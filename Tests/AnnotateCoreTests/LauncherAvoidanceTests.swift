// LauncherAvoidance: which spot `place` picks for the idle pill (dock, lifted, trailing, leading,
// dock fallback), what counts as bottom chrome, and the hysteresis `update` adds (move off a
// collision at once, settle elsewhere only after agreeing checks).
// Geometry is an iPhone in portrait: 393×852 with the dock 34pt above the bottom edge.

@testable import AnnotateCore
import CoreGraphics
import Foundation
import Testing

@Suite struct LauncherAvoidanceTests {
    private static let layout = LauncherAvoidance.Layout(
        bounds: CGRect(x: 0, y: 0, width: 393, height: 852),
        pillSize: CGSize(width: 120, height: 44),
        dockBottom: 818,
        topLimit: 67,
        sideInset: 34
    )

    /// An iOS 26 floating tab bar's frame: full width, from 83pt above the bottom edge.
    private static let tabBar = CGRect(x: 0, y: 769, width: 393, height: 83)
    /// A mini player sitting on the tab bar.
    private static let miniPlayer = CGRect(x: 8, y: 700, width: 377, height: 56)
    /// A centered column of round buttons that climbs out of the band.
    private static let column = [760, 690, 620, 550].map { CGRect(x: 166, y: $0, width: 60, height: 60) }

    private static func place(_ obstacles: [CGRect], layout: LauncherAvoidance.Layout = layout) -> LauncherSpot {
        LauncherAvoidance.place(layout, obstacles: obstacles)
    }

    // MARK: place

    @Test("an empty bottom keeps the dock")
    func emptyDocks() {
        #expect(Self.place([]) == .dock)
    }

    @Test("buttons above the band are content and don't move the pill")
    func contentAboveBandIgnored() {
        #expect(Self.place([CGRect(x: 100, y: 300, width: 200, height: 60)]) == .dock)
    }

    @Test("chrome in the band that misses the pill keeps the dock")
    func sideButtonKeepsDock() {
        #expect(Self.place([CGRect(x: 16, y: 774, width: 44, height: 44)]) == .dock)
    }

    @Test("a tab bar lifts the pill to clearance above its top")
    func liftsAboveTabBar() {
        #expect(Self.place([Self.tabBar]) == .lifted(bottom: Self.tabBar.minY - LauncherAvoidance.clearance))
    }

    @Test("stacked chrome lifts the pill above the highest piece")
    func liftsAboveStack() {
        let spot = Self.place([Self.tabBar, Self.miniPlayer])
        #expect(spot == .lifted(bottom: Self.miniPlayer.minY - LauncherAvoidance.clearance))
        let frame = LauncherAvoidance.frame(for: spot, in: Self.layout)
        #expect(!frame.intersects(Self.miniPlayer.insetBy(dx: -7, dy: -7)))
    }

    @Test("a lift that would leave the band goes trailing at dock height")
    func trailingWhenLiftLeavesBand() {
        #expect(Self.place(Self.column) == .trailing)
    }

    @Test("trailing blocked goes leading")
    func leadingWhenTrailingBlocked() {
        let trailingButton = CGRect(x: 290, y: 770, width: 80, height: 50)
        #expect(Self.place(Self.column + [trailingButton]) == .leading)
    }

    @Test("nowhere clear falls back to the dock")
    func fallbackDocks() {
        #expect(Self.place(Self.column + [Self.tabBar]) == .dock)
    }

    @Test("an obstacle taller than the band is the screen, not chrome")
    func tallObstacleIgnored() {
        #expect(Self.place([CGRect(x: 0, y: 100, width: 393, height: 752)]) == .dock)
    }

    @Test("the lift stops at the safe-area top on a short screen")
    func liftRespectsTopLimit() {
        // Landscape: 852×393, so the band reaches above the safe area's top
        let landscape = LauncherAvoidance.Layout(
            bounds: CGRect(x: 0, y: 0, width: 852, height: 393),
            pillSize: CGSize(width: 120, height: 44),
            dockBottom: 372,
            topLimit: 220,
            sideInset: 34
        )
        let wideBar = CGRect(x: 0, y: 330, width: 852, height: 63)
        let secondBar = CGRect(x: 0, y: 240, width: 852, height: 60)
        #expect(LauncherAvoidance.place(landscape, obstacles: [wideBar]) == .lifted(bottom: 322))
        #expect(LauncherAvoidance.place(landscape, obstacles: [wideBar, secondBar]) == .dock)
    }

    // MARK: frame

    @Test("frames: centered dock, side insets, and a width capped to the insets")
    func frames() {
        let dock = LauncherAvoidance.frame(for: .dock, in: Self.layout)
        #expect(dock == CGRect(x: 136.5, y: 774, width: 120, height: 44))
        #expect(LauncherAvoidance.frame(for: .leading, in: Self.layout).minX == 34)
        #expect(LauncherAvoidance.frame(for: .trailing, in: Self.layout).maxX == 359)
        var wide = Self.layout
        wide.pillSize.width = 500
        let insetWidth: CGFloat = 393 - 68
        #expect(LauncherAvoidance.frame(for: .dock, in: wide).width == insetWidth)
    }

    // MARK: update

    @Test("covering something moves the pill on the same check")
    func pushedMovesAtOnce() {
        var avoidance = LauncherAvoidance()
        #expect(avoidance.update(Self.layout, obstacles: [Self.tabBar]) == .lifted(bottom: 761))
    }

    @Test("a clear pill settles back on the dock only after agreeing checks")
    func settlesAfterChecks() {
        var avoidance = LauncherAvoidance()
        _ = avoidance.update(Self.layout, obstacles: [Self.tabBar])
        for _ in 1..<LauncherAvoidance.settleChecks {
            #expect(avoidance.update(Self.layout, obstacles: []) == .lifted(bottom: 761))
        }
        #expect(avoidance.update(Self.layout, obstacles: []) == .dock)
    }

    @Test("a check that agrees with the current spot resets the pending move")
    func flickerResets() {
        var avoidance = LauncherAvoidance()
        _ = avoidance.update(Self.layout, obstacles: [Self.tabBar])
        _ = avoidance.update(Self.layout, obstacles: [])
        _ = avoidance.update(Self.layout, obstacles: [Self.tabBar])
        #expect(avoidance.update(Self.layout, obstacles: []) == .lifted(bottom: 761))
    }

    @Test("a spot that no longer fits the layout moves at once")
    func layoutChangeMovesAtOnce() {
        var avoidance = LauncherAvoidance()
        _ = avoidance.update(Self.layout, obstacles: [Self.tabBar])
        var shorter = Self.layout
        shorter.bounds.size.height = 700
        shorter.dockBottom = 666
        #expect(avoidance.update(shorter, obstacles: []) == .dock)
    }

    @Test("growing chrome under a lifted pill lifts it further at once")
    func growingStackMovesAtOnce() {
        var avoidance = LauncherAvoidance()
        _ = avoidance.update(Self.layout, obstacles: [Self.tabBar])
        #expect(avoidance.update(Self.layout, obstacles: [Self.tabBar, Self.miniPlayer]) == .lifted(bottom: 692))
    }

    @Test("reset returns to the dock")
    func resetDocks() {
        var avoidance = LauncherAvoidance()
        _ = avoidance.update(Self.layout, obstacles: [Self.tabBar])
        avoidance.reset()
        #expect(avoidance.spot == .dock)
    }
}
