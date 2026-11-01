// When a launch-time start (`ANNOTATE=1`) should freeze the screen. Starting on scene activation
// froze the launch screen or the app's own splash, so the overlay samples tiny grayscale captures
// and waits for the first screen the app settles on. Splashes often hold still for a moment before
// animating away, so "settled" needs a minimum age and a quiet run long enough to outlast that
// pause; a screen that never stops moving (spinner, shimmer) gives up at `timeout`. Ages count
// only time the app is active: a permission alert at first launch makes it inactive, and apps often
// hold their splash until they're active again, which looks settled but isn't (`interrupt`).
// The idle launcher pill's first reveal waits for the same thing on every DEBUG launch, where each
// sample (a draw of every app window) is pure overhead, so it samples less often and gives up
// sooner (`reveal`).
// Foundation only: the samples are plain gray bytes, captured by the overlay.

import Foundation

public struct LaunchSettle: Sendable, Equatable {
    /// Seconds between samples.
    public static let interval: Double = 0.2

    /// Seconds between samples for `reveal`.
    public static let revealInterval: Double = 0.5

    /// When the launcher pill first fades in: the same splash rules, at most 3 s of sampling at
    /// `revealInterval` (7 samples instead of up to 41). Not in Figma: a pill that shows a little
    /// early only lands on the dock before the placement checks move it.
    public static let reveal = LaunchSettle(timeout: 3)

    /// Never start earlier than this many seconds after the overlay attached.
    public var minimumAge: Double
    /// How long the screen must stay unchanged.
    public var quietFor: Double
    /// Start anyway after this many seconds.
    public var timeout: Double
    /// Mean absolute difference (0–255 gray) up to which two samples count as the same screen;
    /// absorbs a blinking caret or a small spinner on an otherwise still screen.
    public var tolerance: Double

    private var previous: [UInt8]?
    private var quietSince: Double?

    public init(minimumAge: Double = 1.5, quietFor: Double = 1.0, timeout: Double = 8, tolerance: Double = 2) {
        self.minimumAge = minimumAge
        self.quietFor = quietFor
        self.timeout = timeout
        self.tolerance = tolerance
    }

    /// The app went inactive (a system alert is up): whatever it shows now doesn't count as settled.
    public mutating func interrupt() {
        previous = nil
        quietSince = nil
    }

    /// Feeds one sample taken after `age` seconds of the app being active since the overlay
    /// attached (nil when the capture failed). Returns true once it's time to start.
    public mutating func observe(_ pixels: [UInt8]?, at age: Double) -> Bool {
        defer { previous = pixels }
        guard age < timeout else { return true }
        guard let pixels else {
            quietSince = nil
            return false
        }
        let unchanged = previous.map { Self.meanDifference($0, pixels) <= tolerance } ?? false
        if !unchanged { quietSince = age }
        guard let quietSince else { return false }
        // Ages are sums of sample intervals; don't let float rounding decide a boundary
        let slack = 1e-6
        return age >= minimumAge - slack && age - quietSince >= quietFor - slack
    }

    /// Mean absolute per-pixel difference, 0–255; infinite when the samples differ in size.
    public static func meanDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
        var total = 0
        for index in lhs.indices {
            total += abs(Int(lhs[index]) - Int(rhs[index]))
        }
        return Double(total) / Double(lhs.count)
    }
}
