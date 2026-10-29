// Pure state model for the annotate overlay (Figma PVX9n74hzo5BWauvymG141, group 9272:17592).
// `OverlayChrome` decides which bottom chrome shows (the review bar, the comment card, the reply card for
// an agent's question about one sent pin, or the last Send's results card) and the copy it carries,
// including whether the open pin can be saved (it needs a comment); `ReviewHint` decides the
// line above the review bar (gestures, agent connected, offline, or the last Send's delivery narration
// with its elapsed time, including an agent's open question) and whether the bar's action reads Send or
// Save; `PointerIntent` classifies a touch on the frozen screen as a pen stroke, a hold or a tap.
// Views and the controller switch on these instead of re-deriving the conditions, so the rules live
// in one place and stay testable on Linux.

import Foundation

public enum OverlayChrome: Equatable, Sendable {
    /// No pin open: the review bar (back chevron, count title, trash, Send). Figma 9272:17041 shows
    /// `count: 4`. The gestures text now lives on the hint line above the bar (`ReviewHint.gestures`).
    /// `count: 0` has no frame: it is derived, showing `emptyTitle` with trash and Send disabled.
    case review(count: Int)
    /// A pin is open: the comment card docked above the keyboard.
    /// `canSubmit: false` is Figma 9257:13322, also Figma 9272:16785 (empty comment, ↑ dimmed);
    /// `canSubmit: true` is Figma 9257:13403 (comment typed, ↑ filled blue), also Figma 9272:16867
    /// (typed) / 9272:16949 (typed, with 3 attached images; images come from the draft, not this state).
    case composing(canSubmit: Bool)
    /// Answering an agent's question about one sent pin: the reply card docked above the keyboard.
    /// No Figma frame (derived): `canSubmit` follows the reply text the way `composing` follows the comment.
    case replying(canSubmit: Bool)
    /// The last Send's per-pin results card (resolved, dismissed, questions).
    /// No Figma frame (derived): shown only while opened and while there is at least one result.
    case results(count: Int)

    public struct Inputs: Equatable, Sendable {
        public var isDraftOpen: Bool
        /// The open pin's comment; ignored when no pin is open.
        public var draftComment: String
        public var pinCount: Int
        /// The reply being typed, non-nil while answering an agent's question.
        public var replyText: String?
        /// The results card was opened (from the hint line, or on start with an open question).
        public var isShowingResults: Bool
        /// How many pins the last Send's results list.
        public var resultCount: Int

        /// The new inputs default to "not replying, no results", so existing callers keep
        /// today's review / composing behavior.
        public init(
            isDraftOpen: Bool,
            draftComment: String,
            pinCount: Int,
            replyText: String? = nil,
            isShowingResults: Bool = false,
            resultCount: Int = 0
        ) {
            self.isDraftOpen = isDraftOpen
            self.draftComment = draftComment
            self.pinCount = pinCount
            self.replyText = replyText
            self.isShowingResults = isShowingResults
            self.resultCount = resultCount
        }
    }

    /// Precedence: a reply in progress, then an open draft, then the results card, then the review bar.
    /// Replying wins because the agent is waiting on it and the reply card owns the keyboard; a draft
    /// comes next for the same keyboard reason; results only replace the review bar, never a card the
    /// user is typing into. No Figma frame for this ordering (derived).
    public static func resolve(_ inputs: Inputs) -> OverlayChrome {
        if let reply = inputs.replyText {
            // A blank reply tells the agent nothing, same rule as a blank comment
            return .replying(canSubmit: !trimmed(reply).isEmpty)
        }
        if inputs.isDraftOpen {
            // Whitespace alone isn't a comment worth sending to the agent
            return .composing(canSubmit: !trimmed(inputs.draftComment).isEmpty)
        }
        if inputs.isShowingResults && inputs.resultCount > 0 {
            return .results(count: inputs.resultCount)
        }
        return .review(count: max(inputs.pinCount, 0))
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Comment field placeholder (Figma 9257:13392 / 9272:16856).
    public static let placeholder = "Describe the change"
    /// Action capsule title while an agent is listening (Figma 9272:17119).
    public static let sendTitle = "Send"
    /// Action capsule title while no agent is listening (Figma 9272:17306): the notes are written
    /// either way, but nobody picks them up yet, so "Send" would overpromise.
    public static let saveTitle = "Save"
    /// Review title with no notes yet. No Figma frame: derived. The gestures text that used to sit
    /// here moved to the hint line above the bar, so the title just says there is nothing to count.
    public static let emptyTitle = "No notes yet"

    /// Trash confirmation title. No Figma frame: trash wipes every pin at once with no undo, so it
    /// asks first and names what goes.
    public static func clearTitle(_ count: Int) -> String {
        count == 1 ? "Delete 1 note?" : "Delete \(max(count, 0)) notes?"
    }
    /// Destructive button in the trash confirmation.
    public static let clearAction = "Delete"

    /// Review bar title (Figma 9272:17114, sample "4 notes"; the 4 is sample data): "4 notes", "1 note",
    /// and `emptyTitle` when there is nothing to count (0 or a negative input).
    /// Figma shows only the plural; the singular "1 note" has no frame and is derived.
    public static func countTitle(_ count: Int) -> String {
        guard count > 0 else { return emptyTitle }
        return count == 1 ? "1 note" : "\(count) notes"
    }

    /// Reply field placeholder. No Figma frame (derived).
    public static let replyPlaceholder = "Reply"
    /// Results card row action on a question. No Figma frame (derived).
    public static let replyAction = "Reply"
    /// Toast after a reply is written for the agent. No Figma frame (derived).
    public static let replySentToast = "Reply sent"

    /// Results card title: "Last Send · 1 note" / "Last Send · N notes". No Figma frame (derived);
    /// the count wording matches `countTitle` so the bar and the card agree.
    public static func resultsTitle(_ count: Int) -> String {
        count == 1 ? "Last Send · 1 note" : "Last Send · \(max(count, 0)) notes"
    }

    /// Reply card header, e.g. "Claude asks about note 2". No Figma frame (derived); the agent's name
    /// goes through `ReviewHint.displayName` so it reads like the hint line.
    public static func askedTitle(agent: String, pin: Int) -> String {
        "\(ReviewHint.displayName(agent)) asks about note \(pin)"
    }

    /// Send (and trash) are live only on the review bar with at least one pin; while composing or
    /// replying the card's ↑ governs, and the results card replaces the bar, so Send isn't shown.
    public var canSend: Bool {
        switch self {
        case .review(let count): count > 0
        case .composing, .replying, .results: false
        }
    }
}

/// The line above the review bar (Figma 9272:17592: 9272:17121 / 9272:17215 / 9272:17309).
/// Figma shows the gestures hint and the connected line with the same agent state, so which one shows
/// is a timing rule: the connection is news for `connectionNewsHold` seconds, then the gestures hint
/// takes over. Offline has no such timeout, because Save instead of Send must stay explained.
/// While a Send is being tracked, the line narrates its delivery instead (Figma 9273:17925 / 9273:18020 /
/// 9273:18115): the launcher pill is hidden in annotate mode, so this is the only place the progress shows.
public enum ReviewHint: Equatable, Sendable {
    /// Figma 9272:17041: "Draw, tap or hold to annotate", no dot.
    case gestures
    /// Figma 9272:17134: "Claude connected", green dot. The pull mode has no frame (derived).
    case connected(agent: String, mode: AgentPresence.Mode)
    /// Figma 9272:17228: "Agent offline · Notes will be saved", red dot, and the action reads Save.
    case offline
    /// The last Send's progress. `agent` may be a raw or display name: `resolve` stores the display
    /// name, and `text` applies `displayName` again (idempotent), so a hand-built "Claude Code" reads "Claude".
    /// Figma 9273:17925 (`.delivered`), 9273:18020 (`.received`), 9273:18115 (`.working(message:)`);
    /// every other stage has no frame and is derived from the launcher's copy.
    case delivery(DeliveryStage, agent: String)

    public enum Dot: Equatable, Sendable {
        /// Green (Figma 9272:17214).
        case connected
        /// Red (Figma 9272:17308).
        case offline
        /// The agent is waiting on the user (an open question). No Figma frame (derived): neither
        /// "going to plan" green nor "something failed" red, so it gets its own color.
        case attention
    }

    public struct Inputs: Equatable, Sendable {
        /// Who listens for Sends (agent.json), nil when nobody does.
        public var agent: AgentPresence?
        /// Annotate mode just opened, or the connection just changed (for `connectionNewsHold`).
        public var isConnectionNews: Bool
        /// The tracked Send's stage, nil when no Send is being tracked.
        public var delivery: DeliveryStage?

        public init(agent: AgentPresence?, isConnectionNews: Bool, delivery: DeliveryStage? = nil) {
            self.agent = agent
            self.isConnectionNews = isConnectionNews
            self.delivery = delivery
        }
    }

    /// A tracked Send → `.delivery`, ahead of everything: the user just acted and wants to see what
    /// happened to it. With no agent connected the subject still reads "Agent" (`displayName("")`).
    /// Otherwise: no agent → `.offline`, whatever the news flag, because with nobody listening the
    /// Save action needs its explanation the whole time. Agent + news → `.connected`. Agent, no news
    /// → `.gestures`.
    public static func resolve(_ inputs: Inputs) -> ReviewHint {
        if let stage = inputs.delivery {
            return .delivery(stage, agent: displayName(inputs.agent?.agent ?? ""))
        }
        guard let presence = inputs.agent else { return .offline }
        if inputs.isConnectionNews {
            return .connected(agent: presence.agent, mode: presence.mode)
        }
        return .gestures
    }

    /// Seconds the connection line shows after annotate mode opens, or after the agent connection
    /// changes while annotating, before it yields to the gestures hint. No Figma source (gap
    /// threshold): long enough to read a short line once, short enough that the gestures hint is
    /// what a user sees while actually annotating.
    public static let connectionNewsHold: Double = 3

    /// The short name for the hint line. Figma 9272:17215 reads "Claude connected" for the agent
    /// that reports itself as "Claude Code", so the product suffix is dropped to keep the line short.
    /// Other names pass through; a blank name still needs a subject, so it reads "Agent".
    public static func displayName(_ agent: String) -> String {
        let trimmed = agent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Agent" }
        if trimmed == "Claude Code" { return "Claude" }
        return trimmed
    }

    public var text: String {
        switch self {
        case .gestures:
            // Figma 9272:17121
            "Draw, tap or hold to annotate"
        case .connected(let agent, .push):
            // Figma 9272:17215 (sample "Claude connected")
            "\(Self.displayName(agent)) connected"
        case .connected(let agent, .pull):
            // No Figma frame (derived): a pull agent reads sessions only when asked, so the line
            // tells the user to ask it, matching `AgentPresence.accessibilityDescription`.
            "\(Self.displayName(agent)) connected · ask it to check"
        case .offline:
            // Figma 9272:17309
            "Agent offline · Notes will be saved"
        case .delivery(let stage, let agent):
            switch stage {
            case .sent(let count):
                // No Figma frame (derived): the launcher's sent title, so the pill and the line agree
                LauncherStatus.sentTitle(count)
            case .unclaimed:
                // No Figma frame (derived): launcher copy
                "Not picked up yet"
            case .delivered:
                // Figma 9273:18006 (sample "Delivered to Claude")
                "Delivered to \(Self.displayName(agent))"
            case .received:
                // Figma 9273:18101 (sample "Claude looking at it")
                "\(Self.displayName(agent)) looking at it"
            case .question(let pin):
                // No Figma frame (derived): the agent asked about one pin and waits for the reply
                "\(Self.displayName(agent)) asked about note \(pin)"
            case .working(let message):
                // Figma 9273:18196 shows the agent's own status.json message (sample "Changes applied,
                // reinstalling"); the fallback without a message is derived
                Self.cleaned(message) ?? "\(Self.displayName(agent)) is working"
            case .done(let message):
                // No Figma frame (derived): launcher copy
                Self.cleaned(message).map { "Done · \($0)" } ?? "Done"
            case .failed(let message):
                // No Figma frame (derived): launcher copy, with the agent's name in the fallback
                Self.cleaned(message).map { "Couldn't finish · \($0)" } ?? "\(Self.displayName(agent)) couldn't finish"
            case .notSaved:
                // No Figma frame (derived): launcher copy
                "Couldn't save · prompt copied"
            case .noAgent:
                // No Figma frame (derived): launcher copy
                "Saved · no agent connected"
            }
        }
    }

    /// nil for the gestures hint, which has no dot in Figma 9272:17121.
    /// Delivery: green while things go to plan (Figma 9273:18004 / 18099 / 18194 for delivered, received
    /// and working; sent and done derived), red for the stages that need the user's attention (unclaimed,
    /// failed, notSaved, noAgent; derived), attention for an agent's open question (derived).
    public var dot: Dot? {
        switch self {
        case .gestures: nil
        case .connected: .connected
        case .offline: .offline
        case .delivery(let stage, _):
            switch stage {
            case .sent, .delivered, .received, .working, .done: .connected
            case .unclaimed, .failed, .notSaved, .noAgent: .offline
            case .question: .attention
            }
        }
    }

    /// Whether the line appends the time since Send (Figma 9273:18007 / 18102 / 18197, samples "1s",
    /// "2s", "9s"). Only while a delivery is still in flight (derived for sent, unclaimed and question,
    /// which is non-final): once the result is in, the figure stops mattering.
    public var showsElapsed: Bool {
        switch self {
        case .delivery(let stage, _): !stage.isFinal
        case .gestures, .connected, .offline: false
        }
    }

    /// Elapsed time since Send: "Ns" below a minute (Figma 9273:18007 sample "1s"), a negative input
    /// (clock skew) reads "0s". From 60 s it reads whole minutes, floored ("Nm"); no Figma frame
    /// (derived), since seconds past a minute are noise on a one-line hint.
    public static func elapsedText(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        if seconds < secondsPerMinute { return "\(seconds)s" }
        return "\(seconds / secondsPerMinute)m"
    }

    /// Where `elapsedText` switches from seconds to minutes.
    private static let secondsPerMinute = 60

    /// "Save" while offline (Figma 9272:17306), else "Send" (Figma 9272:17119).
    /// A delivery reads "Save" only for `.noAgent`: that is the one stage that proves nobody is
    /// listening, so the next action would only save too. Every other stage keeps "Send" (derived).
    /// Two accepted edges follow from delivery taking precedence in `resolve`:
    /// - The agent disconnects while a delivery is narrating: delivery wins, so the bar still reads
    ///   "Send" until the delivery clears.
    /// - An agent connects during the `.noAgent` hold: the bar reads "Save" for up to
    ///   `LauncherStatus.finalHold`.
    public var actionTitle: String {
        switch self {
        case .offline, .delivery(.noAgent, _): OverlayChrome.saveTitle
        case .gestures, .connected, .delivery: OverlayChrome.sendTitle
        }
    }

    /// The agent's message trimmed, or nil when nothing is left, so a blank `status.json` message falls
    /// back to the stage's own copy instead of rendering "Done · " or an empty line.
    private static func cleaned(_ message: String?) -> String? {
        guard let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
