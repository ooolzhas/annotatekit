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

    /// How far along a sketch's first stroke, as a fraction of its length from the first point drawn,
    /// its pin sits: 15% short of where that stroke ends, centered on the line (owner request
    /// 2026-11-01; Figma 9378:5659).
    public static let sketchPinFraction: Double = 0.85

    /// Where a sketch's pin sits: on its first stroke, `sketchPinFraction` along it. Only the first
    /// stroke counts, so drawing more shapes into the same pin never moves it (owner request
    /// 2026-11-01). Nil with no points.
    public static func sketchPin(for strokes: [Stroke]) -> CGPoint? {
        guard let first = strokes.first(where: { !$0.points.isEmpty }) else { return nil }
        return point(along: [first], fraction: sketchPinFraction)
    }

    /// The point `fraction` of the way along `strokes`' total length, walked along the line as it is
    /// drawn (`drawnPoints(of:)`), not the raw touch samples: the drawn curve cuts inside every
    /// sample, so a point on the samples sat off the line, under the pin's edge. The gap between one
    /// stroke's end and the next stroke's start does not count. `fraction` is clamped to 0...1. Nil
    /// when there are no points at all; strokes with zero total length return the first point.
    public static func point(along strokes: [Stroke], fraction: Double) -> CGPoint? {
        let lines = strokes.map(drawnPoints(of:)).filter { !$0.isEmpty }
        guard let first = lines.first?.first, let last = lines.last?.last else { return nil }
        let length = { (a: CGPoint, b: CGPoint) in hypot(Double(b.x - a.x), Double(b.y - a.y)) }
        let total = lines.reduce(0.0) { sum, line in
            zip(line, line.dropFirst()).reduce(sum) { $0 + length($1.0, $1.1) }
        }
        let target = total * Swift.min(Swift.max(fraction, 0), 1)
        guard target > 0 else { return first }
        var walked = 0.0
        for line in lines {
            for (a, b) in zip(line, line.dropFirst()) {
                let segment = length(a, b)
                if segment > 0, walked + segment >= target {
                    let t = CGFloat((target - walked) / segment)
                    return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
                walked += segment
            }
        }
        // Floating-point shortfall at fraction 1 lands here.
        return last
    }

    /// How many straight pieces each curved piece of a drawn pen line is measured in. The curves
    /// span two touch samples at most, so 8 keeps the measured line within a fraction of a point.
    static let curveSteps = 8

    /// A stroke as it is drawn, flattened into short straight pieces. A pen stroke follows the
    /// renderer's smoothing (AnnotateKit's `SketchPath`; keep the two in step): straight from the
    /// first sample to the midpoint of the first two, a quadratic curve from each midpoint to the
    /// next with the sample between as its control, then straight to the last sample. Shapes and
    /// arrows keep their points as they are.
    public static func drawnPoints(of stroke: Stroke) -> [CGPoint] {
        let samples = stroke.points.map(\.cgPoint)
        guard stroke.tool == .pen, samples.count > 2 else { return samples }
        let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var line = [samples[0], mid(samples[0], samples[1])]
        for index in 1..<(samples.count - 1) {
            let start = mid(samples[index - 1], samples[index])
            let control = samples[index]
            let end = mid(samples[index], samples[index + 1])
            for step in 1...curveSteps {
                let t = CGFloat(step) / CGFloat(curveSteps), u = 1 - t
                line.append(CGPoint(
                    x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                    y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
                ))
            }
        }
        line.append(samples[samples.count - 1])
        return line
    }
}
