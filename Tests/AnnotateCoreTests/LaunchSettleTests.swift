// LaunchSettle: when a launch-time start freezes the screen — past a still splash, on the first
// settled screen, never before the minimum age, always by the timeout.

import Foundation
import Testing
@testable import AnnotateCore

@Suite struct LaunchSettleTests {
    let splash = [UInt8](repeating: 255, count: 64)
    let home = [UInt8](repeating: 40, count: 64)

    /// Feeds `frames` every `interval` seconds and returns the age it first said start.
    private func startAge(
        _ settle: LaunchSettle,
        every interval: Double = LaunchSettle.interval,
        frames: (Double) -> [UInt8]?
    ) -> Double? {
        var settle = settle
        var age = 0.0
        while age < 20 {
            if settle.observe(frames(age), at: age) { return age }
            age += interval
        }
        return nil
    }

    @Test func waitsOutASplashThatHoldsStillThenStartsOnTheSettledScreen() throws {
        // Still splash for 1.2 s, animates away by 1.6 s, then Home
        let frames: (Double) -> [UInt8]? = { age in
            if age < 1.2 { return splash }
            if age < 1.6 { return [UInt8](repeating: UInt8(40 + Int(age * 100) % 100), count: 64) }
            return home
        }
        let age = try #require(startAge(LaunchSettle(), frames: frames))
        #expect(age >= 2.6 - 1e-9)
        #expect(age < 3.0)
    }

    @Test func neverStartsBeforeTheMinimumAge() throws {
        let age = try #require(startAge(LaunchSettle()) { _ in home })
        #expect(age >= 1.5 - 1e-9)
        #expect(age < 1.5 + LaunchSettle.interval)
    }

    @Test func aScreenThatNeverSettlesStartsAtTheTimeout() throws {
        let frames: (Double) -> [UInt8]? = { age in
            [UInt8](repeating: Int(age / LaunchSettle.interval) % 2 == 0 ? 0 : 255, count: 64)
        }
        let age = try #require(startAge(LaunchSettle(timeout: 4), frames: frames))
        #expect(age >= 4 - 1e-9)
        #expect(age < 4 + LaunchSettle.interval)
    }

    @Test func smallChangesWithinToleranceStillCountAsSettled() throws {
        // One blinking pixel: a mean difference of about 1.6
        let frames: (Double) -> [UInt8]? = { age in
            var frame = home
            frame[0] = Int(age / LaunchSettle.interval) % 2 == 0 ? 40 : 140
            return frame
        }
        let age = try #require(startAge(LaunchSettle(), frames: frames))
        #expect(age < 1.5 + LaunchSettle.interval)
    }

    @Test func failedCapturesRestartTheQuietRun() throws {
        let age = try #require(startAge(LaunchSettle()) { age in (1.4...1.8).contains(age) ? nil : home })
        // The quiet run restarts at the first good sample after the gap (2.0) and needs 1 s more
        #expect(age >= 3.0 - 1e-9)
    }

    @Test func anInterruptionRestartsTheQuietRun() {
        var settle = LaunchSettle()
        var age = 0.0
        var startedEarly = false
        while age < 1.4 {
            startedEarly = startedEarly || settle.observe(splash, at: age)
            age += LaunchSettle.interval
        }
        settle.interrupt() // a permission alert held the splash still
        let onSplash = settle.observe(splash, at: age)
        let onHome = settle.observe(home, at: age + 0.2)
        let homeNotYetQuiet = settle.observe(home, at: age + 1.0)
        let homeQuiet = settle.observe(home, at: age + 1.2)
        #expect(!startedEarly && !onSplash && !onHome && !homeNotYetQuiet)
        #expect(homeQuiet)
    }

    @Test func meanDifferenceIsPerPixelAndInfiniteForMismatchedSizes() {
        #expect(LaunchSettle.meanDifference([0, 10], [10, 0]) == 10)
        #expect(LaunchSettle.meanDifference([0], [0, 0]) == .infinity)
        #expect(LaunchSettle.meanDifference([], []) == .infinity)
    }

    // MARK: Launcher reveal

    @Test func revealOnAStillScreenWaitsOnlyTheMinimumAge() throws {
        let age = try #require(startAge(.reveal, every: LaunchSettle.revealInterval) { _ in home })
        #expect(age >= 1.5 - 1e-9)
        #expect(age < 1.5 + LaunchSettle.revealInterval)
    }

    @Test func revealGivesUpOnAMovingScreenByThreeSeconds() throws {
        // Every sample differs: a spinner or shimmer the size of the screen
        let frames: (Double) -> [UInt8]? = { age in
            [UInt8](repeating: Int(age / LaunchSettle.revealInterval) % 2 == 0 ? 0 : 255, count: 64)
        }
        let age = try #require(startAge(.reveal, every: LaunchSettle.revealInterval, frames: frames))
        #expect(age >= 3 - 1e-9)
        #expect(age < 3 + LaunchSettle.revealInterval)
        // 7 samples (0 … 3 s), where a launch-time start's pace would take 16 by then and 41 by its timeout
        #expect(Int((age / LaunchSettle.revealInterval).rounded()) + 1 == 7)
    }

    @Test func revealStillWaitsOutASplashThatHoldsStill() throws {
        // The launch-time case above, sampled at the reveal's pace: not revealed over the splash
        let frames: (Double) -> [UInt8]? = { age in
            if age < 1.2 { return splash }
            if age < 1.6 { return [UInt8](repeating: UInt8(40 + Int(age * 100) % 100), count: 64) }
            return home
        }
        let age = try #require(startAge(.reveal, every: LaunchSettle.revealInterval, frames: frames))
        #expect(age >= 2.0 - 1e-9)
        #expect(age <= 3 + 1e-9)
    }
}
