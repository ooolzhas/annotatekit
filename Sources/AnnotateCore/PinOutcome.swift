// Pure model of each sent pin's result, as the app's notes sheet shows it. `PinOutcome` turns the
// agent's `PinStatus` (from status.json) into what the badge, label and detail line read;
// `PinResult` pairs it with the pin's comment, subject and intent and builds the card's summary line.
// `SentPinMark` is what a sent pin's badge shows on the frozen screen after a Send: its number, a
// spinner while the agent has it, or the outcome's glyph. `NoteFilter` is the notes sheet's tags.
// Views switch on these instead of reading `PinStatus` directly, so the rules stay testable on Linux.

import Foundation

/// One sent pin's result as the app shows it, from the agent's PinStatus.
public enum PinOutcome: Equatable, Sendable {
    /// Sent, nothing reported yet.
    case open
    case resolved(summary: String?)
    case dismissed(reason: String?)
    case question(String)
    case answered(question: String?, reply: String)

    public enum Tone: Sendable, Equatable { case neutral, success, muted, attention }

    /// No status means the agent hasn't reported on the pin yet. Blank notes and replies count as
    /// absent, so the card never shows an empty "Resolved · " detail.
    public static func resolve(_ status: PinStatus?) -> PinOutcome {
        guard let status else { return .open }
        switch status.state {
        case .resolved:
            return .resolved(summary: cleaned(status.note))
        case .dismissed:
            return .dismissed(reason: cleaned(status.note))
        case .question:
            // A question with no text is still a question: the user can still reply to it
            return .question(cleaned(status.note) ?? "")
        case .answered:
            return .answered(question: cleaned(status.note), reply: cleaned(status.reply) ?? "")
        }
    }

    public var isQuestion: Bool {
        if case .question = self { return true }
        return false
    }

    public var tone: Tone {
        switch self {
        case .open, .answered: .neutral
        case .resolved: .success
        case .dismissed: .muted
        case .question: .attention
        }
    }

    /// Badge glyph. nil means the badge shows the pin number instead: open and answered pins are
    /// still in progress, so the number keeps them easy to match with the pins on screen.
    public var symbol: String? {
        switch self {
        case .open, .answered: nil
        case .resolved: "checkmark"
        case .dismissed: "xmark"
        case .question: "questionmark"
        }
    }

    public var label: String {
        switch self {
        case .open: "Waiting"
        case .resolved: "Resolved"
        case .dismissed: "Dismissed"
        case .question: "Question"
        case .answered: "Answered"
        }
    }

    /// The summary, reason, question or reply, trimmed. Blank becomes nil. Cases can be built directly
    /// (not only via `resolve`), so this trims again.
    public var detail: String? {
        switch self {
        case .open: nil
        case .resolved(let summary): Self.cleaned(summary)
        case .dismissed(let reason): Self.cleaned(reason)
        case .question(let question): Self.cleaned(question)
        case .answered(_, let reply): Self.cleaned(reply)
        }
    }

    static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// One row of the notes sheet: a pin and what the agent reported on it.
public struct PinResult: Equatable, Sendable, Identifiable {
    public var index: Int
    /// The pin's comment, trimmed.
    public var comment: String
    /// What the pin points at: the element's display name, or "Spot" / "Region" / "Sketch".
    public var subject: String
    public var intent: AnnotationIntent
    public var outcome: PinOutcome

    public var id: Int { index }

    public init(index: Int, comment: String, subject: String, intent: AnnotationIntent, outcome: PinOutcome) {
        self.index = index
        self.comment = comment
        self.subject = subject
        self.intent = intent
        self.outcome = outcome
    }

    /// One result per pin (sorted by index), outcome from the matching status (by index).
    public static func results(for pins: [Annotation], statuses: [PinStatus]) -> [PinResult] {
        // The writer upserts by index, so duplicates shouldn't occur; if they do, the later entry wins
        var byIndex: [Int: PinStatus] = [:]
        for status in statuses { byIndex[status.index] = status }

        return pins
            .sorted { $0.index < $1.index }
            .map { pin in
                PinResult(
                    index: pin.index,
                    comment: pin.comment.trimmingCharacters(in: .whitespacesAndNewlines),
                    subject: subject(of: pin),
                    // Bundles from before intents existed have none: those pins were all fixes
                    intent: pin.intent ?? .fix,
                    outcome: PinOutcome.resolve(byIndex[pin.index])
                )
            }
    }

    /// "2 resolved · 1 dismissed · 1 question" (counts > 0 only, in that order: resolved, dismissed,
    /// question, answered, waiting); nil when every pin is .open, since "3 waiting" alone adds nothing
    /// the delivery hint doesn't already say.
    public static func summary(_ results: [PinResult]) -> String? {
        guard results.contains(where: { $0.outcome != .open }) else { return nil }

        var resolved = 0, dismissed = 0, questions = 0, answered = 0, waiting = 0
        for result in results {
            switch result.outcome {
            case .open: waiting += 1
            case .resolved: resolved += 1
            case .dismissed: dismissed += 1
            case .question: questions += 1
            case .answered: answered += 1
            }
        }

        let parts: [String?] = [
            resolved > 0 ? "\(resolved) resolved" : nil,
            dismissed > 0 ? "\(dismissed) dismissed" : nil,
            questions > 0 ? "\(questions) \(questions == 1 ? "question" : "questions")" : nil,
            answered > 0 ? "\(answered) answered" : nil,
            waiting > 0 ? "\(waiting) waiting" : nil
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// Mirrors the prompt's subject naming (PromptRenderer), minus the sketch's "over <element>" suffix,
    /// which is too long for a one-line row.
    private static func subject(of pin: Annotation) -> String {
        switch pin.kind {
        case .element: pin.element?.displayName() ?? "Element"
        case .point: "Spot"
        case .region: "Region"
        case .sketch: "Sketch"
        }
    }
}

/// A sent pin's badge on the frozen screen while annotate mode stays open after a Send
/// (Figma 9276:28552): a spinner while the agent has the pin (9276:27574), the outcome's glyph once
/// it reports one (9276:27954, a green checkmark for resolved), otherwise the pin's number (9276:28054).
public enum SentPinMark: Equatable, Sendable {
    case number
    case progress
    case symbol(String, PinOutcome.Tone)

    /// A glyph wins whatever the delivery is doing. Open and answered pins (the agent has the reply)
    /// spin while the Send is on its way to the agent or with it, and show their number once nothing
    /// is in flight: nobody picked it up, it finished, failed or was only saved.
    public static func resolve(outcome: PinOutcome, delivery: DeliveryStage?) -> SentPinMark {
        if let symbol = outcome.symbol { return .symbol(symbol, outcome.tone) }
        guard let delivery, spins(during: delivery) else { return .number }
        return .progress
    }

    private static func spins(during stage: DeliveryStage) -> Bool {
        switch stage {
        case .sent, .delivered, .received, .working, .question: true
        case .unclaimed, .done, .failed, .notSaved, .noAgent: false
        }
    }
}

/// The notes sheet's tags (owner request, no Figma): which notes each one lists.
public enum NoteFilter: String, CaseIterable, Sendable {
    /// Saved but not sent yet.
    case current
    /// Sent and still with the agent: waiting, asked about, or answered.
    case inProgress
    /// The agent resolved it.
    case resolved
    /// The agent dismissed it, or its Send failed or couldn't be saved.
    case failed

    public var title: String {
        switch self {
        case .current: "Current"
        case .inProgress: "In Progress"
        case .resolved: "Resolved"
        case .failed: "Failed"
        }
    }

    /// What the sheet says when the tag lists nothing. No Figma frame (derived).
    public var emptyTitle: String {
        switch self {
        case .current: OverlayChrome.emptyTitle
        case .inProgress: "Nothing in progress"
        case .resolved: "Nothing resolved yet"
        case .failed: "Nothing failed"
        }
    }

    /// Where a sent pin belongs. The agent's report decides first. A pin it never reported on follows
    /// its whole Send: resolved once the agent finished it, failed when it failed or couldn't be
    /// written, otherwise still in progress.
    public static func of(_ outcome: PinOutcome, delivery: DeliveryStage?) -> NoteFilter {
        switch outcome {
        case .resolved: return .resolved
        case .dismissed: return .failed
        case .question, .answered: return .inProgress
        case .open:
            switch delivery {
            case .done: return .resolved
            case .failed, .notSaved: return .failed
            default: return .inProgress
            }
        }
    }

    /// The tag the sheet opens on: the first that lists anything, in tag order, else Current (whose
    /// empty state says how to add a note).
    public static func initial(counts: [NoteFilter: Int]) -> NoteFilter {
        allCases.first { (counts[$0] ?? 0) > 0 } ?? .current
    }
}
