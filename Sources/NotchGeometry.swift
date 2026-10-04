import AppKit
import SwiftUI

enum NotchMode: Int, Comparable {
    case hidden, compact, expanded
    static func < (a: NotchMode, b: NotchMode) -> Bool { a.rawValue < b.rawValue }
}

struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    /// Horizontal center of the notch, in global screen coordinates.
    var centerX: CGFloat

    static let wing: CGFloat = 40                 // compact extension on each side
    static let expandedWidth: CGFloat = 400
    static let expandedContentHeight: CGFloat = 138
    static let shadowMargin: CGFloat = 24         // window room for the drop shadow

    /// Concave "ear" radius at the top corners (blends into the menu bar)
    /// and the convex radius at the bottom corners.
    func radii(for mode: NotchMode) -> (top: CGFloat, bottom: CGFloat) {
        switch mode {
        case .hidden: (4, 8)
        case .compact: (6, 10)
        case .expanded: (12, 24)
        }
    }

    func size(for mode: NotchMode) -> CGSize {
        let ears = 2 * radii(for: mode).top
        switch mode {
        case .hidden:
            // Tucked fully behind the physical notch.
            return CGSize(width: notchWidth - 24, height: notchHeight - 8)
        case .compact:
            return CGSize(width: notchWidth + 2 * Self.wing + ears, height: notchHeight)
        case .expanded:
            return CGSize(width: Self.expandedWidth + ears,
                          height: notchHeight + Self.expandedContentHeight)
        }
    }

    func windowFrame(for mode: NotchMode) -> NSRect {
        var size = size(for: mode)
        if mode == .expanded {
            size.width += 2 * Self.shadowMargin
            size.height += Self.shadowMargin
        }
        // Not rounded: every mode's window must share the exact same center,
        // or the notch would shift by half a point when the window resizes.
        return NSRect(x: centerX - size.width / 2, y: screenFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    static func detect() -> NotchGeometry {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(screenFrame: screen.frame, notchWidth: width,
                                 notchHeight: screen.safeAreaInsets.top,
                                 centerX: screen.frame.minX + left.width + width / 2)
        }
        // No notch (e.g. lid closed on an external display): float a
        // notch-sized island at the top center instead.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchGeometry(screenFrame: screen.frame, notchWidth: 180, notchHeight: menuBar,
                             centerX: screen.frame.midX)
    }
}

/// The notch silhouette: flat top with concave ears, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4, rect.height / 2)
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, rect.height - t)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.minX + t, y: rect.minY),
                 tangent2End: CGPoint(x: rect.minX + t, y: rect.maxY), radius: t)
        p.addArc(tangent1End: CGPoint(x: rect.minX + t, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: b)
        p.addArc(tangent1End: CGPoint(x: rect.maxX - t, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - t, y: rect.minY), radius: b)
        p.addArc(tangent1End: CGPoint(x: rect.maxX - t, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: t)
        p.closeSubpath()
        return p
    }
}
