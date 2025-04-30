//
//  CustomScrollIndicator.swift
//  Griddy
//
//  Created by Thomas Minzenmay (AI Generated)
//

import SwiftUI

struct CustomScrollIndicator: View {
    // MARK: - Properties
    let axis: Axis
    let scrollProxy: ScrollViewProxy
    let scrollableContentID: String
    
    // Input Bindings/Values
    @Binding var currentOffset: CGFloat // Offset for THIS axis
    let otherAxisOffset: CGFloat        // Offset for the OTHER axis
    let contentSize: CGSize             // Full content size
    let visibleSize: CGSize             // Full visible size
    
    // Configuration
    let cornerRadius: CGFloat = 5.0
    let inactiveColor = Color(white: 0.9) // Thumb color
    
    // Styling & Interaction State/Constants
    @State private var isHovering: Bool = false
    private let defaultThickness: CGFloat = 5.0
    private let hoveredThickness: CGFloat = 11.0 // Also used for spacing/hitbox
    private let defaultOpacity: Double = 0.60
    private let hoveredOpacity: Double = 0.95
    private let minThumbSize: CGFloat = 30.0    // Minimum physical thumb length
    
    // Internal State for Dragging
    @State private var dragStartOffset: CGFloat? = nil
    
    // MARK: - Computed Properties (Axis-Aware)
    private var contentLength: CGFloat { axis == .vertical ? contentSize.height : contentSize.width }
    private var visibleLength: CGFloat { axis == .vertical ? visibleSize.height : visibleSize.width }
    private var maxScrollOffset: CGFloat { max(0, contentLength - visibleLength) }
    private var trackLength: CGFloat { visibleLength }
    
    private var isActive: Bool {
        contentLength > visibleLength
    }
    
    private var interactiveThickness: CGFloat { hoveredThickness }
    
    private var currentVisualThickness: CGFloat { isHovering ? hoveredThickness : defaultThickness }
    private var currentThumbOpacity: Double { isHovering ? hoveredOpacity : defaultOpacity }
    
    private var thumbLength: CGFloat {
        guard isActive, contentLength > 0 else { return 0 }
        let trackRatio = visibleLength / contentLength
        let proportionalLength = trackLength * trackRatio
        return min(trackLength, max(minThumbSize, proportionalLength)) // Ensure min size and max length
    }
    
    private var maxThumbOffset: CGFloat { max(0, trackLength - thumbLength) }
    
    private var thumbOffset: CGFloat {
        calculateThumbOffset(for: currentOffset)
    }
    
    // MARK: - Body
    var body: some View {
        if isActive {
            Color.clear // Track itself is invisible
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(inactiveColor.opacity(currentThumbOpacity))
                        .frame(
                            width: axis == .horizontal ? thumbLength : currentVisualThickness,
                            height: axis == .vertical ? thumbLength : currentVisualThickness
                        )
                        .contentShape(Rectangle())
                        .offset(
                            x: axis == .horizontal ? thumbOffset : 0,
                            y: axis == .vertical ? thumbOffset : 0
                        )
                        .gesture(dragGesture)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.1)) {
                                isHovering = hovering
                            }
                        },
                    alignment: axis == .vertical ? .top : .leading
                )
                .frame(
                    width: axis == .horizontal ? trackLength : interactiveThickness,
                    height: axis == .vertical ? trackLength : interactiveThickness
                )
                .clipped()
        } else {
            EmptyView()
        }
    }
    
    // MARK: - Drag Gesture
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = currentOffset
                }
                
                let initialThumbOffset = calculateThumbOffset(for: dragStartOffset ?? currentOffset)
                let thumbDragDelta = axis == .vertical ? value.translation.height : value.translation.width
                let targetThumbPos = initialThumbOffset + thumbDragDelta
                let clampedThumbPos = targetThumbPos.clamped(to: 0...maxThumbOffset)
                
                guard maxThumbOffset > 0 else { return }
                
                let targetContentOffsetThisAxis = (clampedThumbPos / maxThumbOffset) * maxScrollOffset
                let finalTargetContentOffsetThisAxis = targetContentOffsetThisAxis.clamped(to: 0...maxScrollOffset)
                
                let tolerance: CGFloat = 0.1
                if abs(currentOffset - finalTargetContentOffsetThisAxis) > tolerance {
                    currentOffset = finalTargetContentOffsetThisAxis
                    
                    let targetOffset = CGPoint(
                        x: axis == .horizontal ? finalTargetContentOffsetThisAxis : otherAxisOffset,
                        y: axis == .vertical ? finalTargetContentOffsetThisAxis : otherAxisOffset
                    )
                    
                    let scrollableWidth = contentSize.width - visibleSize.width
                    let scrollableHeight = contentSize.height - visibleSize.height
                    let anchorX = scrollableWidth > 0 ? (targetOffset.x / scrollableWidth).clamped(to: 0...1) : 0
                    let anchorY = scrollableHeight > 0 ? (targetOffset.y / scrollableHeight).clamped(to: 0...1) : 0
                    let anchor = UnitPoint(x: anchorX, y: anchorY)
                    
                    scrollProxy.scrollTo(scrollableContentID, anchor: anchor)
                }
            }
            .onEnded { _ in
                dragStartOffset = nil
                // Reset hover state on drag end for visual consistency
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = false
                }
            }
    }
    
    // MARK: - Helper Functions
    private func calculateThumbOffset(for contentOffset: CGFloat) -> CGFloat {
        guard isActive, maxScrollOffset > 0 else { return 0 }
        let scrollRatio = (contentOffset / maxScrollOffset).clamped(to: 0...1)
        return maxThumbOffset * scrollRatio
    }
}

// MARK: - Extensions
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}
