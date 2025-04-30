//
//  FileView.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 23.04.25.
//

import SwiftUI
import AppKit

// MARK: - Preference Keys
struct ScrollViewOffsetKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

struct ScrollViewContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: Swift.max(value.width, next.width), height: Swift.max(value.height, next.height))
    }
}

// MARK: - FileView Struct
struct FileView: View {
    @ObservedObject var fileState: FileState
    @Environment(\.undoManager) var envUndoManager
    
    @State private var contentSize: CGSize = .zero
    @State private var scrollOffset: CGPoint = .zero
    @State private var selectedColorIndex: Int = 1
    @State private var zoomLevel: CGFloat = 1.0
    @GestureState private var gestureMagnification: CGFloat = 1.0
    @State private var committedZoomLevel: CGFloat = 1.0
    
    private let minZoom: CGFloat = 0.2
    private let maxZoom: CGFloat = 10.0
    private let zoomSensitivity: CGFloat = 0.9
    private let toolbarWidth: CGFloat = 180
    private let circleSize: CGFloat = 35
    private let scrollBarInteractiveThickness: CGFloat = 11.0
    
    var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureMagnification) { currentState, gestureState, transaction in
                let desiredZoom = committedZoomLevel * currentState
                let sensitiveZoom = committedZoomLevel + (desiredZoom - committedZoomLevel) * zoomSensitivity
                self.zoomLevel = max(self.minZoom, min(sensitiveZoom, self.maxZoom))
                gestureState = currentState
            }
            .onEnded { value in
                let finalDesiredZoom = committedZoomLevel * value
                let finalSensitiveZoom = committedZoomLevel + (finalDesiredZoom - committedZoomLevel) * zoomSensitivity
                let finalClampedZoom = max(self.minZoom, min(finalSensitiveZoom, self.maxZoom))
                withAnimation(.interactiveSpring()) { self.zoomLevel = finalClampedZoom }
                self.committedZoomLevel = finalClampedZoom
            }
    }
    
    var body: some View {
        HSplitView {
            GeometryReader { outerGeometry in
                let visibleSize = outerGeometry.size
                let globalFrameForOverlay = outerGeometry.frame(in: .global)
                
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        scrollableContentView(
                            visibleSize: visibleSize,
                            proxy: proxy,
                            globalFrame: globalFrameForOverlay
                        )
                    }
                    .coordinateSpace(name: "scrollContainerSpace")
                    .onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { oldValue, newValue in
                        let newOffset = newValue
                        let tolerance: CGFloat = 0.1
                        if abs(scrollOffset.x - newOffset.x) > tolerance || abs(scrollOffset.y - newOffset.y) > tolerance {
                            self.scrollOffset = newOffset
                        }
                    }
                    .onScrollGeometryChange(for: CGSize.self, of: { $0.contentSize }) { oldValue, newValue in
                        let newSize = newValue
                        if newSize.width > 0 && newSize.height > 0 && self.contentSize != newSize {
                            self.contentSize = newSize
                        }
                    }
                    .overlay(
                        Group {
                            if contentSize.height > visibleSize.height {
                                HStack {
                                    Spacer()
                                    CustomScrollIndicator(
                                        axis: .vertical,
                                        scrollProxy: proxy,
                                        scrollableContentID: "scrollableContent",
                                        currentOffset: $scrollOffset.y,
                                        otherAxisOffset: scrollOffset.x,
                                        contentSize: contentSize,
                                        visibleSize: visibleSize
                                    )
                                    .frame(width: scrollBarInteractiveThickness)
                                }
                                .padding(.bottom, scrollBarInteractiveThickness)
                                .frame(maxHeight: .infinity, alignment: .trailing)
                            }
                        }
                    )
                    .overlay(
                        Group {
                            if contentSize.width > visibleSize.width {
                                VStack {
                                    Spacer()
                                    CustomScrollIndicator(
                                        axis: .horizontal,
                                        scrollProxy: proxy,
                                        scrollableContentID: "scrollableContent",
                                        currentOffset: $scrollOffset.x,
                                        otherAxisOffset: scrollOffset.y,
                                        contentSize: contentSize,
                                        visibleSize: visibleSize
                                    )
                                    .frame(height: scrollBarInteractiveThickness)
                                }
                                .padding(.trailing, scrollBarInteractiveThickness)
                                .frame(maxWidth: .infinity, alignment: .bottom)
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            
            createToolbar()
                .padding()
                .frame(width: toolbarWidth)
        }
        .onAppear {
            self.zoomLevel = 1.0
            self.committedZoomLevel = 1.0
        }
        .onChange(of: fileState.id) {
            self.zoomLevel = 1.0
            self.committedZoomLevel = 1.0
        }
    }
    
    @ViewBuilder
    private func scrollableContentView(visibleSize: CGSize, proxy: ScrollViewProxy, globalFrame: CGRect) -> some View {
        let scrollableContentID = "scrollableContent"
        
        ZStack(alignment: .topLeading) {
            if let image = fileState.image, fileState.imageWidth > 0, fileState.imageHeight > 0 {
                let scaledWidth = fileState.imageWidth * zoomLevel
                let scaledHeight = fileState.imageHeight * zoomLevel
                
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: scaledWidth, height: scaledHeight)
                        .gesture(magnificationGesture)
                    
                    GridOverlay(
                        gridData: $fileState.gridData,
                        gridColumns: fileState.gridColumns,
                        gridRows: fileState.gridRows,
                        zoomLevel: zoomLevel,
                        onPaint: handlePaintAction,
                        selectedColorIndex: selectedColorIndex,
                        scrollProxy: proxy,
                        scrollableContentID: scrollableContentID,
                        externalContentOffset: $scrollOffset,
                        visibleSize: visibleSize,
                        contentSize: contentSize,
                        scrollViewGlobalFrame: globalFrame
                    )
                    .frame(width: scaledWidth, height: scaledHeight)
                    .contentShape(Rectangle())
                }
                .frame(width: scaledWidth, height: scaledHeight)
                .id(scrollableContentID)
                .background(
                    GeometryReader { contentGeo in
                        Color.clear
                            .preference(
                                key: ScrollViewOffsetKey.self,
                                value: contentGeo.frame(in: .named("scrollContainerSpace")).origin
                            )
                    }
                )
                .background(
                    GeometryReader { contentGeo in
                        Color.clear
                            .preference(
                                key: ScrollViewContentSizeKey.self,
                                value: contentGeo.size
                            )
                    }
                )
            } else {
                Text("No Valid Image Loaded")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .foregroundColor(.red)
            }
        }
        .frame(minWidth: visibleSize.width, minHeight: visibleSize.height)
        .alignmentGuide(.top) { d in d[.top] }
        .alignmentGuide(.leading) { d in d[.leading] }
    }
    
    // MARK: - Toolbar View Builder
    @ViewBuilder
    private func createToolbar() -> some View {
        // Use GeometryReader to get the available height for the toolbar content
        GeometryReader { geometry in
            let availableHeight = geometry.size.height
            let zoomControlsHeight: CGFloat = 30
            let selectedTextHeight: CGFloat = 20
            let uniqueTilesHeight: CGFloat = 20
            let verticalPadding: CGFloat = 32
            let vStackSpacingTotal: CGFloat = 30
            let singleColumnColorListHeight: CGFloat = (circleSize * CGFloat(ColorPalette.colors.count)) + (8 * CGFloat(ColorPalette.colors.count - 1))
            let singleColumnMinHeight = zoomControlsHeight + selectedTextHeight + singleColumnColorListHeight + uniqueTilesHeight + vStackSpacingTotal + verticalPadding
            let layoutSwitchThreshold = singleColumnMinHeight + 10
            
            VStack(alignment: .center, spacing: 10) {
                HStack {
                    Button(action: zoomOut) { Image(systemName: "minus.magnifyingglass") }
                        .disabled(zoomLevel <= minZoom)
                    
                    Text(String(format: "%.1fx", zoomLevel))
                        .font(.caption)
                        .frame(minWidth: 40)
                    
                    Button(action: zoomIn) { Image(systemName: "plus.magnifyingglass") }
                        .disabled(zoomLevel >= maxZoom)
                }
                .padding(.bottom, 10)
                
                Text("Selected: \(ColorPalette.name(for: selectedColorIndex)) (\(selectedColorIndex))")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.bottom, 5)
                
                if availableHeight < layoutSwitchThreshold {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 8) {
                            ForEach(0...4, id: \.self) { i in
                                Button(action: { selectedColorIndex = i }) { colorCircleView(for: i) }
                                    .buttonStyle(.plain)
                            }
                        }
                        
                        VStack(spacing: 8) {
                            ForEach(5..<ColorPalette.colors.count, id: \.self) { i in
                                Button(action: { selectedColorIndex = i }) { colorCircleView(for: i) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(0..<ColorPalette.colors.count, id: \.self) { i in
                                Button(action: { selectedColorIndex = i }) { colorCircleView(for: i) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 5)
                    }
                }
                
                Text("Unique Tiles: \(fileState.uniqueTileCount)")
                    .font(.caption)
                    .padding(.top, 5)
                
                Spacer()
            }
            .padding()
        }
        .frame(width: toolbarWidth)
    }
    
    @ViewBuilder
    private func colorCircleView(for index: Int) -> some View {
        ZStack {
            Circle()
                .fill(ColorPalette.displayColor(for: index))
                .frame(width: circleSize, height: circleSize)
                .overlay(
                    Circle()
                        .stroke(selectedColorIndex == index ? Color.accentColor : .gray.opacity(0.5),
                                lineWidth: selectedColorIndex == index ? 3 : 1)
                )
            
            if index == 0 {
                let i = circleSize * 0.25
                Path { p in
                    p.move(to: .init(x: i, y: i))
                    p.addLine(to: .init(x: circleSize - i, y: circleSize - i))
                }
                .stroke(.red, lineWidth: 2)
            } else {
                Text("\(index)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isLightColor(index) ? .black : .white)
                    .shadow(color: .black.opacity(0.4), radius: 0.5, x: 0.5, y: 0.5)
            }
        }
        .frame(width: circleSize, height: circleSize)
    }
    
    private func isLightColor(_ index: Int) -> Bool {
        return [4, 7, 9].contains(index) || index == 0
    }
    
    private func zoomIn() {
        applyZoom(min(maxZoom, committedZoomLevel * 1.5))
    }
    
    private func zoomOut() {
        applyZoom(max(minZoom, committedZoomLevel / 1.5))
    }
    
    private func applyZoom(_ newZoom: CGFloat) {
        withAnimation(.interactiveSpring()) { zoomLevel = newZoom }
        committedZoomLevel = newZoom
    }
    
    private func handlePaintAction(cellsToPaint: Set<GridCell>, colorIndex: Int) {
        guard let undoMgr = envUndoManager else {
            applyGridChanges(cells: cellsToPaint, newColor: colorIndex)
            return
        }
        
        let previousValues = Dictionary(uniqueKeysWithValues: cellsToPaint.compactMap { c -> (GridCell, Int)? in
            guard c.isValid(rows: fileState.gridRows, cols: fileState.gridColumns) else { return nil }
            return (c, fileState.gridData[c.row][c.col])
        })
        
        applyGridChanges(cells: cellsToPaint, newColor: colorIndex)
        
        undoMgr.registerUndo(withTarget: fileState) { tFS in
            self.applyGridChanges(target: tFS, changes: previousValues)
            undoMgr.registerUndo(withTarget: tFS) { rTFS in
                self.applyGridChanges(target: rTFS, cells: cellsToPaint, newColor: colorIndex)
                undoMgr.setActionName("Paint")
            }
            undoMgr.setActionName("Paint")
        }
        
        undoMgr.setActionName("Paint")
    }
    
    private func applyGridChanges(target: FileState? = nil, cells: Set<GridCell>, newColor: Int) {
        let s = target ?? self.fileState
        for c in cells {
            if c.isValid(rows: s.gridRows, cols: s.gridColumns) {
                s.gridData[c.row][c.col] = newColor
            }
        }
    }
    
    private func applyGridChanges(target: FileState? = nil, changes: [GridCell: Int]) {
        let s = target ?? self.fileState
        for (c, v) in changes {
            if c.isValid(rows: s.gridRows, cols: s.gridColumns) {
                s.gridData[c.row][c.col] = v
            }
        }
    }
}
