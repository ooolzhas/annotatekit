// Pure state model for the annotate overlay (Figma group 9272:17592).
// `OverlayChrome` decides which bottom chrome shows (the review bar, the comment card, or the reply card
// for an agent's question about one sent pin) and the copy it carries,
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

    public struct Inputs: Equatable, Sendable {
        public var isDraftOpen: Bool
        /// The open pin's comment; ignored when no pin is open.
        public var draftComment: String
        public var pinCount: Int
        /// The reply being typed, non-nil while answering an agent's question.
        public var replyText: String?

        /// `replyText` defaults to "not replying", so callers that never reply keep the review /
        /// composing behavior.
        public init(isDraftOpen: Bool, draftComment: String, pinCount: Int, replyText: String? = nil) {
            self.isDraftOpen = isDraftOpen
            self.draftComment = draftComment
            self.pinCount = pinCount
            self.replyText = replyText
        }
    }

    /// Precedence: a reply in progress, then an open draft, then the review bar. Replying wins because
    /// the agent is waiting on it and the reply card owns the keyboard; a draft comes next for the same
    /// keyboard reason. The last Send's results live in the notes sheet, over whichever of these shows.
    /// No Figma frame for this ordering (derived).
    public static func resolve(_ inputs: Inputs) -> OverlayChrome {
        if let reply = inputs.replyText {
            // A blank reply tells the agent nothing, same rule as a blank comment
            return .replying(canSubmit: !trimmed(reply).isEmpty)
        }
        if inputs.isDraftOpen {
            // Whitespace alone isn't a comment worth sending to the agent
            return .composing(canSubmit: !trimmed(inputs.draftComment).isEmpty)
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

    /// Clear-all confirmation title. No Figma frame: clearing wipes every pin at once with no undo, so
    /// it asks first and names what goes.
    public static func clearTitle(_ count: Int) -> String {
        count == 1 ? "Delete 1 note?" : "Delete \(max(count, 0)) notes?"
    }
    /// Destructive button in the clear-all confirmation.
    public static let clearAction = "Delete"
    /// The notes sheet's title. No Figma frame.
    public static let notesSheetTitle = "My Notes"
    /// Clear-all button in the notes sheet's toolbar. No Figma frame: the bar lost its trash button
    /// (9276:27550), so clearing lives with the list now.
    public static let clearAllTitle = "Clear All"
    /// Notes sheet row detail for a pin on another frozen screen, which can't open from here. No
    /// Figma frame (derived).
    public static let otherScreenNote = "Another screen"

    /// Review bar title (Figma 9272:17114, sample "4 notes"; the 4 is sample data): "4 notes", "1 note",
    /// and `emptyTitle` when there is nothing to count (0 or a negative input).
    /// Figma shows only the plural; the singular "1 note" has no frame and is derived.
    public static func countTitle(_ count: Int) -> String {
        guard count > 0 else { return emptyTitle }
        return count == 1 ? "1 note" : "\(count) notes"
    }

    /// Reply field placeholder. No Figma frame (derived).
    public static let replyPlaceholder = "Reply"
    /// Notes sheet row action on a question. No Figma frame (derived).
    public static let replyAction = "Reply"
    /// Toast after a reply is written for the agent. No Figma frame (derived).
    public static let replySentToast = "Reply sent"


    /// Reply card header, e.g. "Claude asks about note 2". No Figma frame (derived); the agent's name
    /// goes through `ReviewHint.displayName` so it reads like the hint line.
    public static func askedTitle(agent: String, pin: Int) -> String {
        "\(ReviewHint.displayName(agent)) asks about note \(pin)"
    }

    /// Send is live only on the review bar with at least one pin; while composing or replying the
    /// card's ↑ governs, so Send isn't shown.
    public var canSend: Bool {
        switch self {
        case .review(let count): count > 0
        case .composing, .replying: false
        }
    }
}

/// The line above the review bar (Figma 9272:17592: 9272:17121 / 9272:17215 / 9272:17309).
/// Figma shows the gestures hint and the connected line with the same agent state, so which one shows
/// is a timing rule: annotate mode opens on the gestures hint for `introHold` seconds, then the line
/// settles on the connection, "Claude connected" or "Agent offline", and stays there (design choice).
/// While a Send is being tracked, the line narrates its delivery instead (Figma 9273:17925 / 9273:18020 /
/// 9273:18115): the launcher pill is hidden in annotate mode, so this is the only place the progress shows.
public enum ReviewHint: Equatable, Sendable {
    /// Figma 9272:17041: "Draw, tap or hold to annotate", no dot.
    case gestures
    /// Figma 9272:17134: "Claude connected", green dot. The pull mode has no frame (derived).
    case connected(agent: String, mode: AgentPresence.Mode)
    /// Figma 9272:17228: "No agent connected · Notes will be saved", red dot, and the
    /// action reads Save.
    case offline
    /// The last Send's progress. `agent` may be a raw or display name: `resolve` stores the display
    /// name, and `text` applies `displayName` again (idempotent), so a hand-built "Claude Code" reads "Claude".
    /// Figma 9273:17925 (`.delivered`), 9273:18020 (`.received`), 9273:18115 (`.working(message:)`);
    /// every other stage has no frame and is derived from the launcher's copy.
    /// `notes`: how many notes the Send carries; `written`: how many are written into it so far.
    case delivery(DeliveryStage, agent: String, notes: Int = 0, written: Int = 0)

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
        /// Annotate mode opened less than `introHold` seconds ago.
        public var isIntro: Bool
        /// The tracked Send's stage, nil when no Send is being tracked.
        public var delivery: DeliveryStage?
        /// How many notes the tracked Send carries.
        public var notes: Int
        /// How many of them are written into it so far ("Sending notes · 1/4").
        public var written: Int

        public init(agent: AgentPresence?, isIntro: Bool, delivery: DeliveryStage? = nil, notes: Int = 0, written: Int = 0) {
            self.agent = agent
            self.isIntro = isIntro
            self.delivery = delivery
            self.notes = notes
            self.written = written
        }
    }

    /// A tracked Send → `.delivery`, ahead of everything: the user just acted and wants to see what
    /// happened to it. With no agent connected the subject still reads "Agent" (`displayName("")`).
    /// Otherwise the intro → `.gestures`, whoever listens. After it: agent → `.connected`, none →
    /// `.offline`, and the line follows the connection from then on.
    public static func resolve(_ inputs: Inputs) -> ReviewHint {
        if let stage = inputs.delivery {
            return .delivery(stage, agent: displayName(inputs.agent?.agent ?? ""), notes: inputs.notes, written: inputs.written)
        }
        if inputs.isIntro { return .gestures }
        guard let presence = inputs.agent else { return .offline }
        return .connected(agent: presence.agent, mode: presence.mode)
    }

    /// Seconds the gestures hint shows after annotate mode opens, before the line settles on the
    /// connection. No Figma source (gap threshold): long enough to read the short how-to once.
    public static let introHold: Double = 3

    /// The short name for the hint line. Figma 9272:17215 reads "Claude connected" for the agent
    /// that reports itself as "Claude Code", so the product suffix is dropped to keep the line short.
    /// Other names pass through; a blank name still needs a subject, so it reads "Agent".
    public static func displayName(_ agent: String) -> String {
        let trimmed = agent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Agent" }
        if trimmed == "Claude Code" { return "Claude" }
        return trimmed
    }

    /// The whole line, as VoiceOver reads it: `headline`, then `detail` after " · ".
    public var text: String {
        let parts = parts
        return parts.detail.map { "\(parts.headline) · \($0)" } ?? parts.headline
    }

    /// The line's lead, drawn at full strength.
    public var headline: String { parts.headline }

    /// The second half of a two-part line, drawn after `headline` at half strength (Figma 9276:28049:
    /// "Notes will be saved" at opacity 50); nil for a one-part line. Only the offline line has a
    /// frame; the other two-part lines are split the same way (derived).
    public var detail: String? { parts.detail }

    /// Copy rules (rewritten 2026-10-29): every line opens with its subject (the agent, "No
    /// agent", or the notes), and the part after " · " is the consequence or the agent's own words.
    /// No Figma frame for the rewrite; the states are the Figma ones.
    private var parts: (headline: String, detail: String?) {
        switch self {
        case .gestures:
            // Figma 9272:17121
            return ("Draw, tap or hold to annotate", nil)
        case .connected(let agent, .push):
            // Figma 9272:17215 (sample "Claude connected")
            return ("\(Self.displayName(agent)) connected", nil)
        case .connected(let agent, .pull):
            // A pull agent reads sessions only when asked, matching `AgentPresence.accessibilityDescription`
            return ("\(Self.displayName(agent)) connected", "Checks when asked")
        case .offline:
            // Figma 9276:28048 / 9276:28049 states, rewritten copy
            return ("No agent connected", "Notes will be saved")
        case .delivery(let stage, let agent, let notes, let written):
            let agent = Self.displayName(agent)
            switch stage {
            case .sent:
                // The Send's notes as they're written into it, then held at the total until picked up
                return ("Sending notes", notes > 0 ? "\(min(max(written, 0), notes))/\(notes)" : nil)
            case .unclaimed:
                return ("\(agent) failed to receive your notes", nil)
            case .delivered:
                // Figma 9273:18006 state
                return ("\(agent) received your notes", nil)
            case .received:
                // Figma 9273:18101 state
                return ("\(agent) is reading…", nil)
            case .question(let pin):
                return ("\(agent) has a question", "Note \(pin)")
            case .working(let message):
                // Figma 9273:18196 shows the agent's own status.json message; agents write it as
                // "headline · next step" (the watcher skill), so it splits like the app's own lines
                return Self.cleaned(message).map(Self.split) ?? ("\(agent) is working…", nil)
            case .done:
                return ("\(agent) is done", notes > 0 ? OverlayChrome.countTitle(notes) : nil)
            case .failed(let message):
                return ("Error", Self.cleaned(message))
            case .notSaved:
                return ("Notes not saved", "Prompt copied")
            case .noAgent:
                return ("No agent connected", "Notes saved")
            }
        }
    }

    /// An agent's message as headline and detail, split at its first " · "; whole when either side
    /// would be empty.
    private static func split(_ message: String) -> (headline: String, detail: String?) {
        guard let separator = message.range(of: " · ") else { return (message, nil) }
        let headline = message[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        let detail = message[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !headline.isEmpty, !detail.isEmpty else { return (message, nil) }
        return (headline, detail)
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
        case .delivery(let stage, _, _, _):
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
        case .delivery(let stage, _, _, _): !stage.isFinal
        case .gestures, .connected, .offline: false
        }
    }

    /// Elapsed time since Send: "Ns" below a minute (Figma 9273:18007 sample "1s"), a negative input
    /// (clock skew) reads "0s". From 60 s it reads minutes and seconds ("1m 5s"), never minutes
    /// alone (design choice), so the counter keeps visibly moving.
    public static func elapsedText(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        if seconds < secondsPerMinute { return "\(seconds)s" }
        return "\(seconds / secondsPerMinute)m \(seconds % secondsPerMinute)s"
    }

    /// Where `elapsedText` adds minutes.
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
        case .offline, .delivery(.noAgent, _, _, _): OverlayChrome.saveTitle
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
