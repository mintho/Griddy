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
    @Binding var currentOffset: CGFloat // Offset for THIS axis (this is fileState.scrollOffset.x or .y)
    let otherAxisOffset: CGFloat        // Offset for the OTHER axis
    let contentSize: CGSize             // Full content size (of the ZStack in FileView: image + 2*margin)
    let visibleSize: CGSize             // Full visible size (ScrollView viewport size)
    
    // Configuration
    let cornerRadius: CGFloat = 5.0
    let inactiveColor = Color(white: 0.9)
    
    // Styling & Interaction State/Constants
    @State private var isHovering: Bool = false
    private let defaultThickness: CGFloat = 5.0
    private let hoveredThickness: CGFloat = 11.0
    private let defaultOpacity: Double = 0.60
    private let hoveredOpacity: Double = 0.95
    private let minThumbSize: CGFloat = 30.0
    
    @State private var dragStartOffset: CGFloat? = nil
    
    // MARK: - Computed Properties (Axis-Aware)
    private var contentLength: CGFloat {
        // contentSize already includes the margins from FileView's ZStack.
        // So, the contentLength for the scrollbar is simply the dimension of contentSize.
        return axis == .vertical ? contentSize.height : contentSize.width
    }
    private var visibleLength: CGFloat {
        axis == .vertical ? visibleSize.height : visibleSize.width
    }
    private var maxScrollOffset: CGFloat { max(0, contentLength - visibleLength) }
    private var trackLength: CGFloat { visibleLength }
    
    private var isActive: Bool {
        // Ensure there's actually something to scroll (content is larger than viewport)
        // Add a small tolerance to avoid scrollbars for minuscule overflows.
        let tolerance: CGFloat = 1.0
        return contentLength > visibleLength + tolerance
    }
    
    private var interactiveThickness: CGFloat { hoveredThickness }
    
    private var currentVisualThickness: CGFloat { isHovering ? hoveredThickness : defaultThickness }
    private var currentThumbOpacity: Double { isHovering ? hoveredOpacity : defaultOpacity }
    
    private var thumbLength: CGFloat {
        guard isActive, contentLength > 0 else { return 0 }
        let trackRatio = visibleLength / contentLength // Ratio of visible area to total content
        let proportionalLength = trackLength * trackRatio
        return min(trackLength, max(minThumbSize, proportionalLength))
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
                        .contentShape(Rectangle()) // Make sure the thumb itself is tappable
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
                    alignment: axis == .vertical ? .topLeading : .topLeading // Ensure consistent alignment
                )
                .frame( // This frame is for the invisible track / hit area
                    width: axis == .horizontal ? trackLength : interactiveThickness,
                    height: axis == .vertical ? trackLength : interactiveThickness
                )
                .clipped() // Important if thumb could go outside for some reason
        } else {
            EmptyView()
        }
    }
    
    // MARK: - Drag Gesture
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartOffset == nil {
                    // Record the content's scroll offset when the drag begins
                    dragStartOffset = currentOffset
                }
                
                // Calculate initial thumb position based on where content was when drag started
                let initialThumbPhysicalOffset = calculateThumbOffset(for: dragStartOffset ?? currentOffset)
                let thumbDragDelta = axis == .vertical ? value.translation.height : value.translation.width
                
                // New desired physical position of the thumb on the track
                let targetThumbPhysicalPos = initialThumbPhysicalOffset + thumbDragDelta
                let clampedThumbPhysicalPos = targetThumbPhysicalPos.clamped(to: 0...maxThumbOffset)
                
                guard maxThumbOffset > 0 else { return } // Avoid division by zero if no scroll range for thumb
                
                // Convert the new thumb physical position back to a content offset
                let targetContentOffsetThisAxis = (clampedThumbPhysicalPos / maxThumbOffset) * maxScrollOffset
                // Ensure the calculated content offset is within the valid scroll range
                let finalTargetContentOffsetThisAxis = targetContentOffsetThisAxis.clamped(to: 0...maxScrollOffset)
                
                let tolerance: CGFloat = 0.1 // To prevent jitter or excessive updates
                if abs(currentOffset - finalTargetContentOffsetThisAxis) > tolerance {
                    currentOffset = finalTargetContentOffsetThisAxis // Update the bound fileState.scrollOffset
                    
                    // Prepare the CGPoint for ScrollViewProxy.scrollTo
                    // This point represents the desired top-left corner of the visible content.
                    let targetScrollToPoint = CGPoint(
                        x: axis == .horizontal ? finalTargetContentOffsetThisAxis : otherAxisOffset,
                        y: axis == .vertical ? finalTargetContentOffsetThisAxis : otherAxisOffset
                    )
                    
                    // Calculate anchor for scrollTo. The anchor is a UnitPoint representing
                    // the fractional position within the scrollable range.
                    let scrollableRangeX = contentLength - visibleLength // This is maxScrollOffset for X
                    let scrollableRangeY = contentLength - visibleLength // This is maxScrollOffset for Y (if vertical)

                    // Use the correct scrollable range for the current axis
                    let currentAxisScrollableRange = axis == .vertical ? scrollableRangeY : scrollableRangeX

                    // If we are scrolling horizontally, anchor.x uses finalTargetContentOffsetThisAxis
                    // and anchor.y uses otherAxisOffset / scrollableRangeY.
                    // And vice-versa for vertical scrolling.
                    
                    let anchorX = (scrollableRangeX > 0) ? ( (axis == .horizontal ? finalTargetContentOffsetThisAxis : otherAxisOffset) / scrollableRangeX ).clamped(to: 0...1) : 0
                    let anchorY = (scrollableRangeY > 0) ? ( (axis == .vertical ? finalTargetContentOffsetThisAxis : otherAxisOffset) / scrollableRangeY ).clamped(to: 0...1) : 0

                    let anchor = UnitPoint(x: anchorX, y: anchorY)
                    
                    scrollProxy.scrollTo(scrollableContentID, anchor: anchor)
                }
            }
            .onEnded { _ in
                dragStartOffset = nil
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = false
                }
            }
    }
    
    // MARK: - Helper Functions
    private func calculateThumbOffset(for contentOffset: CGFloat) -> CGFloat {
        guard isActive, maxScrollOffset > 0 else { return 0 }
        // Ensure contentOffset doesn't exceed maxScrollOffset for calculation
        let clampedContentOffset = contentOffset.clamped(to: 0...maxScrollOffset)
        let scrollRatio = clampedContentOffset / maxScrollOffset
        return (maxThumbOffset * scrollRatio).clamped(to: 0...maxThumbOffset)
    }
}

// MARK: - Extensions 2
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}
