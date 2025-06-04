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
    
    @Binding var currentOffset: CGFloat
    let otherAxisOffset: CGFloat
    let contentSize: CGSize
    let visibleSize: CGSize
    
    let cornerRadius: CGFloat = 5.0
    let inactiveColor = Color(white: 0.9)
    
    @State private var isHovering: Bool = false
    private let defaultThickness: CGFloat = 5.0
    private let hoveredThickness: CGFloat = 11.0
    private let defaultOpacity: Double = 0.60
    private let hoveredOpacity: Double = 0.95
    private let minThumbSize: CGFloat = 30.0
    
    @State private var dragStartOffset: CGFloat? = nil
    
    // MARK: - Computed Properties (Axis-Aware)
    private var contentLength: CGFloat {
        return axis == .vertical ? contentSize.height : contentSize.width
    }
    private var visibleLength: CGFloat {
        axis == .vertical ? visibleSize.height : visibleSize.width
    }
    private var maxScrollOffset: CGFloat { max(0, contentLength - visibleLength) }
    private var trackLength: CGFloat { visibleLength }
    
    private var isActive: Bool {
        let tolerance: CGFloat = 1.0
        return contentLength > visibleLength + tolerance
    }
    
    private var interactiveThickness: CGFloat { hoveredThickness }
    
    private var currentVisualThickness: CGFloat { isHovering ? hoveredThickness : defaultThickness }
    private var currentThumbOpacity: Double { isHovering ? hoveredOpacity : defaultOpacity }
    
    private var thumbLength: CGFloat {
        guard isActive, contentLength > 0 else { return 0 }
        let trackRatio = visibleLength / contentLength
        let proportionalLength = trackLength * trackRatio
        return min(trackLength, max(minThumbSize, proportionalLength))
    }
    
    private var maxThumbOffset: CGFloat { max(0, trackLength - thumbLength) }
    
    private var thumbOffset: CGFloat {
        calculateThumbOffset(for: currentOffset)
    }
    
    var body: some View {
        if isActive {
            Color.clear
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
                    alignment: axis == .vertical ? .topLeading : .topLeading
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
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = currentOffset
                }
                
                let initialThumbPhysicalOffset = calculateThumbOffset(for: dragStartOffset ?? currentOffset)
                let thumbDragDelta = axis == .vertical ? value.translation.height : value.translation.width
                
                let targetThumbPhysicalPos = initialThumbPhysicalOffset + thumbDragDelta
                let clampedThumbPhysicalPos = targetThumbPhysicalPos.clamped(to: 0...maxThumbOffset)
                
                guard maxThumbOffset > 0 else { return }
                
                let targetContentOffsetThisAxis = (clampedThumbPhysicalPos / maxThumbOffset) * maxScrollOffset
                let finalTargetContentOffsetThisAxis = targetContentOffsetThisAxis.clamped(to: 0...maxScrollOffset)
                
                let tolerance: CGFloat = 0.1
                if abs(currentOffset - finalTargetContentOffsetThisAxis) > tolerance {
                    currentOffset = finalTargetContentOffsetThisAxis
                    
                    // REMOVED targetScrollToPoint as it was unused.
                    
                    let scrollableRangeX = contentSize.width - visibleSize.width // Using contentSize directly for clarity here
                    let scrollableRangeY = contentSize.height - visibleSize.height// Using contentSize directly for clarity here

                    // REMOVED currentAxisScrollableRange as it was unused.

                    let anchorX = (scrollableRangeX > 0) ? ( (axis == .horizontal ? finalTargetContentOffsetThisAxis : otherAxisOffset) / scrollableRangeX ).clamped(to: 0...1) : 0.5 // Adjusted to 0.5 for non-scrollable
                    let anchorY = (scrollableRangeY > 0) ? ( (axis == .vertical ? finalTargetContentOffsetThisAxis : otherAxisOffset) / scrollableRangeY ).clamped(to: 0...1) : 0.5 // Adjusted to 0.5 for non-scrollable
                    
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
    
    private func calculateThumbOffset(for contentOffset: CGFloat) -> CGFloat {
        guard isActive, maxScrollOffset > 0 else { return 0 }
        let clampedContentOffset = contentOffset.clamped(to: 0...maxScrollOffset)
        let scrollRatio = clampedContentOffset / maxScrollOffset
        return (maxThumbOffset * scrollRatio).clamped(to: 0...maxThumbOffset)
    }
}

// MARK: - Extensions
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}
