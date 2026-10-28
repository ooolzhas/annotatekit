// Tap → element selection, independent of UIKit.
// The overlay collects every element whose frame contains the tap (accessibility nodes, UIViews and
// optional `.annotatable()` registrations) as `ElementCandidate`s. `SelectionStack` sorts them
// smallest-first, merges candidates that describe the same box, and walks the stack with ↑ (larger,
// toward the parent) and ↓ (smaller). Below the smallest element sits the tapped point itself: a
// tap on nothing distinct (only big containers under it) starts there, so anything is pinnable.
// `SourceResolver` maps any frame to the nearest `.annotatable()` registration that encloses it.

#if canImport(CoreGraphics)
// CGRect's initializers and Equatable conformance live in the CoreGraphics overlay on Apple platforms
import CoreGraphics
#endif
import Foundation

public struct ElementCandidate: Sendable, Equatable {
    public var frame: CGRect
    public var info: ElementInfo
    /// Set when the candidate is itself an `.annotatable()` registration.
    public var source: SourceLocation?

    public init(frame: CGRect, info: ElementInfo, source: SourceLocation? = nil) {
        self.frame = frame
        self.info = info
        self.source = source
    }

    /// Combines two descriptions of the same on-screen box, keeping the most specific of each field.
    public func merged(with other: ElementCandidate) -> ElementCandidate {
        var result = self
        var info = self.info
        let otherInfo = other.info
        if ElementInfo.isGeneric(role: info.role) && !ElementInfo.isGeneric(role: otherInfo.role) {
            info.role = otherInfo.role
            info.traits = otherInfo.traits
        }
        // A registration's name ("HeroCard") beats a UIKit class name
        if other.source != nil && self.source == nil, let name = otherInfo.typeName {
            info.typeName = name
        } else if info.typeName == nil {
            info.typeName = otherInfo.typeName
        }
        info.label = info.label.nonEmpty ?? otherInfo.label.nonEmpty
        info.value = info.value.nonEmpty ?? otherInfo.value.nonEmpty
        info.identifier = info.identifier.nonEmpty ?? otherInfo.identifier.nonEmpty
        result.info = info
        result.source = source ?? other.source
        return result
    }
}

public struct SelectionStack: Sendable, Equatable {
    /// Smallest first; every frame contains the tapped point.
    public private(set) var candidates: [ElementCandidate]
    public private(set) var index: Int
    /// The pin marks the tapped spot rather than an element.
    public private(set) var isAtPoint: Bool
    public let point: CGPoint

    /// - Parameters:
    ///   - screenArea: when given, a tap whose smallest candidate covers more than
    ///     `containerFraction` of the screen starts at the point instead of that container.
    public init(
        candidates: [ElementCandidate],
        at point: CGPoint,
        screenArea: CGFloat? = nil,
        containerFraction: CGFloat = 0.4,
        tolerance: CGFloat = 1
    ) {
        let hits = candidates.enumerated()
            .filter { $0.element.frame.area > 0 && $0.element.frame.containsPoint(point) }
            // Stable smallest-first: ties keep discovery order (deeper views are discovered later,
            // so for equal boxes the later, more specific one is merged into the earlier)
            .sorted { lhs, rhs in
                lhs.element.frame.area == rhs.element.frame.area ? lhs.offset < rhs.offset : lhs.element.frame.area < rhs.element.frame.area
            }
            .map(\.element)

        var merged: [ElementCandidate] = []
        for hit in hits {
            if let existing = merged.firstIndex(where: { $0.frame.isNearlyEqual(to: hit.frame, tolerance: tolerance) }) {
                merged[existing] = Self.preferSpecific(merged[existing], hit)
            } else {
                merged.append(hit)
            }
        }
        self.candidates = merged
        self.index = 0
        self.point = point
        if let first = merged.first, let screenArea, screenArea > 0 {
            self.isAtPoint = first.frame.area > screenArea * containerFraction
        } else {
            self.isAtPoint = merged.isEmpty
        }
    }

    public var isEmpty: Bool { candidates.isEmpty }

    /// The selected element; nil while the selection is the tapped point.
    public var current: ElementCandidate? {
        guard !isAtPoint, candidates.indices.contains(index) else { return nil }
        return candidates[index]
    }

    /// ↑ — select the next larger enclosing element (from the point: the smallest element).
    /// Returns false at the top.
    @discardableResult
    public mutating func expand() -> Bool {
        if isAtPoint {
            guard !candidates.isEmpty else { return false }
            isAtPoint = false
            index = 0
            return true
        }
        guard index + 1 < candidates.count else { return false }
        index += 1
        return true
    }

    /// ↓ — select the next smaller element under the tap, then the point itself.
    /// Returns false once at the point.
    @discardableResult
    public mutating func narrow() -> Bool {
        guard !isAtPoint else { return false }
        if index > 0 {
            index -= 1
        } else {
            isAtPoint = true
        }
        return true
    }

    /// Candidates larger than the selection, nearest first.
    private var enclosing: ArraySlice<ElementCandidate> {
        let start = isAtPoint ? 0 : index + 1
        return start < candidates.count ? candidates[start...] : []
    }

    /// Titles of the enclosing candidates, nearest first.
    public func breadcrumb(limit: Int = 4) -> [String] {
        enclosing.prefix(limit).map(\.info.title)
    }

    /// The current candidate's own registration, else the nearest enclosing one.
    public var resolvedSource: SourceLocation? {
        if let source = current?.source { return source }
        let target = current?.frame ?? CGRect(x: point.x, y: point.y, width: 0, height: 0)
        for candidate in enclosing {
            if var source = candidate.source, candidate.frame.encloses(target) {
                source.match = .enclosing
                return source
            }
        }
        return nil
    }

    /// `current` with breadcrumb filled in, ready to store on an annotation.
    public var currentInfo: ElementInfo? {
        guard var info = current?.info else { return nil }
        info.breadcrumb = breadcrumb()
        return info
    }

    private static func preferSpecific(_ a: ElementCandidate, _ b: ElementCandidate) -> ElementCandidate {
        func score(_ c: ElementCandidate) -> Int {
            (ElementInfo.isGeneric(role: c.info.role) ? 0 : 2) + (c.info.label.nonEmpty == nil ? 0 : 1)
        }
        return score(b) > score(a) ? b.merged(with: a) : a.merged(with: b)
    }
}

/// One live `.annotatable()` registration, in screen points.
public struct RegisteredView: Sendable, Equatable {
    public var name: String?
    public var frame: CGRect
    public var file: String
    public var line: Int

    public init(name: String?, frame: CGRect, file: String, line: Int) {
        self.name = name
        self.frame = frame
        self.file = file
        self.line = line
    }

    public var source: SourceLocation {
        SourceLocation(name: name, file: file, line: line, match: .exact)
    }

    public var candidate: ElementCandidate {
        ElementCandidate(
            frame: frame,
            info: ElementInfo(role: "view", typeName: name ?? SourceLocation.fileStem(file)),
            source: source
        )
    }
}

public enum SourceResolver {
    /// The smallest registration enclosing `frame`: `.exact` when it is the same box, else `.enclosing`.
    public static func resolve(frame: CGRect, in views: [RegisteredView], tolerance: CGFloat = 1) -> SourceLocation? {
        let best = views
            .filter { $0.frame.area > 0 && $0.frame.encloses(frame, tolerance: tolerance) }
            .min { $0.frame.area < $1.frame.area }
        guard let best else { return nil }
        var source = best.source
        source.match = best.frame.isNearlyEqual(to: frame, tolerance: tolerance) ? .exact : .enclosing
        return source
    }
}

extension ElementInfo {
    static func isGeneric(role: String) -> Bool {
        role == "view" || role == "element"
    }

    /// Short kind label for chips and breadcrumbs: "Button", "Text", or a registration name.
    public var title: String {
        if ElementInfo.isGeneric(role: role), let typeName, !typeName.isEmpty {
            return typeName
        }
        return role.prefix(1).uppercased() + role.dropFirst()
    }

    /// `Button "Get started"`, `Text "Light that follows…"`, `HeroCard`.
    public func displayName(maxLabelLength: Int = 40) -> String {
        guard let label = (label.nonEmpty ?? value.nonEmpty) else { return title }
        return "\(title) \"\(label.truncated(to: maxLabelLength))\""
    }
}

extension SourceLocation {
    /// "HomeView" from ".../HomeView.swift".
    public static func fileStem(_ path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        if let dot = last.lastIndex(of: ".") { return String(last[..<dot]) }
        return last
    }

    /// "HomeView.swift:42".
    public var shortDescription: String {
        let last = file.split(separator: "/").last.map(String.init) ?? file
        return "\(last):\(line)"
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension String {
    func truncated(to length: Int) -> String {
        let collapsed = split(whereSeparator: \.isNewline).joined(separator: " ")
        guard collapsed.count > length else { return collapsed }
        let head = collapsed.prefix(Swift.max(1, length - 1))
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }
}
