// Per-pin threads and acknowledged pins: SessionInbox.ask / markAnswered / updatePin keep each pin's
// conversation, status.json files from before threads rebuild it from note and reply, acknowledge
// orders the pins the agent started on, DeliveryStage.resolve names the one it's on, and the app's
// per-pin views (PinOutcome.working, PinResult.earlierMessages, SentPinMark, the thread line) follow.
// Dates are whole seconds because status.json and replies.json encode ISO 8601 without fractions.

@testable import AnnotateCore
import Foundation
import Testing

/// A throwaway `.annotate` directory holding one written session (pins 1–3), removed by the caller.
private struct ThreadFixture {
    let output: URL
    let id: String

    static let t0 = Date(timeIntervalSince1970: 1_793_196_900)

    init() throws {
        output = FileManager.default.temporaryDirectory
            .appendingPathComponent("annotate-threads-\(UUID().uuidString)", isDirectory: true)
        let session = Fixtures.session(annotations: [Fixtures.element, Fixtures.copyEdit, Fixtures.spot])
        id = session.id
        try SessionWriter.write(SessionBundle(session: session, images: [:]), prompt: "prompt\n", to: output)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: output)
    }

    func status() -> SessionStatus? {
        SessionInbox.readStatus(id: id, in: output)
    }

    func pin(_ index: Int) -> PinStatus? {
        status()?.pins?.first { $0.index == index }
    }

    /// Writes status.json by hand, as an older `annotate` would have.
    func writeRawStatus(_ json: String) throws {
        let url = SessionInbox.sessionDirectory(id, in: output).appendingPathComponent(SessionInbox.statusFile)
        try Data(json.utf8).write(to: url)
    }

    static func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }
}

private func agent(_ text: String, _ seconds: TimeInterval) -> PinMessage {
    PinMessage(role: .agent, text: text, at: ThreadFixture.at(seconds))
}

private func human(_ text: String, _ seconds: TimeInterval) -> PinMessage {
    PinMessage(role: .human, text: text, at: ThreadFixture.at(seconds))
}

// MARK: - Threads on disk

@Suite struct PinThreadInboxTests {
    @Test func askStartsTheThreadAndKeepsTheQuestionInNote() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }

        try SessionInbox.ask("Which blue?", pin: 1, id: fixture.id, in: fixture.output, at: ThreadFixture.at(0))

        let pin = try #require(fixture.pin(1))
        #expect(pin.state == .question)
        // Apps built before threads read the question from note
        #expect(pin.note == "Which blue?")
        #expect(pin.updatedAt == ThreadFixture.at(0))
        #expect(pin.thread == [agent("Which blue?", 0)])
    }

    @Test func eachRoundOfQuestionAndReplyAddsToTheThread() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }

        try SessionInbox.ask("Which blue?", pin: 1, id: fixture.id, in: fixture.output, at: ThreadFixture.at(0))
        try SessionInbox.markAnswered(PinReply(index: 1, text: "The brand one", at: ThreadFixture.at(10)), id: fixture.id, in: fixture.output)
        try SessionInbox.ask("Lighter or darker?", pin: 1, id: fixture.id, in: fixture.output, at: ThreadFixture.at(20))
        try SessionInbox.markAnswered(PinReply(index: 1, text: "Darker", at: ThreadFixture.at(30)), id: fixture.id, in: fixture.output)

        let pin = try #require(fixture.pin(1))
        #expect(pin.state == .answered)
        #expect(pin.note == "Lighter or darker?")
        #expect(pin.reply == "Darker")
        #expect(pin.thread == [
            agent("Which blue?", 0), human("The brand one", 10),
            agent("Lighter or darker?", 20), human("Darker", 30)
        ])
    }

    @Test func aReplyToAnEarlierRoundIsntDeliveredAgain() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }
        let first = PinReply(index: 1, text: "The brand one", at: ThreadFixture.at(10))

        try SessionInbox.ask("Which blue?", pin: 1, id: fixture.id, in: fixture.output, at: ThreadFixture.at(0))
        try SessionInbox.appendReply(first, id: fixture.id, in: fixture.output)
        try SessionInbox.markAnswered(first, id: fixture.id, in: fixture.output)
        try SessionInbox.ask("Lighter or darker?", pin: 1, id: fixture.id, in: fixture.output, at: ThreadFixture.at(20))
        #expect(SessionInbox.unansweredReplies(id: fixture.id, in: fixture.output).isEmpty)

        let second = PinReply(index: 1, text: "Darker", at: ThreadFixture.at(25))
        try SessionInbox.appendReply(second, id: fixture.id, in: fixture.output)
        #expect(SessionInbox.unansweredReplies(id: fixture.id, in: fixture.output) == [second])
    }

    @Test func askingAgainInTheSecondOfTheReplyWaitsForANewOne() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }
        let first = PinReply(index: 1, text: "Bold", at: ThreadFixture.at(10))

        try SessionInbox.ask("Semibold or bold?", pin: 1, id: fixture.id, in: fixture.output, at: ThreadFixture.at(0))
        try SessionInbox.appendReply(first, id: fixture.id, in: fixture.output)
        try SessionInbox.markAnswered(first, id: fixture.id, in: fixture.output)
        // The agent asks again within the second the reply is dated
        try SessionInbox.ask("Same weight for White?", pin: 1, id: fixture.id, in: fixture.output, at: ThreadFixture.at(10))

        #expect(fixture.pin(1)?.updatedAt == ThreadFixture.at(11))
        #expect(fixture.pin(1)?.thread?.last == agent("Same weight for White?", 11))
        #expect(SessionInbox.unansweredReplies(id: fixture.id, in: fixture.output).isEmpty)
    }

    @Test func aReplyMarkedTwiceIsInTheThreadOnce() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }
        let reply = PinReply(index: 2, text: "Shorter", at: ThreadFixture.at(5))

        try SessionInbox.ask("Shorter or bolder?", pin: 2, id: fixture.id, in: fixture.output, at: ThreadFixture.at(0))
        try SessionInbox.markAnswered(reply, id: fixture.id, in: fixture.output)
        try SessionInbox.markAnswered(reply, id: fixture.id, in: fixture.output)

        #expect(fixture.pin(2)?.thread == [agent("Shorter or bolder?", 0), human("Shorter", 5)])
    }

    @Test func resolvingAnAskedPinKeepsItsConversation() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }

        try SessionInbox.ask("Which blue?", pin: 1, id: fixture.id, in: fixture.output, at: ThreadFixture.at(0))
        try SessionInbox.markAnswered(PinReply(index: 1, text: "The brand one", at: ThreadFixture.at(10)), id: fixture.id, in: fixture.output)
        try SessionInbox.updatePin(PinStatus(index: 1, state: .resolved, note: "Used the brand blue"), id: fixture.id, in: fixture.output)

        let pin = try #require(fixture.pin(1))
        #expect(pin.state == .resolved)
        #expect(pin.note == "Used the brand blue")
        #expect(pin.thread == [agent("Which blue?", 0), human("The brand one", 10)])
    }

    @Test func aPinNobodyAskedAboutHasNoThread() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }

        try SessionInbox.updatePin(PinStatus(index: 3, state: .resolved, note: "Removed the gap"), id: fixture.id, in: fixture.output)
        try SessionInbox.updatePin(PinStatus(index: 3, state: .dismissed, note: "Matches the spec"), id: fixture.id, in: fixture.output)

        let pin = try #require(fixture.pin(3))
        #expect(pin.thread == nil)
        #expect(pin.messages.isEmpty)
        // An optional thread isn't written at all, so older readers see the file they know
        let data = try Data(contentsOf: SessionInbox.sessionDirectory(fixture.id, in: fixture.output)
            .appendingPathComponent(SessionInbox.statusFile))
        #expect(!String(decoding: data, as: UTF8.self).contains("thread"))
    }

    @Test func aPinWrittenBeforeThreadsRebuildsItsExchange() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }
        try fixture.writeRawStatus("""
            {"state": "working", "updatedAt": "2026-10-28T14:15:00Z", "pins": [
              {"index": 1, "state": "answered", "note": "Which blue?", "reply": "The brand one", "updatedAt": "2026-10-28T14:16:00Z"},
              {"index": 2, "state": "question", "note": " ", "updatedAt": "2026-10-28T14:16:00Z"},
              {"index": 3, "state": "resolved", "note": "Removed the gap", "updatedAt": "2026-10-28T14:16:00Z"}
            ]}
            """)
        let asked = try #require(ISO8601DateFormatter().date(from: "2026-10-28T14:16:00Z"))

        #expect(fixture.pin(1)?.messages == [
            PinMessage(role: .agent, text: "Which blue?", at: asked),
            PinMessage(role: .human, text: "The brand one", at: asked)
        ])
        // A blank question still counts as a message: only a missing one is left out
        #expect(fixture.pin(2)?.messages == [PinMessage(role: .agent, text: " ", at: asked)])
        // A resolved pin's note is its summary, not a question
        #expect(fixture.pin(3)?.messages == [])

        // Asking again carries the rebuilt exchange into the new thread, dated after it
        try SessionInbox.ask("Lighter or darker?", pin: 1, id: fixture.id, in: fixture.output, at: ThreadFixture.at(0))
        #expect(fixture.pin(1)?.thread == [
            PinMessage(role: .agent, text: "Which blue?", at: asked),
            PinMessage(role: .human, text: "The brand one", at: asked),
            PinMessage(role: .agent, text: "Lighter or darker?", at: asked.addingTimeInterval(1))
        ])
    }
}

// MARK: - Acknowledged pins

@Suite struct AcknowledgedPinTests {
    @Test func theMostRecentlyAcknowledgedPinIsLastAndARepeatMoves() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }

        try SessionInbox.acknowledge([1], id: fixture.id, in: fixture.output)
        try SessionInbox.acknowledge([3], id: fixture.id, in: fixture.output)
        try SessionInbox.acknowledge([1], id: fixture.id, in: fixture.output)
        #expect(fixture.status()?.acknowledged == [3, 1])

        try SessionInbox.acknowledge([2, 3], id: fixture.id, in: fixture.output)
        #expect(fixture.status()?.acknowledged == [1, 2, 3])
    }

    @Test func acknowledgingPutsAnOpenSessionToWorkAndDropsItsMessage() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }

        try SessionInbox.writeStatus(SessionStatus(state: .received), id: fixture.id, in: fixture.output)
        try SessionInbox.acknowledge([2], id: fixture.id, in: fixture.output)
        #expect(fixture.status()?.state == .working)

        // The pin is newer than the agent's last note, so the device names the pin instead
        try SessionInbox.writeStatus(SessionStatus(state: .working, message: "Editing HomeView"), id: fixture.id, in: fixture.output)
        try SessionInbox.acknowledge([3], id: fixture.id, in: fixture.output)
        let status = try #require(fixture.status())
        #expect(status.state == .working)
        #expect(status.message == nil)
    }

    @Test func aFinishedSessionKeepsItsStateAndMessage() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }

        try SessionInbox.writeStatus(SessionStatus(state: .done, message: "All set"), id: fixture.id, in: fixture.output)
        try SessionInbox.acknowledge([2], id: fixture.id, in: fixture.output)

        let status = try #require(fixture.status())
        #expect(status.state == .done)
        #expect(status.message == "All set")
        #expect(status.acknowledged == [2])
    }

    @Test func acknowledgingWithNoStatusYetStartsWorking() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }

        let returned = try SessionInbox.acknowledge([1], id: fixture.id, in: fixture.output)
        #expect(returned.state == .working)
        #expect(fixture.status()?.acknowledged == [1])
    }

    @Test func statusAndPinReportsKeepTheAcknowledgedPins() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }

        try SessionInbox.acknowledge([2], id: fixture.id, in: fixture.output)
        try SessionInbox.writeStatus(SessionStatus(state: .working, message: "Reinstalling"), id: fixture.id, in: fixture.output)
        #expect(fixture.status()?.acknowledged == [2])
        try SessionInbox.updatePin(PinStatus(index: 2, state: .resolved), id: fixture.id, in: fixture.output)
        #expect(fixture.status()?.acknowledged == [2])
        try SessionInbox.ask("Which gap?", pin: 3, id: fixture.id, in: fixture.output)
        #expect(fixture.status()?.acknowledged == [2])
    }

    @Test func aStatusWrittenBeforeAcknowledgementsDecodes() throws {
        let fixture = try ThreadFixture()
        defer { fixture.cleanUp() }
        try fixture.writeRawStatus(#"{"state": "working", "message": "Editing", "updatedAt": "2026-10-28T14:15:00Z"}"#)

        let status = try #require(fixture.status())
        #expect(status.acknowledged == nil)
        #expect(status.message == "Editing")
    }
}

// MARK: - The stage the device narrates

@Suite struct ActivePinStageTests {
    private static func status(_ state: SessionStatus.State, message: String? = nil, acknowledged: [Int]?) -> SessionStatus {
        SessionStatus(state: state, message: message, updatedAt: ThreadFixture.t0, acknowledged: acknowledged)
    }

    @Test func aWorkingSessionWithoutAMessageNamesThePinTheAgentIsOn() {
        let stage = DeliveryStage.resolve(status: Self.status(.working, acknowledged: [1, 3]), pins: [])
        #expect(stage == .working(message: "Working on note 3"))
    }

    @Test("the agent's own note wins; a blank one doesn't count", arguments: [
        ("Editing HomeView", "Editing HomeView"),
        ("  ", "Working on note 2")
    ])
    func theAgentsMessageWins(message: String, expected: String) {
        let stage = DeliveryStage.resolve(status: Self.status(.working, message: message, acknowledged: [2]), pins: [])
        #expect(stage == .working(message: expected))
    }

    @Test func settledPinsArentTheActiveOne() {
        let pins = [
            PinStatus(index: 3, state: .resolved),
            PinStatus(index: 2, state: .dismissed)
        ]
        let status = Self.status(.working, acknowledged: [1, 2, 3])
        #expect(DeliveryStage.activePin(status: status, pins: pins) == 1)
        #expect(DeliveryStage.resolve(status: status, pins: pins) == .working(message: "Working on note 1"))

        let allSettled = pins + [PinStatus(index: 1, state: .resolved)]
        #expect(DeliveryStage.activePin(status: status, pins: allSettled) == nil)
        #expect(DeliveryStage.resolve(status: status, pins: allSettled) == .working(message: nil))
    }

    @Test func anAnsweredPinStaysActive() {
        let pins = [PinStatus(index: 2, state: .answered, note: "Which blue?", reply: "Brand")]
        #expect(DeliveryStage.activePin(status: Self.status(.working, acknowledged: [2]), pins: pins) == 2)
    }

    @Test func anOpenQuestionWinsOverTheActivePin() {
        let pins = [PinStatus(index: 2, state: .question, note: "Which blue?")]
        #expect(DeliveryStage.resolve(status: Self.status(.working, acknowledged: [1]), pins: pins) == .question(pin: 2))
    }

    @Test func otherStatesIgnoreAcknowledgedPins() {
        #expect(DeliveryStage.resolve(status: Self.status(.done, acknowledged: [1]), pins: []) == .done(message: nil))
        #expect(DeliveryStage.resolve(status: Self.status(.received, acknowledged: [1]), pins: []) == .received)
        #expect(DeliveryStage.resolve(status: Self.status(.working, acknowledged: nil), pins: []) == .working(message: nil))
    }
}

// MARK: - What the app shows per pin

@Suite struct PinThreadResultTests {
    private static let pins = [Fixtures.element, Fixtures.copyEdit, Fixtures.spot]

    @Test func anAcknowledgedPinWithoutAReportIsWorking() {
        let results = PinResult.results(for: Self.pins, statuses: [PinStatus(index: 2, state: .resolved)], acknowledged: [1, 2])
        #expect(results.map(\.outcome) == [.working, .resolved(summary: nil), .open])

        let working = PinOutcome.working
        #expect(working.label == "Working")
        #expect(working.symbol == nil)
        #expect(working.tone == .neutral)
        #expect(working.detail == nil)
        #expect(NoteFilter.of(working, delivery: nil) == .inProgress)
    }

    @Test func summaryCountsWorkingPinsBeforeWaitingOnes() {
        let results = PinResult.results(for: Self.pins, statuses: [PinStatus(index: 2, state: .resolved)], acknowledged: [1])
        #expect(PinResult.summary(results) == "1 resolved · 1 working · 1 waiting")
    }

    @Test func resultsCarryEachPinsThread() {
        let thread = [agent("Which blue?", 0), human("The brand one", 10)]
        let statuses = [PinStatus(index: 1, state: .answered, note: "Which blue?", reply: "The brand one", thread: thread)]
        let results = PinResult.results(for: Self.pins, statuses: statuses)
        #expect(results[0].thread == thread)
        #expect(results[1].thread.isEmpty)
    }

    @Test func earlierMessagesLeaveOutWhatTheRowAlreadyShows() {
        let thread = [agent("Which blue?", 0), human("The brand one", 10), agent("Lighter or darker?", 20)]

        func result(_ outcome: PinOutcome, _ thread: [PinMessage]) -> PinResult {
            PinResult(index: 1, comment: "", subject: "Spot", intent: .fix, outcome: outcome, thread: thread)
        }
        // The open question is the row's detail
        #expect(result(.question("Lighter or darker?"), thread).earlierMessages == Array(thread.prefix(2)))
        // So is the reply that answered it
        let answered = Array(thread.prefix(2))
        #expect(result(.answered(question: "Which blue?", reply: "The brand one"), answered).earlierMessages == [thread[0]])
        // A resolved pin's detail is its summary, so the whole exchange shows
        #expect(result(.resolved(summary: "Used the brand blue"), answered).earlierMessages == answered)
        #expect(result(.open, []).earlierMessages.isEmpty)
    }

    @Test("once the agent acknowledges pins, an open pin it hasn't reached shows its number", arguments: [
        (PinOutcome.open, true, SentPinMark.number),
        (PinOutcome.open, false, SentPinMark.progress),
        (PinOutcome.working, true, SentPinMark.progress),
        (PinOutcome.answered(question: "Which blue?", reply: "Brand"), true, SentPinMark.progress),
        (PinOutcome.resolved(summary: nil), true, SentPinMark.symbol("checkmark", .success))
    ])
    func sentPinMark(outcome: PinOutcome, acknowledgesPins: Bool, expected: SentPinMark) {
        #expect(SentPinMark.resolve(outcome: outcome, delivery: .working(message: nil), acknowledgesPins: acknowledgesPins) == expected)
    }

    @Test func aWorkingPinStopsSpinningOnceNothingIsInFlight() {
        #expect(SentPinMark.resolve(outcome: .working, delivery: .done(message: nil), acknowledgesPins: true) == .number)
        #expect(SentPinMark.resolve(outcome: .working, delivery: nil, acknowledgesPins: true) == .number)
    }

    @Test func threadLinesNameTheSpeaker() {
        #expect(OverlayChrome.threadLine(agent("Which blue?", 0), agent: "Claude Code") == "Claude: Which blue?")
        #expect(OverlayChrome.threadLine(human("The brand one", 0), agent: "Claude Code") == "You: The brand one")
        #expect(OverlayChrome.threadLine(agent("Which blue?", 0), agent: "") == "Agent: Which blue?")
        #expect(DeliveryStage.workingMessage(pin: 2) == "Working on note 2")
    }
}
