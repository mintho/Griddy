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
        // Ensure we take the actual reported content size, not just max.
        // This key is intended to report the single content's size.
        value = next
    }
}

// MARK: - FileView Struct
struct FileView: View {
    @ObservedObject var fileState: FileState
    @Environment(\.undoManager) var envUndoManager

    @State private var contentSize: CGSize = .zero // Tracks the ZStack's size
    @GestureState private var gestureMagnification: CGFloat = 1.0
    @State private var selectedColorIndex: Int = 1
    
    @State private var currentVisibleSize: CGSize = .zero // ADDED: For viewport size

    private let minZoom: CGFloat = 0.2
    private let maxZoom: CGFloat = 5.0
    // private let zoomSensitivity: CGFloat = 0.4 // Not currently used directly
    private let toolbarWidth: CGFloat = 180
    private let circleSize: CGFloat = 35
    private let scrollBarInteractiveThickness: CGFloat = 11.0
    
    var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Directly apply zoom factor to the committed zoom level for smoother feel
                // The 'value' is a multiplier from the start of the gesture.
                // We need to manage the committed zoom level carefully.
                // Let's assume gestureMagnification starts at 1.0 (from @GestureState)
                // and fileState.zoomLevel is the "committed" zoom.
                // This approach seems to accumulate too much.
                // A better way for live gesture:
                // Store zoom at gesture start, then newZoom = startZoom * value
                // For now, let's stick to the previous simpler approach if it worked,
                // and focus on offset clamping. The previous simpler gesture was:
                let sensitivity: CGFloat = 0.1
                let delta = value - 1.0 // value is total magnification since gesture start
                let scaledDelta = delta * sensitivity
                // This needs to be applied to the zoom level AT THE START of this specific onChanged event,
                // or manage a temporary zoom factor.
                // Simpler: if fileState.zoomLevel is updated, the .onChange will handle clamping.
                // The key is that `value` in `onChanged` is relative to the start of the gesture.
                // So, if we directly use it like `fileState.zoomLevel * value`, it will grow too fast
                // if `fileState.zoomLevel` is also being updated by the gesture.
                // Let's assume the original simple approach was intended:
                // fileState.zoomLevel = (committedZoomLevelAtGestureStart * value).clamped(to: minZoom...maxZoom)
                // Since we don't have committedZoomLevelAtGestureStart easily here without more state,
                // the .onChange(of: fileState.zoomLevel) is our main defense.
                // The previous simple logic for gesture:
                let proposedZoomLevel = fileState.zoomLevel * (1.0 + (value - gestureMagnification) * 0.5) // Incremental change
                fileState.zoomLevel = proposedZoomLevel.clamped(to: minZoom...maxZoom)
                // gestureMagnification is reset by @GestureState, so this makes sense.
            }
            .onEnded { value in
                // Final adjustment if needed, .onChange will also fire
                // fileState.zoomLevel = (fileState.zoomLevel * value).clamped(to: minZoom...maxZoom); // This was likely wrong before
                // The onEnded value is the final magnification of the gesture.
                // If onChanged updated it incrementally, onEnded might just confirm or do nothing new.
                // The important part is that fileState.zoomLevel is now set.
            }
    }
    
    var body: some View {
        HSplitView {
            GeometryReader { outerGeometry in
                let localVisibleSize = outerGeometry.size // Use this for direct passing
                let globalFrameForOverlay = outerGeometry.frame(in: .global)
                
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        scrollableContentView(
                            visibleSize: localVisibleSize, // Pass current actual visible size
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
                            self.contentSize = newSize // This is the ZStack's size
                        }
                    }
                    .overlay(
                        Group { // Vertical Scrollbar
                            if contentSize.height > localVisibleSize.height {
                                HStack {
                                    Spacer()
                                    CustomScrollIndicator(
                                        axis: .vertical,
                                        scrollProxy: proxy,
                                        scrollableContentID: "scrollableContent",
                                        currentOffset: $fileState.scrollOffset.y,
                                        otherAxisOffset: fileState.scrollOffset.x,
                                        contentSize: self.contentSize, // Use the state var for ZStack size
                                        visibleSize: localVisibleSize  // Use current viewport size
                                    )
                                    .frame(width: scrollBarInteractiveThickness)
                                }
                                .padding(.bottom, (contentSize.width > localVisibleSize.width) ? scrollBarInteractiveThickness : 0) // Avoid overlap
                                .frame(maxHeight: .infinity, alignment: .trailing)
                            }
                        }
                    )
                    .overlay(
                        Group { // Horizontal Scrollbar
                            if contentSize.width > localVisibleSize.width {
                                VStack {
                                    Spacer()
                                    CustomScrollIndicator(
                                        axis: .horizontal,
                                        scrollProxy: proxy,
                                        scrollableContentID: "scrollableContent",
                                        currentOffset: $fileState.scrollOffset.x,
                                        otherAxisOffset: fileState.scrollOffset.y,
                                        contentSize: self.contentSize, // Use the state var for ZStack size
                                        visibleSize: localVisibleSize  // Use current viewport size
                                    )
                                    .frame(height: scrollBarInteractiveThickness)
                                }
                                .padding(.trailing, (contentSize.height > localVisibleSize.height) ? scrollBarInteractiveThickness : 0) // Avoid overlap
                                .frame(maxWidth: .infinity, alignment: .bottom)
                            }
                        }
                    )
                    .onAppear {
                        if fileState.isNewlyOpened {
                            let margin: CGFloat = 100
                            let initialOffsetX = margin
                            let initialOffsetY = margin
                            // Ensure offset is valid for initial content and view size
                            // This will be handled by adjustScrollOffsetAfterChange called from outer .onAppear
                            fileState.scrollOffset = CGPoint(x: initialOffsetX, y: initialOffsetY)
                            fileState.isNewlyOpened = false
                        }
                        // else {
                        // This part was problematic and could lead to recursive updates or race conditions.
                        // Rely on scrollOffset binding and .onChange for adjustments.
                        // let targetAnchor = calculateAnchor(from: fileState.scrollOffset, visibleSize: localVisibleSize)
                        // proxy.scrollTo("scrollableContent", anchor: targetAnchor)
                        // }
                    }
                }
                .onAppear { // For the GeometryReader itself
                    self.currentVisibleSize = localVisibleSize
                    DispatchQueue.main.async { // Allow contentSize preference to be updated
                        if self.contentSize.width > 0 && self.contentSize.height > 0 {
                             self.adjustScrollOffsetAfterChange(newContentWidth: self.contentSize.width,
                                                               newContentHeight: self.contentSize.height)
                        } else if let image = fileState.image { // Fallback if contentSize not set yet
                            let margin: CGFloat = 100
                            let initialContentWidth = image.size.width * fileState.zoomLevel + 2 * margin
                            let initialContentHeight = image.size.height * fileState.zoomLevel + 2 * margin
                            if initialContentWidth > 0 && initialContentHeight > 0 {
                                self.adjustScrollOffsetAfterChange(newContentWidth: initialContentWidth,
                                                                   newContentHeight: initialContentHeight)
                            }
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
        .gesture(magnificationGesture)
        .onChange(of: fileState.zoomLevel) {
            // This is the primary handler for zoom changes from any source (buttons, gesture)
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
        // Use fileState.imageWidth/Height which are set on init, not direct image?.size
        if fileState.image != nil, fileState.imageWidth > 0, fileState.imageHeight > 0 {
            let scaledWidth = fileState.imageWidth * fileState.zoomLevel
            let scaledHeight = fileState.imageHeight * fileState.zoomLevel
            let margin: CGFloat = 100
            
            ZStack { // This ZStack's frame becomes self.contentSize via preference key
                Image(nsImage: fileState.image!) // Safe to unwrap due to guard above
                    .resizable()
                    .interpolation(.none)
                    .frame(width: scaledWidth, height: scaledHeight)
                    // Position GridOverlay and Image at the same logical place if margin is for ZStack
                    // The ZStack is (image + 2*margin). Image is at its center.
                    // GridOverlay should map to the image part.
                    .position(x: scaledWidth / 2, y: scaledHeight / 2) // Position image at top-left of its own frame

                GridOverlay(
                    gridData: $fileState.gridData,
                    gridColumns: fileState.gridColumns,
                    gridRows: fileState.gridRows,
                    zoomLevel: fileState.zoomLevel,
                    onPaint: handlePaintAction,
                    selectedColorIndex: selectedColorIndex,
                    scrollProxy: proxy,
                    scrollableContentID: scrollableContentID,
                    externalContentOffset: $fileState.scrollOffset, // This is offset of ZStack
                    visibleSize: visibleSize,                       // Viewport size
                    contentSize: self.contentSize,                  // ZStack size (image + 2*margin)
                    scrollViewGlobalFrame: globalFrame,
                    contentViewInset: margin                        // The margin for GridOverlay's own content
                )
                .frame(width: scaledWidth, height: scaledHeight) // GridOverlay matches image size
                // .position(x: scaledWidth / 2, y: scaledHeight / 2) // Positioned by ZStack implicitly
            }
            // The ZStack has the margin applied. Its origin is (0,0) in its own space.
            // Its content (Image, GridOverlay) is positioned from its (0,0).
            // So scrollOffset is (margin, margin) for initial view.
            // GridOverlay needs to know that fileState.scrollOffset.x = margin means its visual left edge is at viewport left.
            .padding(margin) // Apply padding to the ZStack to create the margin
            .frame(width: scaledWidth + 2 * margin, height: scaledHeight + 2 * margin) // Explicit frame for preference key
            .id(scrollableContentID)
            .contentShape(Rectangle())
            // .simultaneousGesture(magnificationGesture) // Already on HSplitView
            .background( // For ScrollViewOffsetKey (offset of this ZStack inside ScrollView)
                GeometryReader { contentGeo in
                    Color.clear
                        .preference(
                            key: ScrollViewOffsetKey.self,
                            value: contentGeo.frame(in: .named("scrollContainerSpace")).origin
                        )
                }
            )
            .background( // For ScrollViewContentSizeKey (size of this ZStack)
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

        if newContentWidth <= 0 || newContentHeight <= 0 { // Invalid new content size
            clampedX = 0
            clampedY = 0
        } else {
            let maxOffsetX = max(0, newContentWidth - self.currentVisibleSize.width)
            let maxOffsetY = max(0, newContentHeight - self.currentVisibleSize.height)

            if newContentWidth <= self.currentVisibleSize.width {
                clampedX = 0 // Center if smaller, or stick to 0
            } else {
                clampedX = clampedX.clamped(to: 0...maxOffsetX)
            }

            if newContentHeight <= self.currentVisibleSize.height {
                clampedY = 0 // Center if smaller, or stick to 0
            } else {
                clampedY = clampedY.clamped(to: 0...maxOffsetY)
            }
        }
        
        let newClampedOffset = CGPoint(x: clampedX, y: clampedY)

        if fileState.scrollOffset != newClampedOffset {
            fileState.scrollOffset = newClampedOffset
        }
    }
    
    // MARK: - Toolbar View Builder
    @ViewBuilder
    private func createToolbar() -> some View {
        // ... (toolbar code remains the same)
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
        // ... (colorCircleView code remains the same)
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
        // ... (isLightColor code remains the same)
        return [4, 7, 9].contains(index) || index == 0
    }
    
    private func zoomIn() {
        fileState.zoomLevel = (fileState.zoomLevel * 1.5).clamped(to: minZoom...maxZoom)
    }

    private func zoomOut() {
        fileState.zoomLevel = (fileState.zoomLevel / 1.5).clamped(to: minZoom...maxZoom)
    }
    
    private func handlePaintAction(cellsToPaint: Set<GridCell>, colorIndex: Int) {
        // ... (handlePaintAction code remains the same)
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
        // ... (applyGridChanges code remains the same)
        let s = target ?? self.fileState
        for c in cells {
            if c.isValid(rows: s.gridRows, cols: s.gridColumns) {
                s.gridData[c.row][c.col] = newColor
            }
        }
    }
    
    private func applyGridChanges(target: FileState? = nil, changes: [GridCell: Int]) {
        // ... (applyGridChanges code remains the same)
        let s = target ?? self.fileState
        for (c, v) in changes {
            if c.isValid(rows: s.gridRows, cols: s.gridColumns) {
                s.gridData[c.row][c.col] = v
            }
        }
    }
    
    // Removed calculateAnchor as it's not used directly for now.
    // If needed for programmatic scroll-to-center, it can be re-added.
}

// Add clamped extension for CGFloat if not already globally available
extension CGFloat {
    func clamped(to limits: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}
