// Small CGRect helpers written against origin/size only, so they behave identically on Darwin and
// swift-corelibs-foundation (Linux), which lacks most of CoreGraphics' CGRect extensions.
// Also placement math for the overlay: pin badges and the comment card.

#if canImport(CoreGraphics)
// CGRect's initializers and Equatable conformance live in the CoreGraphics overlay on Apple platforms
import CoreGraphics
#endif
import Foundation

extension CGRect {
    var left: CGFloat { Swift.min(origin.x, origin.x + size.width) }
    var right: CGFloat { Swift.max(origin.x, origin.x + size.width) }
    var top: CGFloat { Swift.min(origin.y, origin.y + size.height) }
    var bottom: CGFloat { Swift.max(origin.y, origin.y + size.height) }

    /// Width × height, 0 for empty or inverted rects.
    public var area: CGFloat { Swift.max(0, size.width) * Swift.max(0, size.height) }

    public func containsPoint(_ point: CGPoint) -> Bool {
        point.x >= left && point.x <= right && point.y >= top && point.y <= bottom
    }

    /// `other` lies inside this rect, allowing `tolerance` points of overhang on each edge.
    public func encloses(_ other: CGRect, tolerance: CGFloat = 1) -> Bool {
        other.left >= left - tolerance && other.right <= right + tolerance
            && other.top >= top - tolerance && other.bottom <= bottom + tolerance
    }

    /// Every edge within `tolerance` points.
    public func isNearlyEqual(to other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(left - other.left) <= tolerance && abs(right - other.right) <= tolerance
            && abs(top - other.top) <= tolerance && abs(bottom - other.bottom) <= tolerance
    }

    /// The rect spanned by two drag points, in either direction.
    public static func spanning(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: Swift.min(a.x, b.x), y: Swift.min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Intersection that returns `.zero` instead of `.null` when disjoint.
    public func clipped(to bounds: CGRect) -> CGRect {
        let l = Swift.max(left, bounds.left), r = Swift.min(right, bounds.right)
        let t = Swift.max(top, bounds.top), b = Swift.min(bottom, bounds.bottom)
        guard r > l, b > t else { return .zero }
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }

    public func padded(by inset: CGFloat) -> CGRect {
        CGRect(x: left - inset, y: top - inset, width: (right - left) + inset * 2, height: (bottom - top) + inset * 2)
    }
}

public enum OverlayPlacement {
    /// Center for a numbered pin: the element's top-trailing corner, pulled inside `bounds`.
    public static func pinCenter(for frame: CGRect, radius: CGFloat, in bounds: CGRect) -> CGPoint {
        let x = Swift.min(Swift.max(frame.right, bounds.left + radius), bounds.right - radius)
        let y = Swift.min(Swift.max(frame.top, bounds.top + radius), bounds.bottom - radius)
        return CGPoint(x: x, y: y)
    }

    /// Frame for a card of `size` next to `anchor`: below if it fits, else above, else pinned to
    /// the bottom of `bounds`. Leading edge follows the anchor, clamped horizontally.
    public static func cardFrame(size: CGSize, anchoredTo anchor: CGRect, in bounds: CGRect, spacing: CGFloat = 10) -> CGRect {
        let width = Swift.min(size.width, bounds.size.width)
        let x = Swift.min(Swift.max(anchor.left, bounds.left), bounds.right - width)
        let below = anchor.bottom + spacing
        let above = anchor.top - spacing - size.height
        let y: CGFloat
        if below + size.height <= bounds.bottom {
            y = below
        } else if above >= bounds.top {
            y = above
        } else {
            y = bounds.bottom - size.height
        }
        return CGRect(x: x, y: y, width: width, height: size.height)
    }

    /// The two barb endpoints of an arrow head at `end`.
    public static func arrowHead(from start: CGPoint, to end: CGPoint, length: CGFloat = 14, spread: CGFloat = .pi / 7) -> (CGPoint, CGPoint) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let a = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let b = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        return (a, b)
    }
}
