// Visible-text outline of a screen and the "nearby text" hints derived from it.
// No tagging required: every pin carries the labels around it, so an agent can grep for a unique
// string ("Wake up at", "Halo Pendant") to find the SwiftUI view that draws that part of the screen.

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
