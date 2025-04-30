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
    let contentSize: CGSize
    let scrollViewGlobalFrame: CGRect
    
    // MARK: - Drag State
    @State private var isDragging: Bool = false
    @State private var dragStartCell: GridCell? = nil
    @State private var dragCurrentCell: GridCell? = nil
    
    // MARK: - Auto-Scroll State & Config
    @State private var autoScrollTimer: Timer? = nil
    @State private var autoScrollDirection: Set<Direction> = []
    @State private var localDragLocation: CGPoint = .zero
    private let autoScrollMargin: CGFloat = 50.0
    private let autoScrollAmount: CGFloat = 15.0
    private let autoScrollTimerInterval: TimeInterval = 0.02
    
    // MARK: - Additional State for Continuous Updates
    @State private var initialLocalDragLocation: CGPoint? = nil
    @State private var initialContentOffset: CGPoint? = nil
    
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
        gridRows > 0 && gridColumns > 0 && gridData.count == gridRows && gridData.first?.count == gridColumns
    }
    
    private let GRID_CELL_SIZE: CGFloat = 8.0
    
    // MARK: - Body
    var body: some View {
        if isValidGrid {
            GeometryReader { geometry in
                let localSize = geometry.size
                let cellWidth = gridColumns > 0 ? localSize.width / CGFloat(gridColumns) : 0
                let cellHeight = gridRows > 0 ? localSize.height / CGFloat(gridRows) : 0
                let scaledCellSize = GRID_CELL_SIZE * zoomLevel
                let showGridLines = scaledCellSize > 4
                
                ZStack(alignment: .topLeading) {
                    drawGridCells(in: geometry.frame(in: .local), cellWidth: cellWidth, cellHeight: cellHeight)
                    
                    if showGridLines {
                        drawGridLines(in: geometry.frame(in: .local), cellWidth: cellWidth, cellHeight: cellHeight)
                    }
                    
                    if isDragging {
                        drawDragPreview(in: geometry.frame(in: .local), cellWidth: cellWidth, cellHeight: cellHeight)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let localLocation = value.location
                            self.localDragLocation = localLocation
                            initialLocalDragLocation = localLocation
                            initialContentOffset = externalContentOffset
                            let currentCell = mapPointToCell(localPoint: localLocation)
                            
                            if !isDragging {
                                isDragging = true
                                dragStartCell = currentCell
                                dragCurrentCell = currentCell
                            } else if currentCell != dragCurrentCell {
                                dragCurrentCell = currentCell
                            }
                            
                            determineScrollDirection()
                            manageAutoScrollTimer()
                        }
                        .onEnded { value in
                            let localLocation = value.location
                            self.localDragLocation = localLocation
                            let endCell = mapPointToCell(localPoint: localLocation)
                            dragCurrentCell = endCell
                            
                            let dragDistance = hypot(value.translation.width, value.translation.height)
                            let dragThreshold: CGFloat = 5.0
                            var cellsToPaint = Set<GridCell>()
                            
                            // Determine if it's a single cell click or a drag rectangle
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
                .onChange(of: externalContentOffset) { _, newOffset in
                    if isDragging {
                        if let initialLoc = initialLocalDragLocation, let initialOff = initialContentOffset {
                            let delta = CGPoint(x: newOffset.x - initialOff.x, y: newOffset.y - initialOff.y)
                            let currentLoc = CGPoint(x: initialLoc.x + delta.x, y: initialLoc.y + delta.y)
                            let currentCell = mapPointToCell(localPoint: currentLoc)
                            
                            if let cell = currentCell {
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
    
    // MARK: - Drawing Helpers
    @ViewBuilder
    private func drawGridCells(in rect: CGRect, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        if cellWidth > 0 && cellHeight > 0 && gridRows > 0 && gridColumns > 0 {
            ZStack(alignment: .topLeading) {
                ForEach(0..<gridRows, id: \.self) { row in
                    ForEach(0..<gridColumns, id: \.self) { col in
                        if row < gridData.count && col < gridData[row].count {
                            let colorIndex = gridData[row][col]
                            if colorIndex > 0 {
                                let x = CGFloat(col) * cellWidth
                                let y = CGFloat(row) * cellHeight
                                
                                Rectangle()
                                    .fill(ColorPalette.gridColor(for: colorIndex))
                                    .frame(width: cellWidth, height: cellHeight)
                                    .offset(x: x, y: y)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func drawGridLines(in rect: CGRect, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        if cellWidth > 0 && cellHeight > 0 && gridRows > 0 && gridColumns > 0 {
            Path { path in
                for col in 0...gridColumns {
                    let x = CGFloat(col) * cellWidth
                    path.move(to: CGPoint(x: x, y: rect.minY))
                    path.addLine(to: CGPoint(x: x, y: rect.maxY))
                }
                
                for row in 0...gridRows {
                    let y = CGFloat(row) * cellHeight
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
            }
            .stroke(Color.black.opacity(0.3), lineWidth: max(0.1, 0.5 / zoomLevel))
        }
    }
    
    @ViewBuilder
    private func drawDragPreview(in rect: CGRect, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        if cellWidth > 0 && cellHeight > 0 && gridRows > 0 && gridColumns > 0 {
            let previewColor = calculatePreviewColor()
            
            ZStack(alignment: .topLeading) {
                ForEach(Array(cellsInDragRectangle), id: \.self) { cell in
                    if cell.isValid(rows: gridRows, cols: gridColumns) {
                        Rectangle()
                            .fill(previewColor)
                            .frame(width: cellWidth, height: cellHeight)
                            .offset(x: CGFloat(cell.col) * cellWidth, y: CGFloat(cell.row) * cellHeight)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
    
    private func calculatePreviewColor() -> Color {
        selectedColorIndex == 0 ? Color.white.opacity(0.4) : ColorPalette.gridColor(for: selectedColorIndex).opacity(0.6)
    }
    
    // MARK: - Cell Mapping
    private func mapPointToCell(localPoint: CGPoint) -> GridCell? {
        guard GRID_CELL_SIZE > 0, zoomLevel > 0 else { return nil }
        let renderedCellWidth = GRID_CELL_SIZE * zoomLevel
        let renderedCellHeight = GRID_CELL_SIZE * zoomLevel
        guard renderedCellWidth > 0, renderedCellHeight > 0 else { return nil }
        
        let col = Int(floor(localPoint.x / renderedCellWidth))
        let row = Int(floor(localPoint.y / renderedCellHeight))
        let cell = GridCell(row: row, col: col)
        
        return cell.isValid(rows: gridRows, cols: gridColumns) ? cell : nil
    }
    
    // MARK: - Auto-Scroll Logic
    private func determineScrollDirection() {
        // Calculate mouse position relative to the scroll view's global frame
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let mouseLocation = NSEvent.mouseLocation
        let globalMousePoint = CGPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)
        let scrollViewPoint = CGPoint(
            x: globalMousePoint.x - scrollViewGlobalFrame.minX,
            y: globalMousePoint.y - scrollViewGlobalFrame.minY
        )
        var directions: Set<Direction> = []
        
        let visibleX = scrollViewPoint.x
        let visibleY = scrollViewPoint.y
        
        if visibleX < autoScrollMargin {
            directions.insert(.left)
        } else if visibleX > visibleSize.width - autoScrollMargin {
            directions.insert(.right)
        }
        
        if visibleY < autoScrollMargin {
            directions.insert(.up)
        } else if visibleY > visibleSize.height - autoScrollMargin {
            directions.insert(.down)
        }
        
        if directions != self.autoScrollDirection {
            self.autoScrollDirection = directions
        }
    }
    
    private func manageAutoScrollTimer() {
        let shouldBeScrolling = !autoScrollDirection.isEmpty
        
        if shouldBeScrolling && autoScrollTimer == nil {
            autoScrollTimer = Timer.scheduledTimer(withTimeInterval: autoScrollTimerInterval, repeats: true) { _ in
                DispatchQueue.main.async {
                    self.determineScrollDirection()
                    
                    if !self.autoScrollDirection.isEmpty {
                        self.performAutoScroll()
                    } else {
                        self.autoScrollTimer?.invalidate()
                        self.autoScrollTimer = nil
                    }
                }
            }
        } else if !shouldBeScrolling && autoScrollTimer != nil {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
        }
    }
    
    private func performAutoScroll() {
        guard !autoScrollDirection.isEmpty else { return }
        
        let currentOffset = externalContentOffset
        var deltaX: CGFloat = 0
        var deltaY: CGFloat = 0
        
        // Calculate scroll intensity based on distance from the center
        let viewportX = localDragLocation.x - externalContentOffset.x
        let viewportY = localDragLocation.y - externalContentOffset.y
        let centerX = visibleSize.width / 2
        let centerY = visibleSize.height / 2
        let distanceX = abs(viewportX - centerX)
        let distanceY = abs(viewportY - centerY)
        let maxDistanceX = centerX
        let maxDistanceY = centerY
        let intensityX = (distanceX / maxDistanceX).clamped(to: 0...1)
        let intensityY = (distanceY / maxDistanceY).clamped(to: 0...1)
        let speedFactorX = pow(intensityX, 3)
        let speedFactorY = pow(intensityY, 3)
        let baseScrollAmount: CGFloat = 55.0
        let scrollAmountX = baseScrollAmount * speedFactorX
        let scrollAmountY = baseScrollAmount * speedFactorY
        
        if autoScrollDirection.contains(.left) { deltaX -= scrollAmountX }
        if autoScrollDirection.contains(.right) { deltaX += scrollAmountX }
        if autoScrollDirection.contains(.up) { deltaY -= scrollAmountY }
        if autoScrollDirection.contains(.down) { deltaY += scrollAmountY }
        
        let targetX = currentOffset.x + deltaX
        let targetY = currentOffset.y + deltaY
        
        let maxX = max(0, contentSize.width - visibleSize.width)
        let maxY = max(0, contentSize.height - visibleSize.height)
        let clampedX = targetX.clamped(to: 0...maxX)
        let clampedY = targetY.clamped(to: 0...maxY)
        let targetOffset = CGPoint(x: clampedX, y: clampedY)
        
        guard targetOffset != currentOffset else { return }
        
        let denominatorX = max(1e-6, contentSize.width - visibleSize.width)
        let denominatorY = max(1e-6, contentSize.height - visibleSize.height)
        let anchorX = clampedX / denominatorX
        let anchorY = clampedY / denominatorY
        let targetAnchor = UnitPoint(x: anchorX.clamped(to: 0...1), y: anchorY.clamped(to: 0...1))
        
        scrollProxy.scrollTo(scrollableContentID, anchor: targetAnchor)
    }
    
    private func resetDragState() {
        isDragging = false
        dragStartCell = nil
        dragCurrentCell = nil
        
        if autoScrollTimer != nil {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
        }
        
        autoScrollDirection = []
    }
}

// MARK: - Extensions
extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
