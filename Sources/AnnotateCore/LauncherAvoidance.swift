// Where the idle launcher pill sits so it stays off the app's own bottom chrome: a tab bar, a
// toolbar, a text field, a view marked `.annotateAvoid()`. `place` is the pure rule: the dock above
// the home indicator when it's clear, else lifted above what covers it in the bottom band, else
// beside it at dock height (trailing first), else the dock anyway. `update` adds hysteresis for the
// timer that re-checks: a pill that covers something moves at once, while one that is clear only
// settles somewhere new after `settleChecks` checks in a row agree, so a bar that shrinks and
// grows while the app scrolls doesn't make the pill bob.
// Foundation only: the overlay collects the obstacle rects.

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public enum LauncherSpot: Equatable, Sendable {
    /// Centered above the home indicator (Figma 9289:1305).
    case dock
    /// Centered, its bottom edge at `bottom`, above whatever covered the dock.
    case lifted(bottom: CGFloat)
    /// At dock height against the leading inset.
    case leading
    /// At dock height against the trailing inset.
    case trailing
}

public struct LauncherAvoidance: Equatable, Sendable {
    public struct Layout: Equatable, Sendable {
        /// The overlay's bounds, in screen points.
        public var bounds: CGRect
        /// The pill's size; its width is capped to `bounds` less `sideInset` on each side.
        public var pillSize: CGSize
        /// The docked pill's bottom edge.
        public var dockBottom: CGFloat
        /// The highest a lifted pill's top may reach (the safe area's top).
        public var topLimit: CGFloat
        /// Distance kept from the side edges, both for the centered pill's width and a side spot.
        public var sideInset: CGFloat

        public init(bounds: CGRect, pillSize: CGSize, dockBottom: CGFloat, topLimit: CGFloat, sideInset: CGFloat) {
            self.bounds = bounds
            self.pillSize = pillSize
            self.dockBottom = dockBottom
            self.topLimit = topLimit
            self.sideInset = sideInset
        }

        /// The bottom strip where chrome counts: obstacles outside it are content, and a lifted pill
        /// stays inside it.
        public var band: CGRect {
            let top = Swift.max(bounds.bottom - LauncherAvoidance.bandHeight, bounds.top)
            return CGRect(x: bounds.left, y: top, width: bounds.right - bounds.left, height: bounds.bottom - top)
        }
    }

    /// Gap kept between the pill and an obstacle. No Figma source: the 8pt the pill keeps above the keyboard.
    public static let clearance: CGFloat = 8
    /// Height of the bottom band, from the screen's bottom edge. No Figma source: room for a tab bar
    /// with a mini player or composer on it, without letting the pill climb into the content.
    public static let bandHeight: CGFloat = 240
    /// Checks in a row that must agree before a pill that covers nothing settles somewhere new.
    /// No Figma source: with the overlay's 1 s re-check, about 2 s of a steady screen.
    public static let settleChecks = 2

    /// Where the pill is now; `update` moves it.
    public private(set) var spot: LauncherSpot = .dock
    private var pendingSpot: LauncherSpot?
    private var pendingCount = 0

    public init() {}

    /// Back to the dock with nothing pending.
    public mutating func reset() {
        spot = .dock
        pendingSpot = nil
        pendingCount = 0
    }

    /// One re-check: moves at once when the current spot covers an obstacle or no longer fits,
    /// otherwise only once `settleChecks` checks in a row picked the same new spot.
    public mutating func update(_ layout: Layout, obstacles: [CGRect]) -> LauncherSpot {
        let target = Self.place(layout, obstacles: obstacles)
        guard target != spot else {
            pendingSpot = nil
            pendingCount = 0
            return spot
        }
        let blockers = Self.relevant(obstacles, in: layout)
        if !Self.fits(spot, in: layout) || !Self.isClear(spot, in: layout, of: blockers) {
            settle(on: target)
            return spot
        }
        if pendingSpot == target {
            pendingCount += 1
        } else {
            pendingSpot = target
            pendingCount = 1
        }
        if pendingCount >= Self.settleChecks { settle(on: target) }
        return spot
    }

    private mutating func settle(on target: LauncherSpot) {
        spot = target
        pendingSpot = nil
        pendingCount = 0
    }

    // MARK: Rule

    /// The dock when it's clear; else lifted above what covers it, while the pill stays inside the
    /// band; else trailing, then leading, at dock height; else the dock (the pill covers something,
    /// as it did before avoidance).
    public static func place(_ layout: Layout, obstacles: [CGRect]) -> LauncherSpot {
        let blockers = relevant(obstacles, in: layout)
        if isClear(.dock, in: layout, of: blockers) { return .dock }
        if let bottom = liftedBottom(layout, blockers: blockers) { return .lifted(bottom: bottom) }
        for side in [LauncherSpot.trailing, .leading] where fits(side, in: layout) && isClear(side, in: layout, of: blockers) {
            return side
        }
        return .dock
    }

    /// The pill's frame at `spot`.
    public static func frame(for spot: LauncherSpot, in layout: Layout) -> CGRect {
        let bounds = layout.bounds
        let width = Swift.min(layout.pillSize.width, Swift.max(bounds.right - bounds.left - layout.sideInset * 2, 0))
        let height = layout.pillSize.height
        let centeredX = (bounds.left + bounds.right) / 2 - width / 2
        let (x, bottom): (CGFloat, CGFloat) = switch spot {
        case .dock: (centeredX, layout.dockBottom)
        case .lifted(let bottom): (centeredX, bottom)
        case .leading: (bounds.left + layout.sideInset, layout.dockBottom)
        case .trailing: (bounds.right - layout.sideInset - width, layout.dockBottom)
        }
        return CGRect(x: x, y: bottom - height, width: width, height: height)
    }

    /// Obstacles that are bottom chrome: in the band, with some area, and no taller than the band.
    /// Anything taller (a full-screen editor, a background control) is the screen, not a bar, and
    /// would only push the pill to the fallback.
    static func relevant(_ obstacles: [CGRect], in layout: Layout) -> [CGRect] {
        let band = layout.band
        return obstacles.filter { obstacle in
            obstacle.area >= 1 && obstacle.bottom - obstacle.top <= LauncherAvoidance.bandHeight
                && obstacle.clipped(to: band).area > 0
        }
    }

    static func isClear(_ spot: LauncherSpot, in layout: Layout, of blockers: [CGRect]) -> Bool {
        let frame = frame(for: spot, in: layout)
        return !blockers.contains { collides($0, frame) }
    }

    /// The spot still makes sense for this layout: inside the bounds, no lower than the dock, and a
    /// lifted pill inside the band and below the safe-area top.
    static func fits(_ spot: LauncherSpot, in layout: Layout) -> Bool {
        let frame = frame(for: spot, in: layout)
        let slack: CGFloat = 0.5
        return frame.left >= layout.bounds.left - slack && frame.right <= layout.bounds.right + slack
            && frame.bottom <= layout.dockBottom + slack && frame.top >= ceiling(layout) - slack
    }

    /// Lifts the pill above everything it hits, pass by pass (a mini player on a tab bar takes two);
    /// nil when that would take its top above the band or the safe area.
    private static func liftedBottom(_ layout: Layout, blockers: [CGRect]) -> CGFloat? {
        var bottom = layout.dockBottom
        for _ in 0...blockers.count {
            let frame = frame(for: .lifted(bottom: bottom), in: layout)
            let hits = blockers.filter { collides($0, frame) }
            guard let highest = hits.map(\.top).min() else { return bottom }
            bottom = (highest - clearance).rounded(.down)
            if bottom - layout.pillSize.height < ceiling(layout) { return nil }
        }
        return nil
    }

    private static func ceiling(_ layout: Layout) -> CGFloat {
        Swift.max(layout.band.top, layout.topLimit)
    }

    private static func collides(_ obstacle: CGRect, _ frame: CGRect) -> Bool {
        obstacle.padded(by: clearance).clipped(to: frame).area > 0
    }
}
