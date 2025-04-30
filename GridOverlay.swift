//
//  GridOverlay.swift
//  Griddy
//
//  Created by Thomas Minzenmay on 23.04.25.
//

import SwiftUI

// MARK: - Supporting Types
struct GridCell: Hashable, CustomStringConvertible {
    let row: Int
    let col: Int
    
    var description: String { "(\(row), \(col))" }
    
    func isValid(rows: Int, cols: Int) -> Bool {
        row >= 0 && row < rows && col >= 0 && col < cols
    }
}

enum Direction: Hashable {
    case left
    case right
    case up
    case down
}

// MARK: - GridOverlay View
struct GridOverlay: View {
    // MARK: - Properties & Bindings
    @Binding var gridData: [[Int]]
    let gridColumns: Int
    let gridRows: Int
    let zoomLevel: CGFloat
    var onPaint: (_ cells: Set<GridCell>, _ colorIndex: Int) -> Void
    let selectedColorIndex: Int
    
    // Context from FileView
    let scrollProxy: ScrollViewProxy
    let scrollableContentID: String
    @Binding var externalContentOffset: CGPoint
    let visibleSize: CGSize
    let contentSize: CGSize // This is the ZStack's size from FileView
    let scrollViewGlobalFrame: CGRect
    let contentViewInset: CGFloat // Margin inside the ZStack, around GridOverlay

    // MARK: - Drag State
    @State private var isDragging: Bool = false
    @State private var dragStartCell: GridCell? = nil
    @State private var dragCurrentCell: GridCell? = nil
    
    // MARK: - Auto-Scroll State & Config
    @State private var autoScrollTimer: Timer? = nil
    @State private var autoScrollDirection: Set<Direction> = []
    private let autoScrollMargin: CGFloat = 60.0
    private let autoScrollTimerInterval: TimeInterval = 0.02
    @State private var scrollSpeedX: CGFloat = 0
    @State private var scrollSpeedY: CGFloat = 0
    
    @State private var initialLocalDragLocationForScrollHandling: CGPoint? = nil
    @State private var initialContentOffsetForScrollHandling: CGPoint? = nil
    
    // MARK: - Computed Properties
    private var cellsInDragRectangle: Set<GridCell> {
        guard let start = dragStartCell, let current = dragCurrentCell else { return [] }
        let minR = min(start.row, current.row)
        let maxR = max(start.row, current.row)
        let minC = min(start.col, current.col)
        let maxC = max(start.col, current.col)
        var cells = Set<GridCell>()
        
        for r in minR...maxR {
            for c in minC...maxC {
                let cell = GridCell(row: r, col: c)
                if cell.isValid(rows: gridRows, cols: gridColumns) {
                    cells.insert(cell)
                }
            }
        }
        return cells
    }
    
    private var isValidGrid: Bool {
        gridRows > 0 && gridColumns > 0 &&
        gridData.count == gridRows && (gridData.first?.count ?? 0) == gridColumns
    }
    
    private let GRID_CELL_SIZE_CONST: CGFloat = GRID_CELL_SIZE

    var body: some View {
        if isValidGrid {
            GeometryReader { geometry in
                let localSize = geometry.size // Size of GridOverlay itself (scaled image size)
                let scaledCellWidth = GRID_CELL_SIZE_CONST * zoomLevel
                let scaledCellHeight = GRID_CELL_SIZE_CONST * zoomLevel
                
                let showGridLines = (scaledCellWidth > 3.0 || scaledCellHeight > 3.0) && zoomLevel > 0.1

                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        guard scaledCellWidth > 0, scaledCellHeight > 0 else { return }

                        let viewportOriginInGridOverlayX = externalContentOffset.x - contentViewInset
                        let viewportOriginInGridOverlayY = externalContentOffset.y - contentViewInset
                        
                        let visibleRectInGridOverlayCoords = CGRect(
                            x: viewportOriginInGridOverlayX,
                            y: viewportOriginInGridOverlayY,
                            width: visibleSize.width,
                            height: visibleSize.height
                        )

                        let startRowCells = max(0, Int(floor(visibleRectInGridOverlayCoords.minY / scaledCellHeight)))
                        let endRowCellsExclusive = min(gridRows, Int(ceil(visibleRectInGridOverlayCoords.maxY / scaledCellHeight)))
                        
                        let startColCells = max(0, Int(floor(visibleRectInGridOverlayCoords.minX / scaledCellWidth)))
                        let endColCellsExclusive = min(gridColumns, Int(ceil(visibleRectInGridOverlayCoords.maxX / scaledCellWidth)))
                        
                        if startRowCells < endRowCellsExclusive && startColCells < endColCellsExclusive {
                            for row in startRowCells..<endRowCellsExclusive {
                                for col in startColCells..<endColCellsExclusive {
                                    if row < gridData.count && col < (gridData.first?.count ?? 0) {
                                        let colorIndex = gridData[row][col]
                                        if colorIndex > 0 {
                                            let x = CGFloat(col) * scaledCellWidth
                                            let y = CGFloat(row) * scaledCellHeight
                                            let rect = CGRect(x: x, y: y, width: scaledCellWidth, height: scaledCellHeight)
                                            context.fill(Path(rect), with: .color(ColorPalette.gridColor(for: colorIndex)))
                                        }
                                    }
                                }
                            }
                        }
                        
                        if showGridLines {
                            let targetScreenPixelLineWidth: CGFloat
                            let lineOpacity: Double

                            if zoomLevel > 2.0 {
                                targetScreenPixelLineWidth = 1.0
                                lineOpacity = 0.60
                            } else if zoomLevel > 1.0 {
                                targetScreenPixelLineWidth = 0.8
                                lineOpacity = 0.45
                            } else if zoomLevel > 0.5 {
                                targetScreenPixelLineWidth = 0.6
                                lineOpacity = 0.35
                            } else {
                                targetScreenPixelLineWidth = 0.5
                                lineOpacity = 0.3
                            }
                            
                            let effectiveZoomLevelForLineWidth = max(0.1, zoomLevel)
                            let lineRenderWidth = max(0.1 / effectiveZoomLevelForLineWidth, targetScreenPixelLineWidth / effectiveZoomLevelForLineWidth)
                            let lineColor = Color.black.opacity(lineOpacity)
                            
                            let lineDrawingMinX = CGFloat(startColCells) * scaledCellWidth
                            let lineDrawingMaxX = CGFloat(endColCellsExclusive) * scaledCellWidth
                            let lineDrawingMinY = CGFloat(startRowCells) * scaledCellHeight
                            let lineDrawingMaxY = CGFloat(endRowCellsExclusive) * scaledCellHeight
                            
                            // Iterate for vertical lines (from col 0 to gridColumns)
                            // but only draw if they are within the visible cell drawing area.
                            let firstLineColToDraw = startColCells
                            let lastLineColToDraw = endColCellsExclusive // Draw line at the right of the last visible column of cells

                            if firstLineColToDraw <= lastLineColToDraw {
                                for col_idx in firstLineColToDraw...lastLineColToDraw {
                                    let x = CGFloat(col_idx) * scaledCellWidth
                                    // Ensure the line itself is within the broader visible area to avoid unnecessary drawing
                                    if x >= visibleRectInGridOverlayCoords.minX - scaledCellWidth && x <= visibleRectInGridOverlayCoords.maxX + scaledCellWidth {
                                        context.stroke(Path { path in
                                            path.move(to: CGPoint(x: x, y: lineDrawingMinY))
                                            path.addLine(to: CGPoint(x: x, y: lineDrawingMaxY))
                                        }, with: .color(lineColor), lineWidth: lineRenderWidth)
                                    }
                                }
                            }
                            
                            // Iterate for horizontal lines (from row 0 to gridRows)
                            let firstLineRowToDraw = startRowCells
                            let lastLineRowToDraw = endRowCellsExclusive // Draw line at the bottom of the last visible row of cells

                            if firstLineRowToDraw <= lastLineRowToDraw {
                                for row_idx in firstLineRowToDraw...lastLineRowToDraw {
                                    let y = CGFloat(row_idx) * scaledCellHeight
                                    if y >= visibleRectInGridOverlayCoords.minY - scaledCellHeight && y <= visibleRectInGridOverlayCoords.maxY + scaledCellHeight {
                                        context.stroke(Path { path in
                                            path.move(to: CGPoint(x: lineDrawingMinX, y: y))
                                            path.addLine(to: CGPoint(x: lineDrawingMaxX, y: y))
                                        }, with: .color(lineColor), lineWidth: lineRenderWidth)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: localSize.width, height: localSize.height)
                    
                    if isDragging, let start = dragStartCell, let current = dragCurrentCell {
                        let minR = min(start.row, current.row)
                        let maxR = max(start.row, current.row)
                        let minC = min(start.col, current.col)
                        let maxC = max(start.col, current.col)
                        
                        let previewX = CGFloat(minC) * scaledCellWidth
                        let previewY = CGFloat(minR) * scaledCellHeight
                        let previewWidth = CGFloat(maxC - minC + 1) * scaledCellWidth
                        let previewHeight = CGFloat(maxR - minR + 1) * scaledCellHeight
                        
                        Rectangle()
                            .fill(calculatePreviewColor())
                            .frame(width: previewWidth, height: previewHeight)
                            .offset(x: previewX, y: previewY)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let localLocation = value.location
                            let currentCell = mapPointToCell(localPoint: localLocation)
                            
                            if !isDragging {
                                isDragging = true
                                dragStartCell = currentCell
                                initialLocalDragLocationForScrollHandling = localLocation
                                initialContentOffsetForScrollHandling = externalContentOffset
                            }
                            
                            if currentCell != dragCurrentCell {
                                dragCurrentCell = currentCell
                            }
                            
                            let mouseLocationInViewport = CGPoint(
                                x: (localLocation.x + contentViewInset) - externalContentOffset.x,
                                y: (localLocation.y + contentViewInset) - externalContentOffset.y
                            )
                            determineScrollDirection(mouseLocalToScrollViewVisibleArea: mouseLocationInViewport)
                            manageAutoScrollTimer()
                        }
                        .onEnded { value in
                            let localLocation = value.location
                            let endCell = mapPointToCell(localPoint: localLocation)
                            dragCurrentCell = endCell
                            
                            let dragDistance = hypot(value.translation.width, value.translation.height)
                            let dragThreshold: CGFloat = 5.0
                            var cellsToPaint = Set<GridCell>()
                            
                            if !isDragging || (dragDistance < dragThreshold && dragStartCell == endCell) {
                                if let cell = endCell, cell.isValid(rows: gridRows, cols: gridColumns) {
                                    cellsToPaint.insert(cell)
                                }
                            } else {
                                cellsToPaint = self.cellsInDragRectangle
                            }
                            
                            if !cellsToPaint.isEmpty {
                                onPaint(cellsToPaint, selectedColorIndex)
                            }
                            resetDragState()
                        }
                )
                .onChange(of: externalContentOffset) { oldOffset, newOffset in
                    if isDragging {
                        if let initialLocalDrag = initialLocalDragLocationForScrollHandling,
                           let initialContentOffset = initialContentOffsetForScrollHandling {
                            
                            let contentScrollDelta = CGPoint(x: newOffset.x - initialContentOffset.x,
                                                             y: newOffset.y - initialContentOffset.y)
                            
                            let currentEffectiveLocalLocation = CGPoint(
                                x: initialLocalDrag.x - contentScrollDelta.x,
                                y: initialLocalDrag.y - contentScrollDelta.y
                            )
                            
                            let currentCell = mapPointToCell(localPoint: currentEffectiveLocalLocation)
                            
                            if let cell = currentCell, cell != dragCurrentCell {
                                dragCurrentCell = cell
                            }
                        }
                    }
                }
            }
        } else {
            Text("Invalid Grid State")
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
        
    private func calculatePreviewColor() -> Color {
        selectedColorIndex == 0 ? Color.white.opacity(0.4) : ColorPalette.gridColor(for: selectedColorIndex).opacity(0.6)
    }
    
    private func mapPointToCell(localPoint: CGPoint) -> GridCell? {
        guard GRID_CELL_SIZE_CONST > 0, zoomLevel > 0, gridColumns > 0, gridRows > 0 else { return nil }
        
        let currentCellWidth = GRID_CELL_SIZE_CONST * zoomLevel
        let currentCellHeight = GRID_CELL_SIZE_CONST * zoomLevel

        guard currentCellWidth > 0, currentCellHeight > 0 else { return nil }
        
        let col = Int(floor(localPoint.x / currentCellWidth))
        let row = Int(floor(localPoint.y / currentCellHeight))
        
        let cell = GridCell(row: row, col: col)
        return cell.isValid(rows: gridRows, cols: gridColumns) ? cell : nil
    }
    
    private func determineScrollDirection(mouseLocalToScrollViewVisibleArea: CGPoint) {
        var directions: Set<Direction> = []
        let maxScrollSpeed: CGFloat = 1500.0
        
        scrollSpeedX = 0
        scrollSpeedY = 0
        
        if mouseLocalToScrollViewVisibleArea.x < autoScrollMargin {
            directions.insert(.left)
            scrollSpeedX = -((1.0 - max(0, mouseLocalToScrollViewVisibleArea.x) / autoScrollMargin).clamped(to: 0...1) * maxScrollSpeed)
        } else if mouseLocalToScrollViewVisibleArea.x > visibleSize.width - autoScrollMargin {
            directions.insert(.right)
            let distFromRightEdge = visibleSize.width - mouseLocalToScrollViewVisibleArea.x
            scrollSpeedX = (1.0 - max(0, distFromRightEdge) / autoScrollMargin).clamped(to: 0...1) * maxScrollSpeed
        }
        
        if mouseLocalToScrollViewVisibleArea.y < autoScrollMargin {
            directions.insert(.up)
            scrollSpeedY = -((1.0 - max(0, mouseLocalToScrollViewVisibleArea.y) / autoScrollMargin).clamped(to: 0...1) * maxScrollSpeed)
        } else if mouseLocalToScrollViewVisibleArea.y > visibleSize.height - autoScrollMargin {
            directions.insert(.down)
            let distFromBottomEdge = visibleSize.height - mouseLocalToScrollViewVisibleArea.y
            scrollSpeedY = (1.0 - max(0, distFromBottomEdge) / autoScrollMargin).clamped(to: 0...1) * maxScrollSpeed
        }
        
        self.autoScrollDirection = directions
    }
    
    private func manageAutoScrollTimer() {
        let shouldBeScrolling = isDragging && !autoScrollDirection.isEmpty
        
        if shouldBeScrolling && autoScrollTimer == nil {
            autoScrollTimer = Timer.scheduledTimer(withTimeInterval: autoScrollTimerInterval, repeats: true) { timer in
                DispatchQueue.main.async {
                    if self.isDragging && !self.autoScrollDirection.isEmpty {
                        self.performAutoScroll()
                    } else {
                        timer.invalidate()
                        self.autoScrollTimer = nil
                    }
                }
            }
        } else if (!shouldBeScrolling || !isDragging) && autoScrollTimer != nil {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
        }
    }
    
    private func performAutoScroll() {
        guard !autoScrollDirection.isEmpty else { return }
        
        let deltaX = scrollSpeedX * autoScrollTimerInterval
        let deltaY = scrollSpeedY * autoScrollTimerInterval
        
        var targetX = externalContentOffset.x + deltaX
        var targetY = externalContentOffset.y + deltaY
        
        let maxX = max(0, self.contentSize.width - self.visibleSize.width)
        let maxY = max(0, self.contentSize.height - self.visibleSize.height)
        
        targetX = targetX.clamped(to: 0...maxX)
        targetY = targetY.clamped(to: 0...maxY)
        
        let targetOffset = CGPoint(x: targetX, y: targetY)
        
        if targetOffset != externalContentOffset {
            let scrollableWidth = self.contentSize.width - self.visibleSize.width
            let scrollableHeight = self.contentSize.height - self.visibleSize.height
            
            let anchorX = scrollableWidth > 0 ? (targetX / scrollableWidth).clamped(to: 0...1) : 0.5
            let anchorY = scrollableHeight > 0 ? (targetY / scrollableHeight).clamped(to: 0...1) : 0.5
            
            scrollProxy.scrollTo(scrollableContentID, anchor: UnitPoint(x: anchorX, y: anchorY))
        }
    }
    
    private func resetDragState() {
        isDragging = false
        dragStartCell = nil
        dragCurrentCell = nil
        initialLocalDragLocationForScrollHandling = nil
        initialContentOffsetForScrollHandling = nil
        
        if autoScrollTimer != nil {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
        }
        autoScrollDirection = []
        scrollSpeedX = 0
        scrollSpeedY = 0
    }
}
