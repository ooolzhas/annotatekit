// Pure state model for the annotate overlay (Figma PVX9n74hzo5BWauvymG141, group 9257:13754).
// `OverlayChrome` decides which bottom chrome shows (the review bar or the comment card) and the copy it
// carries; `PointerIntent` classifies a touch on the frozen screen as a pen stroke, a hold or a tap.
// Views and the controller switch on these instead of re-deriving the conditions, so the rules live
// in one place and stay testable on Linux.

import Foundation

public enum OverlayChrome: Equatable, Sendable {
    /// No pin open: the review bar (×, count title, trash, Send). Figma 9257:13484 shows `count: 4`.
    /// `count: 0` has no frame: it is derived, showing `emptyHint` with trash and Send disabled.
    case review(count: Int)
    /// A pin is open: the comment card docked above the keyboard.
    /// `canSubmit: false` is Figma 9257:13322 (empty comment, ↑ dimmed);
    /// `canSubmit: true` is Figma 9257:13403 (comment typed, ↑ filled blue).
    case composing(canSubmit: Bool)

    public struct Inputs: Equatable, Sendable {
        public var isDraftOpen: Bool
        /// The open pin's comment; ignored when no pin is open.
        public var draftComment: String
        public var pinCount: Int

        public init(isDraftOpen: Bool, draftComment: String, pinCount: Int) {
            self.isDraftOpen = isDraftOpen
            self.draftComment = draftComment
            self.pinCount = pinCount
        }
    }

    public static func resolve(_ inputs: Inputs) -> OverlayChrome {
        if inputs.isDraftOpen {
            // Whitespace alone isn't a comment worth sending to the agent
            let trimmed = inputs.draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
            return .composing(canSubmit: !trimmed.isEmpty)
        }
        return .review(count: max(inputs.pinCount, 0))
    }

    /// Comment field placeholder (Figma 9257:13392).
    public static let placeholder = "Describe the change"
    /// Send capsule title (Figma 9257:13561).
    public static let sendTitle = "Send"
    /// Review title with no pins yet. No Figma frame: derived to name the three gestures that create a pin.
    public static let emptyHint = "Draw, tap or hold"

    /// Review bar title (Figma 9257:13556, sample "4 comments"): "4 comments", "1 comment",
    /// and `emptyHint` when there is nothing to count (0 or a negative input).
    /// Figma shows only the plural; the singular "1 comment" has no frame and is derived.
    public static func countTitle(_ count: Int) -> String {
        guard count > 0 else { return emptyHint }
        return count == 1 ? "1 comment" : "\(count) comments"
    }

    /// Send (and trash) are live only on the review bar with at least one pin; while composing,
    /// the card's ↑ governs and Send isn't shown.
    public var canSend: Bool {
        switch self {
        case .review(let count): count > 0
        case .composing: false
        }
    }
}

public enum PointerIntent: Equatable, Sendable {
    /// Moved past moveThreshold: a pen stroke.
    case draw
    /// Held still for holdDuration: a spot at the touch-down point.
    case hold
    /// Lifted before either: select the element under it.
    case tap

    /// Points of travel before a touch counts as drawing; carried over from 0.1.x's drag threshold
    /// (6pt, strict `>`) so finger jitter on a tap doesn't start a stroke.
    public static let moveThreshold: Double = 6
    /// Seconds held still before a touch becomes a spot. No Figma source: the UIKit long-press default,
    /// so "hold" feels like every other long press on iOS.
    public static let holdDuration: Double = 0.5

    /// nil while a touch that's still down hasn't decided yet.
    /// Movement wins over time: a slow stroke that passes the hold duration is still a stroke.
    public static func classify(distance: Double, duration: Double, isEnded: Bool) -> PointerIntent? {
        if distance > moveThreshold { return .draw }
        if duration >= holdDuration { return .hold }
        if isEnded { return .tap }
        return nil
    }
}
