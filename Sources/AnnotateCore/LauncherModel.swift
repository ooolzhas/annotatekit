// Pure state model for the floating launcher pill
// (Figma PVX9n74hzo5BWauvymG141, frames 9265:14439 and 9265:14691).
// `LauncherStatus` decides whether the pill is idle or narrating the last Send, and owns the one-line
// title it carries; `DeliveryStage` is where that Send has got to. The pill replaces the old delivery
// ring and toasts, so every delivery message lives here as the pill's title. The controller and the
// view switch on these instead of re-deriving the conditions, so the rules stay testable on Linux.

import Foundation

public enum DeliveryStage: Equatable, Sendable {
    /// Figma 9265:14691 (sample `count: 4`): the bundle is written and no agent has it yet.
    case sent(count: Int)
    /// No Figma frame: nobody picked the bundle up after `unclaimedAfter`. Derived from the old unclaimed toast.
    case unclaimed
    /// Figma 9273:17925 (hint line "Delivered to Claude"): handed to the agent, not opened yet.
    case delivered
    /// Figma 9273:18020 (hint line "Claude looking at it"): the agent opened the bundle.
    case received
    /// Figma 9273:18115 shows one ("Changes applied, reinstalling"): the agent is working; the message
    /// comes from its `status.json`.
    case working(message: String?)
    /// No Figma frame; the agent asked about one pin (annotation_ask / annotate ask). Not final: the
    /// Send is still open while the question waits for a reply.
    case question(pin: Int)
    /// No Figma frame: the agent finished; the message comes from its `status.json`.
    case done(message: String?)
    /// No Figma frame: the agent gave up; the message comes from its `status.json`.
    case failed(message: String?)
    /// No Figma frame: the bundle couldn't be written, so the prompt was copied instead.
    /// Shortened from the old write-failure toast.
    case notSaved
    /// No Figma frame: the bundle is saved, but no agent was connected when it went out (no fresh
    /// `agent.json`). Said at once instead of waiting out `unclaimedAfter`; tracking goes on, so an
    /// agent that connects in time still picks it up and narrates over this.
    case noAgent

    /// Final stages hold for `LauncherStatus.finalHold` and then the launcher returns to idle;
    /// the others are still waiting on the agent.
    public var isFinal: Bool {
        switch self {
        case .done, .failed, .notSaved, .noAgent: true
        case .sent, .unclaimed, .delivered, .received, .working, .question: false
        }
    }

    /// What the device plays when the Send reaches this stage: a light tick while it moves along,
    /// success when the agent is done, a warning when it needs the user (a question, nobody picked it
    /// up), an error when it failed.
    public var haptic: DeliveryHaptic {
        switch self {
        case .sent, .delivered, .received, .working: .tick
        case .done: .success
        case .question, .unclaimed, .noAgent: .warning
        case .failed, .notSaved: .error
        }
    }
}

/// The feedback a delivery stage change plays; AnnotateKit maps it onto UIKit's generators.
public enum DeliveryHaptic: Equatable, Sendable {
    case tick, success, warning, error
}

public enum LauncherStatus: Equatable, Sendable {
    /// Figma 9265:14439 shows `pending: 0`. `pending > 0` has no frame: it is derived to show pins saved
    /// but not sent, replacing the old count badge.
    case idle(pending: Int)
    /// Figma 9265:14691 is `.sent`; every other stage has no frame.
    case delivery(DeliveryStage)

    public struct Inputs: Equatable, Sendable {
        /// The stage the controller is narrating, or nil once it has cleared.
        public var delivery: DeliveryStage?
        /// Pins saved but not sent.
        public var pendingCount: Int

        public init(delivery: DeliveryStage?, pendingCount: Int) {
            self.delivery = delivery
            self.pendingCount = pendingCount
        }
    }

    /// Delivery wins while one is showing; otherwise idle with max(pendingCount, 0).
    public static func resolve(_ inputs: Inputs) -> LauncherStatus {
        // The pill has one line, and the Send in flight is the news; pending pins wait their turn
        if let delivery = inputs.delivery { return .delivery(delivery) }
        return .idle(pending: max(inputs.pendingCount, 0))
    }

    /// Idle pill title (Figma 9265:14505).
    public static let idleTitle = "Annotate"

    /// Seconds a final stage (done, failed, notSaved, noAgent) shows before the launcher returns to idle.
    /// No Figma source: the same 6 s the old delivery ring held, so the result stays readable as long as before.
    public static let finalHold: Double = 6
    /// Seconds "Not picked up yet" shows before the launcher returns to idle (polling continues).
    /// No Figma source: the same 4 s as the old unclaimed toast; it's a nudge, not a result, so it leaves sooner.
    public static let unclaimedHold: Double = 4

    /// Sent title: "4 notes sent", "1 note sent". The old launcher frame (Figma 9265:14691, text 9265:14757)
    /// showed the sample "4 comments sent"; the wording now follows the newer overlay design (9272:17592),
    /// which says "notes" everywhere ("4 notes", 9272:17114). Figma shows only the plural; the singular has
    /// no frame and is derived. A count ≤ 0 reads as 1 because a Send always carries at least one pin.
    public static func sentTitle(_ count: Int) -> String {
        let count = max(count, 1)
        return count == 1 ? "1 note sent" : "\(count) notes sent"
    }

    public var title: String {
        switch self {
        case .idle(let pending):
            // No Figma frame for pending > 0: open question for the user, shipped as "Annotate · N"
            pending > 0 ? "\(Self.idleTitle) · \(pending)" : Self.idleTitle
        case .delivery(let stage):
            switch stage {
            case .sent(let count):
                Self.sentTitle(count)
            // delivered and received follow the Figma hint line (9273:18006, 9273:18101) instead of the old
            // toasts; the launcher has no agent input, so they keep a fixed "Claude". No Figma frame for the
            // rest: copy reused or shortened from the old delivery toasts so it fits the one-line pill.
            // unclaimed, notSaved and failed-with-message are new wording.
            case .unclaimed:
                "Not picked up yet"
            case .delivered:
                "Delivered to Claude"
            case .received:
                "Claude looking at it"
            case .working(let message):
                Self.cleaned(message) ?? "Claude is working"
            case .question(let pin):
                // No Figma frame; the agent asked about one pin (annotation_ask / annotate ask)
                "Question on note \(pin)"
            case .done(let message):
                Self.cleaned(message).map { "Done · \($0)" } ?? "Done"
            case .failed(let message):
                Self.cleaned(message).map { "Couldn't finish · \($0)" } ?? "Claude couldn't finish"
            case .notSaved:
                "Couldn't save · prompt copied"
            case .noAgent:
                "Saved · no agent connected"
            }
        }
    }

    /// The agent's message trimmed, or nil when nothing is left: a blank `status.json` message would
    /// otherwise render as "Done · " or an empty pill.
    private static func cleaned(_ message: String?) -> String? {
        guard let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
