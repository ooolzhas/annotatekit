// Which earlier freeze-frame, if any, the app is showing again. Annotate mode takes a new
// freeze-frame each time it starts, and pins belong to the frame they were drawn on, so without
// this, leaving annotate mode and coming back hid every pin while the count still included them.
// Comparing tiny grayscale samples recognizes the same screen: the overlay then shows that frame
// again, pins and all. Foundation only: the samples are plain gray bytes, captured by the overlay.

import Foundation

public enum ScreenMatch {
    /// Mean gray difference (0–255) up to which two samples are the same screen. Above
    /// `LaunchSettle`'s caret tolerance: a screen left and revisited can also have a ticking clock
    /// or a changed badge, while a different screen differs by tens.
    public static let tolerance: Double = 4

    /// The candidate closest to `sample` within `tolerance`, or nil when none is the same screen.
    public static func match(_ sample: [UInt8], among candidates: [(index: Int, pixels: [UInt8])]) -> Int? {
        candidates
            .map { (index: $0.index, difference: LaunchSettle.meanDifference(sample, $0.pixels)) }
            .filter { $0.difference <= tolerance }
            .min { $0.difference < $1.difference }?
            .index
    }
}
