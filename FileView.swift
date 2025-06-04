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
        value = next
    }
}

// MARK: - FileView Struct
struct FileView: View {
    @ObservedObject var fileState: FileState
    @Environment(\.undoManager) var envUndoManager

    @State private var contentSize: CGSize = .zero
    @GestureState private var gestureMagnification: CGFloat = 1.0 // Tracks the gesture's current scale factor
    @State private var selectedColorIndex: Int = 1
    
    @State private var currentVisibleSize: CGSize = .zero

    private let minZoom: CGFloat = 0.2
    private let maxZoom: CGFloat = 5.0
    private let toolbarWidth: CGFloat = 180
    private let circleSize: CGFloat = 35
    private let scrollBarInteractiveThickness: CGFloat = 11.0
    
    var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let sensitivityFactor = 0.05 // Make this smaller for less sensitivity
                let incrementalMagnificationChange = value - gestureMagnification
                
                // Apply the sensitive incremental change to the current zoom level
                let proposedZoomLevel = fileState.zoomLevel * (1.0 + incrementalMagnificationChange * sensitivityFactor)
                
                fileState.zoomLevel = proposedZoomLevel.clamped(to: minZoom...maxZoom)
            }
            .onEnded { value in
            }
    }
    
    var body: some View {
        HSplitView {
            GeometryReader { outerGeometry in
                let localVisibleSize = outerGeometry.size
                let globalFrameForOverlay = outerGeometry.frame(in: .global)
                
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        scrollableContentView(
                            visibleSize: localVisibleSize,
                            proxy: proxy,
                            globalFrame: globalFrameForOverlay
                        )
                    }
                    .coordinateSpace(name: "scrollContainerSpace")
                    .onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { oldValue, newValue in
                        let newOffset = newValue
                        let tolerance: CGFloat = 0.1
                        if abs(fileState.scrollOffset.x - newOffset.x) > tolerance || abs(fileState.scrollOffset.y - newOffset.y) > tolerance {
                            fileState.scrollOffset = newOffset
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
                            if contentSize.height > localVisibleSize.height {
                                HStack {
                                    Spacer()
                                    CustomScrollIndicator(
                                        axis: .vertical,
                                        scrollProxy: proxy,
                                        scrollableContentID: "scrollableContent",
                                        currentOffset: $fileState.scrollOffset.y,
                                        otherAxisOffset: fileState.scrollOffset.x,
                                        contentSize: self.contentSize,
                                        visibleSize: localVisibleSize
                                    )
                                    .frame(width: scrollBarInteractiveThickness)
                                }
                                .padding(.bottom, (contentSize.width > localVisibleSize.width) ? scrollBarInteractiveThickness : 0)
                                .frame(maxHeight: .infinity, alignment: .trailing)
                            }
                        }
                    )
                    .overlay(
                        Group {
                            if contentSize.width > localVisibleSize.width {
                                VStack {
                                    Spacer()
                                    CustomScrollIndicator(
                                        axis: .horizontal,
                                        scrollProxy: proxy,
                                        scrollableContentID: "scrollableContent",
                                        currentOffset: $fileState.scrollOffset.x,
                                        otherAxisOffset: fileState.scrollOffset.y,
                                        contentSize: self.contentSize,
                                        visibleSize: localVisibleSize
                                    )
                                    .frame(height: scrollBarInteractiveThickness)
                                }
                                .padding(.trailing, (contentSize.height > localVisibleSize.height) ? scrollBarInteractiveThickness : 0)
                                .frame(maxWidth: .infinity, alignment: .bottom)
                            }
                        }
                    )
                    .onAppear {
                        if fileState.isNewlyOpened {
                            let margin: CGFloat = 100
                            let initialOffsetX = margin
                            let initialOffsetY = margin
                            fileState.scrollOffset = CGPoint(x: initialOffsetX, y: initialOffsetY)
                            fileState.isNewlyOpened = false
                        }
                    }
                }
                .onAppear {
                    self.currentVisibleSize = localVisibleSize
                    DispatchQueue.main.async {
                        let currentContentWidth: CGFloat
                        let currentContentHeight: CGFloat

                        if self.contentSize.width > 0 && self.contentSize.height > 0 {
                             currentContentWidth = self.contentSize.width
                             currentContentHeight = self.contentSize.height
                        } else if let image = fileState.image {
                            let margin: CGFloat = 100
                            currentContentWidth = image.size.width * fileState.zoomLevel + 2 * margin
                            currentContentHeight = image.size.height * fileState.zoomLevel + 2 * margin
                        } else {
                            return
                        }
                        if currentContentWidth > 0 && currentContentHeight > 0 {
                            self.adjustScrollOffsetAfterChange(newContentWidth: currentContentWidth,
                                                               newContentHeight: currentContentHeight)
                        }
                    }
                }
                .onChange(of: localVisibleSize) { oldSize, newSize in
                    self.currentVisibleSize = newSize
                    if self.contentSize.width > 0 && self.contentSize.height > 0 {
                         self.adjustScrollOffsetAfterChange(newContentWidth: self.contentSize.width,
                                                           newContentHeight: self.contentSize.height)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            
            createToolbar()
                .padding()
                .frame(width: toolbarWidth)
        }
        .gesture(magnificationGesture) // Apply gesture to HSplitView
        .onChange(of: fileState.zoomLevel) {
            guard let image = fileState.image, self.currentVisibleSize.width > 0, self.currentVisibleSize.height > 0 else {
                return
            }
            let margin: CGFloat = 100

            let newScaledWidth = image.size.width * fileState.zoomLevel
            let newScaledHeight = image.size.height * fileState.zoomLevel
            let newContentWidth = newScaledWidth + 2 * margin
            let newContentHeight = newScaledHeight + 2 * margin
            
            self.adjustScrollOffsetAfterChange(newContentWidth: newContentWidth, newContentHeight: newContentHeight)
        }
    }
    
    @ViewBuilder
    private func scrollableContentView(visibleSize: CGSize, proxy: ScrollViewProxy, globalFrame: CGRect) -> some View {
        let scrollableContentID = "scrollableContent"
        if fileState.image != nil, fileState.imageWidth > 0, fileState.imageHeight > 0 {
            let scaledWidth = fileState.imageWidth * fileState.zoomLevel
            let scaledHeight = fileState.imageHeight * fileState.zoomLevel
            let margin: CGFloat = 100
            
            ZStack {
                Image(nsImage: fileState.image!)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: scaledWidth, height: scaledHeight)

                GridOverlay(
                    gridData: $fileState.gridData,
                    gridColumns: fileState.gridColumns,
                    gridRows: fileState.gridRows,
                    zoomLevel: fileState.zoomLevel,
                    onPaint: handlePaintAction,
                    selectedColorIndex: selectedColorIndex,
                    scrollProxy: proxy,
                    scrollableContentID: scrollableContentID,
                    externalContentOffset: $fileState.scrollOffset,
                    visibleSize: visibleSize,
                    contentSize: self.contentSize,
                    scrollViewGlobalFrame: globalFrame,
                    contentViewInset: margin
                )
                .frame(width: scaledWidth, height: scaledHeight)
            }
            .padding(margin)
            .frame(width: scaledWidth + 2 * margin, height: scaledHeight + 2 * margin)
            .id(scrollableContentID)
            .contentShape(Rectangle())
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

    private func adjustScrollOffsetAfterChange(newContentWidth: CGFloat, newContentHeight: CGFloat) {
        guard self.currentVisibleSize.width > 0, self.currentVisibleSize.height > 0 else { return }
        
        var clampedX = fileState.scrollOffset.x
        var clampedY = fileState.scrollOffset.y

        if newContentWidth <= 0 || newContentHeight <= 0 {
            clampedX = 0
            clampedY = 0
        } else {
            let maxOffsetX = max(0, newContentWidth - self.currentVisibleSize.width)
            let maxOffsetY = max(0, newContentHeight - self.currentVisibleSize.height)

            if newContentWidth <= self.currentVisibleSize.width {
                clampedX = 0
            } else {
                clampedX = clampedX.clamped(to: 0...maxOffsetX)
            }

            if newContentHeight <= self.currentVisibleSize.height {
                clampedY = 0
            } else {
                clampedY = clampedY.clamped(to: 0...maxOffsetY)
            }
        }
        
        let newClampedOffset = CGPoint(x: clampedX, y: clampedY)

        if fileState.scrollOffset != newClampedOffset {
            fileState.scrollOffset = newClampedOffset
        }
    }
    
    @ViewBuilder
    private func createToolbar() -> some View {
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
                    Button(action: zoomOut) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(fileState.zoomLevel <= minZoom)
                    
                    Text(String(format: "%.1fx", fileState.zoomLevel))
                        .font(.caption)
                        .frame(minWidth: 40)
                    
                    Button(action: zoomIn) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(fileState.zoomLevel >= maxZoom)
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
        fileState.zoomLevel = (fileState.zoomLevel * 1.5).clamped(to: minZoom...maxZoom)
    }

    private func zoomOut() {
        fileState.zoomLevel = (fileState.zoomLevel / 1.5).clamped(to: minZoom...maxZoom)
    }
    
    private func handlePaintAction(cellsToPaint: Set<GridCell>, colorIndex: Int) {
        guard let undoMgr = envUndoManager else {
            applyGridChanges(cells: cellsToPaint, newColor: colorIndex)
            return
        }
        
        let previousValues = Dictionary(uniqueKeysWithValues: cellsToPaint.compactMap { c -> (GridCell, Int)? in
            guard c.isValid(rows: fileState.gridRows, cols: fileState.gridColumns) else { return nil }
            if fileState.gridData.indices.contains(c.row) && fileState.gridData[c.row].indices.contains(c.col) {
                 return (c, fileState.gridData[c.row][c.col])
            }
            return nil
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
                 if s.gridData.indices.contains(c.row) && s.gridData[c.row].indices.contains(c.col) {
                    s.gridData[c.row][c.col] = newColor
                }
            }
        }
    }
    
    private func applyGridChanges(target: FileState? = nil, changes: [GridCell: Int]) {
        let s = target ?? self.fileState
        for (c, v) in changes {
            if c.isValid(rows: s.gridRows, cols: s.gridColumns) {
                if s.gridData.indices.contains(c.row) && s.gridData[c.row].indices.contains(c.col) {
                    s.gridData[c.row][c.col] = v
                }
            }
        }
    }
}

// CGFloat.clamped extension should be available
extension CGFloat {
    func clamped(to limits: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}
