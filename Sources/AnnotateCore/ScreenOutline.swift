// Visible-text outline of a screen, the "nearby text" hints derived from it, and whether the live
// layout still matches it (the overlay only trusts a live scan when it does).
// No tagging required: every pin carries the labels around it, so an agent can grep for a unique
// string ("Wake up at", "Halo Pendant") to find the SwiftUI view that draws that part of the screen.

#if canImport(CoreGraphics)
// CGRect's initializers and Equatable conformance live in the CoreGraphics overlay on Apple platforms
import CoreGraphics
#endif
import Foundation

public enum ScreenOutline {
    /// Drops empty, off-screen and duplicate entries, orders top-to-bottom then leading-to-trailing,
    /// and caps the list so session.json stays readable.
    public static func normalized(_ elements: [ScreenElement], in bounds: CGRect, limit: Int = 300) -> [ScreenElement] {
        var seen = Set<String>()
        var result: [ScreenElement] = []
        let sorted = elements.sorted { lhs, rhs in
            lhs.frame.y == rhs.frame.y ? lhs.frame.x < rhs.frame.x : lhs.frame.y < rhs.frame.y
        }
        for element in sorted {
            let label = element.label.split(whereSeparator: \.isNewline).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, element.frame.cgRect.clipped(to: bounds).area > 0 else { continue }
            // Same text at (nearly) the same place is one element seen through two layers
            let key = "\(label)|\(Int(element.frame.x / 4))|\(Int(element.frame.y / 4))"
            guard seen.insert(key).inserted else { continue }
            var copy = element
            copy.label = label
            result.append(copy)
            if result.count == limit { break }
        }
        return result
    }

    /// Whether the live layout has moved away from a frozen outline: some labeled element present
    /// in both (same role and text) is now more than `tolerance` points from where it was. Nothing
    /// in common counts as moved, since there's no evidence the layout held still.
    public static func hasMoved(from frozen: [ScreenElement], to live: [ScreenElement], tolerance: Double = 1) -> Bool {
        var frozenFrames: [String: [AnnotationRect]] = [:]
        for element in frozen {
            frozenFrames[element.role + "|" + element.label, default: []].append(element.frame)
        }
        var compared = 0
        for element in live {
            guard let frames = frozenFrames[element.role + "|" + element.label] else { continue }
            compared += 1
            let stayed = frames.contains { frame in
                abs(frame.x - element.frame.x) <= tolerance && abs(frame.y - element.frame.y) <= tolerance
                    && abs(frame.width - element.frame.width) <= tolerance && abs(frame.height - element.frame.height) <= tolerance
            }
            if !stayed { return true }
        }
        return compared == 0
    }

    /// Labels of elements overlapping `frame` (grown by `padding`), nearest first, unique.
    public static func nearbyText(
        for frame: CGRect,
        in elements: [ScreenElement],
        padding: CGFloat = 32,
        limit: Int = 6,
        excluding excluded: String? = nil
    ) -> [String] {
        let area = frame.padded(by: padding)
        let center = CGPoint(x: frame.left + frame.width / 2, y: frame.top + frame.height / 2)
        let hits = elements
            .filter { $0.frame.cgRect.clipped(to: area).area > 0 }
            .map { element -> (String, CGFloat) in
                let rect = element.frame.cgRect
                let elementCenter = CGPoint(x: rect.left + rect.width / 2, y: rect.top + rect.height / 2)
                return (element.label, hypot(elementCenter.x - center.x, elementCenter.y - center.y))
            }
            .sorted { $0.1 < $1.1 }

        var seen = Set<String>()
        if let excluded { seen.insert(excluded) }
        var result: [String] = []
        for (label, _) in hits where seen.insert(label).inserted {
            result.append(label.truncated(to: 60))
            if result.count == limit { break }
        }
        return result
    }
}
