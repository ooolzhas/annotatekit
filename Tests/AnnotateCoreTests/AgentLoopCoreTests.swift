// Agent loop, AnnotateCore side: per-pin status and replies on disk (SessionInbox.updatePin,
// appendReply / readReplies, unansweredReplies, markAnswered), the prompt's intent tags, legend,
// reporting paragraph and detail levels (PromptRenderer), the reply and results chrome
// (OverlayChrome), the agent's open question as a delivery stage (ReviewHint / LauncherStatus /
// DeliveryStage), and AnnotationIntent's schema and rules.
// Pins rules and shapes; exact copy is pinned only for the contract's short constants.
// Dates are whole seconds because status.json and replies.json encode ISO 8601 without fractions.

@testable import AnnotateCore
import Foundation
import Testing

/// A throwaway `.annotate` directory holding one written session, removed by the caller.
private struct InboxFixture {
    let output: URL
    let id: String

    /// Whole-second base time, so values survive the ISO 8601 round trip unchanged.
    static let t0 = Date(timeIntervalSince1970: 1_793_196_900)

    init() throws {
        output = FileManager.default.temporaryDirectory
            .appendingPathComponent("annotate-agentloop-\(UUID().uuidString)", isDirectory: true)
        let session = Fixtures.session(annotations: [Fixtures.element, Fixtures.copyEdit, Fixtures.spot])
        id = session.id
        try SessionWriter.write(SessionBundle(session: session, images: [:]), prompt: "prompt\n", to: output)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: output)
    }

    var statusURL: URL {
        SessionInbox.sessionDirectory(id, in: output).appendingPathComponent(SessionInbox.statusFile)
    }

    var repliesURL: URL {
        SessionInbox.sessionDirectory(id, in: output).appendingPathComponent(SessionInbox.repliesFile)
    }

    static func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }
}

// MARK: - SessionInbox: per-pin status and replies

@Suite struct AgentLoopCoreInboxTests {
    @Test func updatePinWithoutStatusStartsWorking() throws {
        let fixture = try InboxFixture()
        defer { fixture.cleanUp() }
        #expect(SessionInbox.readStatus(id: fixture.id, in: fixture.output) == nil)

        let pin = PinStatus(index: 2, state: .resolved, note: "Tightened the copy", updatedAt: InboxFixture.at(0))
        let returned = try SessionInbox.updatePin(pin, id: fixture.id, in: fixture.output)

        #expect(returned.state == .working)
        #expect(returned.pins == [pin])
        let stored = try #require(SessionInbox.readStatus(id: fixture.id, in: fixture.output))
        #expect(stored.state == .working)
        #expect(stored.pins == [pin])
    }

    @Test func updatePinUpsertsByIndexAndKeepsSessionStateAndMessage() throws {
        let fixture = try InboxFixture()
        defer { fixture.cleanUp() }
        try SessionInbox.writeStatus(SessionStatus(state: .received, message: "Opened it"), id: fixture.id, in: fixture.output)

        let third = PinStatus(index: 3, state: .resolved, note: "Removed the gap", updatedAt: InboxFixture.at(1))
        let first = PinStatus(index: 1, state: .dismissed, note: "Matches the spec", updatedAt: InboxFixture.at(2))
        let thirdAgain = PinStatus(index: 3, state: .question, note: "Which gap?", updatedAt: InboxFixture.at(3))
        try SessionInbox.updatePin(third, id: fixture.id, in: fixture.output)
        try SessionInbox.updatePin(first, id: fixture.id, in: fixture.output)
        let returned = try SessionInbox.updatePin(thirdAgain, id: fixture.id, in: fixture.output)

        let stored = try #require(SessionInbox.readStatus(id: fixture.id, in: fixture.output))
        #expect(stored.state == .received)
        #expect(stored.message == "Opened it")
        // One entry per index (the second report for pin 3 replaced the first), in index order
        #expect(stored.pins == [first, thirdAgain])
        #expect(returned.pins == stored.pins)
        #expect(returned.state == stored.state)
        #expect(returned.message == stored.message)
    }

    @Test func legacyStatusWithoutPinsDecodes() throws {
        let fixture = try InboxFixture()
        defer { fixture.cleanUp() }
        let legacy = #"{"message":"Edited HomeView.swift","state":"done","updatedAt":"2026-10-28T14:15:02Z"}"#
        try Data(legacy.utf8).write(to: fixture.statusURL)

        let status = try #require(SessionInbox.readStatus(id: fixture.id, in: fixture.output))
        #expect(status.state == .done)
        #expect(status.message == "Edited HomeView.swift")
        #expect(status.pins == nil)

        // A pin report on a legacy status keeps its state and message
        let pin = PinStatus(index: 1, state: .resolved, updatedAt: InboxFixture.at(0))
        try SessionInbox.updatePin(pin, id: fixture.id, in: fixture.output)
        let updated = try #require(SessionInbox.readStatus(id: fixture.id, in: fixture.output))
        #expect(updated.state == .done)
        #expect(updated.message == "Edited HomeView.swift")
        #expect(updated.pins == [pin])
    }

    @Test func repliesRoundTripInFileOrder() throws {
        let fixture = try InboxFixture()
        defer { fixture.cleanUp() }
        #expect(SessionInbox.readReplies(id: fixture.id, in: fixture.output).isEmpty)

        let first = PinReply(index: 2, text: "Blue, like the header", at: InboxFixture.at(10))
        let second = PinReply(index: 1, text: "Yes", at: InboxFixture.at(5))
        try SessionInbox.appendReply(first, id: fixture.id, in: fixture.output)
        try SessionInbox.appendReply(second, id: fixture.id, in: fixture.output)

        // Append-only: file order, not time order
        #expect(SessionInbox.readReplies(id: fixture.id, in: fixture.output) == [first, second])
    }

    @Test func unreadableRepliesReadAsEmpty() throws {
        let fixture = try InboxFixture()
        defer { fixture.cleanUp() }
        try Data("not json".utf8).write(to: fixture.repliesURL)
        #expect(SessionInbox.readReplies(id: fixture.id, in: fixture.output).isEmpty)
    }

    @Test func unansweredRepliesWithoutStatusIsEmpty() throws {
        let fixture = try InboxFixture()
        defer { fixture.cleanUp() }
        try SessionInbox.appendReply(PinReply(index: 1, text: "Hi", at: InboxFixture.at(0)), id: fixture.id, in: fixture.output)
        #expect(SessionInbox.unansweredReplies(id: fixture.id, in: fixture.output).isEmpty)
    }

    @Test func unansweredRepliesKeepOnlyFreshRepliesToOpenQuestions() throws {
        let fixture = try InboxFixture()
        defer { fixture.cleanUp() }
        let (id, output) = (fixture.id, fixture.output)
        try SessionInbox.updatePin(PinStatus(index: 1, state: .question, note: "Bigger how?", updatedAt: InboxFixture.at(0)), id: id, in: output)
        try SessionInbox.updatePin(PinStatus(index: 2, state: .resolved, note: "Done", updatedAt: InboxFixture.at(0)), id: id, in: output)
        try SessionInbox.updatePin(PinStatus(index: 3, state: .question, note: "Remove it?", updatedAt: InboxFixture.at(100)), id: id, in: output)
        try SessionInbox.updatePin(
            PinStatus(index: 4, state: .answered, note: "Why?", reply: "Because", updatedAt: InboxFixture.at(0)), id: id, in: output
        )

        let toFirst = PinReply(index: 1, text: "Twice as big", at: InboxFixture.at(10))
        let toResolved = PinReply(index: 2, text: "Thanks", at: InboxFixture.at(20))
        let staleToThird = PinReply(index: 3, text: "Old answer", at: InboxFixture.at(50))
        let laterToFirst = PinReply(index: 1, text: "Actually 3x", at: InboxFixture.at(200))
        let toThird = PinReply(index: 3, text: "Yes, remove it", at: InboxFixture.at(150))
        let toAnswered = PinReply(index: 4, text: "Again", at: InboxFixture.at(30))
        let toUnknownPin = PinReply(index: 9, text: "Nobody asked", at: InboxFixture.at(40))
        for reply in [toFirst, toResolved, staleToThird, laterToFirst, toThird, toAnswered, toUnknownPin] {
            try SessionInbox.appendReply(reply, id: id, in: output)
        }

        // Only replies to `.question` pins, no older than the question, oldest first
        #expect(SessionInbox.unansweredReplies(id: id, in: output) == [toFirst, toThird, laterToFirst])
    }

    @Test func replyAtTheQuestionsOwnTimeCounts() throws {
        let fixture = try InboxFixture()
        defer { fixture.cleanUp() }
        try SessionInbox.updatePin(PinStatus(index: 1, state: .question, note: "?", updatedAt: InboxFixture.at(5)), id: fixture.id, in: fixture.output)
        let reply = PinReply(index: 1, text: "Same second", at: InboxFixture.at(5))
        try SessionInbox.appendReply(reply, id: fixture.id, in: fixture.output)
        #expect(SessionInbox.unansweredReplies(id: fixture.id, in: fixture.output) == [reply])
    }

    @Test func markAnsweredRecordsTheReplyAndDeliversItOnce() throws {
        let fixture = try InboxFixture()
        defer { fixture.cleanUp() }
        let (id, output) = (fixture.id, fixture.output)
        try SessionInbox.writeStatus(SessionStatus(state: .working, message: "On it"), id: id, in: output)
        let resolved = PinStatus(index: 1, state: .resolved, note: "Done", updatedAt: InboxFixture.at(0))
        try SessionInbox.updatePin(resolved, id: id, in: output)
        try SessionInbox.updatePin(PinStatus(index: 2, state: .question, note: "Which color?", updatedAt: InboxFixture.at(0)), id: id, in: output)
        let reply = PinReply(index: 2, text: "Blue", at: InboxFixture.at(5))
        try SessionInbox.appendReply(reply, id: id, in: output)
        #expect(SessionInbox.unansweredReplies(id: id, in: output) == [reply])

        try SessionInbox.markAnswered(reply, id: id, in: output)

        let status = try #require(SessionInbox.readStatus(id: id, in: output))
        let answered = try #require(status.pins?.first { $0.index == 2 })
        #expect(answered.state == .answered)
        #expect(answered.note == "Which color?")
        #expect(answered.reply == "Blue")
        #expect(status.pins?.first { $0.index == 1 } == resolved)
        #expect(status.state == .working)
        #expect(status.message == "On it")
        #expect(SessionInbox.unansweredReplies(id: id, in: output).isEmpty)
        // The reply itself stays in replies.json (append-only); only the pin's state moved on
        #expect(SessionInbox.readReplies(id: id, in: output) == [reply])
    }
}

// MARK: - PromptRenderer: intent tags, legend, reporting, detail levels

@Suite struct AgentLoopCorePromptTests {
    private static let path = "/Users/me/app/.annotate/sessions/20261028-141502-a1b2"

    private static func render(_ annotations: [Annotation], screens: [Screen] = [Fixtures.screen], detail: PromptDetail = .standard) -> String {
        PromptRenderer.render(Fixtures.session(annotations: annotations, screens: screens), sessionPath: path, detail: detail)
    }

    private static func lines(_ prompt: String) -> [String] {
        prompt.components(separatedBy: "\n")
    }

    private static func with(_ annotation: Annotation, intent: AnnotationIntent?) -> Annotation {
        var copy = annotation
        copy.intent = intent
        return copy
    }

    @Test func questionPinIsTaggedAfterItsNumberAndExplainedByTheLegend() throws {
        let prompt = Self.render([Self.with(Fixtures.element, intent: .question), Fixtures.spot])
        let lines = Self.lines(prompt)

        #expect(lines.contains { $0.hasPrefix("1. [Question] Button") })
        // An untagged pin reads as before
        #expect(lines.contains { $0.hasPrefix("3. Spot") })

        let coordinates = try #require(lines.firstIndex { $0.hasPrefix("Coordinates are") })
        let legend = lines[coordinates + 1]
        #expect(legend.hasPrefix("Tags:"))
        #expect(legend.contains("[Question]"))
        #expect(lines.filter { $0.hasPrefix("Tags:") }.count == 1)
    }

    @Test func legendNamesEachPresentTagOnce() throws {
        let prompt = Self.render([
            Self.with(Fixtures.element, intent: .question),
            Self.with(Fixtures.copyEdit, intent: .fix),
            Self.with(Fixtures.spot, intent: .question)
        ])
        let lines = Self.lines(prompt)
        #expect(lines.contains { $0.hasPrefix("1. [Question] Button") })
        #expect(lines.contains { $0.hasPrefix("2. Text") })
        #expect(lines.contains { $0.hasPrefix("3. [Question] Spot") })

        let legend = try #require(lines.first { $0.hasPrefix("Tags:") })
        #expect(legend.components(separatedBy: "[Question]").count == 2)
    }

    @Test("no non-fix intent means no tags and no legend",
          arguments: [nil, AnnotationIntent.fix])
    func noIntentsNoLegend(intent: AnnotationIntent?) {
        let prompt = Self.render([Self.with(Fixtures.element, intent: intent), Fixtures.spot])
        #expect(!prompt.contains("Tags:"))
        for tag in AnnotationIntent.allCases.compactMap(\.promptTag) {
            #expect(!prompt.contains(tag))
        }
    }

    @Test func reportingParagraphNamesTheSessionAndPrecedesFullDetail() throws {
        let session = Fixtures.session(annotations: [Fixtures.element])
        let prompt = PromptRenderer.render(session, sessionPath: Self.path, completion: "When you're done, report back.")
        let lines = Self.lines(prompt)

        let reporting = try #require(lines.firstIndex { $0.contains("annotate resolve \(session.id)") })
        let paragraph = lines[reporting]
        #expect(paragraph.contains("annotate dismiss \(session.id)"))
        #expect(paragraph.contains("annotate ask \(session.id)"))
        #expect(paragraph.contains("annotation_resolve"))
        #expect(paragraph.contains("annotation_dismiss"))
        #expect(paragraph.contains("annotation_ask"))

        let fullDetail = try #require(lines.firstIndex { $0.hasPrefix("Full detail") })
        let completion = try #require(lines.firstIndex { $0 == "When you're done, report back." })
        #expect(reporting < fullDetail)
        #expect(fullDetail < completion)
    }

    @Test func reportingParagraphUsesTheSessionIDEvenWithoutAPath() {
        let session = Fixtures.session(annotations: [Fixtures.element])
        let prompt = PromptRenderer.render(session, sessionPath: nil)
        #expect(prompt.contains("annotate resolve \(session.id)"))
    }

    @Test func standardIsTheDefaultAndKeepsNearbyText() {
        let annotations = [Fixtures.element, Fixtures.spot]
        let standard = Self.render(annotations, detail: .standard)
        #expect(PromptRenderer.render(Fixtures.session(annotations: annotations), sessionPath: Self.path) == standard)
        #expect(standard.contains("Nearby text: \"Light that follows your day\""))
        #expect(standard.contains("clean \(Self.path)/screens/1.png"))
        #expect(standard.contains("hi-res \(Self.path)/screens/1@3x.png"))
        #expect(!standard.contains("Visible text:"))
    }

    @Test func compactDropsNearbyTextAndExtraImagesButKeepsTheRest() {
        let compact = Self.render([Fixtures.element, Fixtures.region], detail: .compact)
        #expect(!compact.contains("Nearby text"))
        #expect(!compact.contains("\(Self.path)/screens/1.png"))
        #expect(!compact.contains("1@3x.png"))
        #expect(!compact.contains("Visible text:"))
        // Annotated image, crops, source and comments survive
        #expect(compact.contains("annotated \(Self.path)/screens/1-annotated.png"))
        #expect(compact.contains("Crop: \(Self.path)/crops/1.png"))
        #expect(compact.contains("Crop: \(Self.path)/crops/4.png"))
        #expect(compact.contains("Source: inside `HeroCard` at App/HomeView.swift:42"))
        #expect(compact.contains("bigger, tighter"))
        #expect(compact.contains("add a signup card here"))
        #expect(compact.contains("annotate resolve"))
    }

    @Test func detailedAddsVisibleTextAfterTheScreenHeader() throws {
        let detailed = Self.render([Fixtures.element], detail: .detailed)
        let lines = Self.lines(detailed)
        let header = try #require(lines.firstIndex { $0.hasPrefix("Screen 1 (") })
        let visible = lines[header + 1]
        #expect(visible.hasPrefix("Visible text: "))
        #expect(visible.contains("\"Get started\" (24, 300, 120×44)"))
        // Detailed is a superset of standard: nearby text stays
        #expect(detailed.contains("Nearby text:"))
    }

    @Test func detailedVisibleTextSkipsBlanksAndIsCapped() throws {
        let blank = ScreenElement(role: "view", label: "  ", frame: AnnotationRect(x: 0, y: 0, width: 10, height: 10))
        let labelled = (0..<(PromptRenderer.visibleTextLimit + 5)).map { n in
            ScreenElement(role: "text", label: "E\(n)", frame: AnnotationRect(x: 0, y: Double(n), width: 10, height: 10))
        }
        var screen = Fixtures.screen
        screen.elements = [blank] + labelled

        let detailed = Self.render([Fixtures.element], screens: [screen], detail: .detailed)
        let visible = try #require(Self.lines(detailed).first { $0.hasPrefix("Visible text: ") })
        #expect(visible.hasPrefix("Visible text: \"E0\""))
        #expect(visible.components(separatedBy: "\"E").count - 1 == PromptRenderer.visibleTextLimit)
        #expect(visible.contains("\"E\(PromptRenderer.visibleTextLimit - 1)\""))
        #expect(!visible.contains("\"E\(PromptRenderer.visibleTextLimit)\""))
        #expect(PromptRenderer.visibleTextLimit == 40)
    }

    @Test func detailedWithNoVisibleTextAddsNoLine() {
        var screen = Fixtures.screen
        screen.elements = []
        let detailed = Self.render([Fixtures.element], screens: [screen], detail: .detailed)
        #expect(!detailed.contains("Visible text:"))
    }
}

// MARK: - OverlayChrome: replying and results

@Suite struct AgentLoopCoreChromeTests {
    private static func inputs(
        open: Bool = false,
        comment: String = "",
        pins: Int = 2,
        reply: String? = nil,
        showingResults: Bool = false,
        results: Int = 0
    ) -> OverlayChrome.Inputs {
        OverlayChrome.Inputs(
            isDraftOpen: open, draftComment: comment, pinCount: pins,
            replyText: reply, isShowingResults: showingResults, resultCount: results
        )
    }

    @Test("a reply in progress wins over a draft and the results card; blank can't submit",
          arguments: ["", " ", "\n\t "])
    func blankReplyCannotSubmit(reply: String) {
        #expect(OverlayChrome.resolve(Self.inputs(reply: reply)) == .replying(canSubmit: false))
        #expect(OverlayChrome.resolve(Self.inputs(open: true, comment: "typed", reply: reply, showingResults: true, results: 3))
                == .replying(canSubmit: false))
    }

    @Test func typedReplyCanSubmit() {
        #expect(OverlayChrome.resolve(Self.inputs(reply: "  Blue  ")) == .replying(canSubmit: true))
        #expect(OverlayChrome.resolve(Self.inputs(open: true, reply: "Blue", showingResults: true, results: 3))
                == .replying(canSubmit: true))
    }

    @Test func openDraftWinsOverResults() {
        #expect(OverlayChrome.resolve(Self.inputs(open: true, comment: "fix it", showingResults: true, results: 3))
                == .composing(canSubmit: true))
        #expect(OverlayChrome.resolve(Self.inputs(open: true, showingResults: true, results: 3))
                == .composing(canSubmit: false))
    }

    @Test("an open pin needs a comment; whitespace isn't one",
          arguments: ["", " ", "  \n"])
    func blankCommentCannotSubmit(comment: String) {
        #expect(OverlayChrome.resolve(Self.inputs(open: true, comment: comment)) == .composing(canSubmit: false))
        #expect(OverlayChrome.resolve(Self.inputs(open: true, comment: comment + "x")) == .composing(canSubmit: true))
    }

    @Test func resultsShowOnlyWhileOpenAndNonEmpty() {
        #expect(OverlayChrome.resolve(Self.inputs(pins: 0, showingResults: true, results: 3)) == .results(count: 3))
        #expect(OverlayChrome.resolve(Self.inputs(pins: 2, showingResults: true, results: 0)) == .review(count: 2))
        #expect(OverlayChrome.resolve(Self.inputs(pins: 2, showingResults: false, results: 3)) == .review(count: 2))
    }

    @Test("Send is live only on the review bar with pins",
          arguments: [
            (OverlayChrome.replying(canSubmit: true), false),
            (.replying(canSubmit: false), false),
            (.results(count: 3), false),
            (.results(count: 0), false),
            (.composing(canSubmit: true), false),
            (.review(count: 0), false),
            (.review(count: 1), true)
          ])
    func canSend(chrome: OverlayChrome, expected: Bool) {
        #expect(chrome.canSend == expected)
    }

    @Test func resultsTitleCountsNotes() {
        let one = OverlayChrome.resultsTitle(1)
        let three = OverlayChrome.resultsTitle(3)
        #expect(one == "Last Send · 1 note")
        #expect(three == "Last Send · 3 notes")
        #expect(one.contains("1") && !one.hasSuffix("notes"))
        #expect(three.contains("3") && three.hasSuffix("notes"))
    }

    @Test func replyCopyConstants() {
        #expect(OverlayChrome.replyPlaceholder == "Reply")
        #expect(OverlayChrome.replyAction == "Reply")
        #expect(OverlayChrome.replySentToast == "Reply sent")
    }

    @Test func askedTitleUsesTheDisplayNameAndPin() {
        #expect(OverlayChrome.askedTitle(agent: "Claude Code", pin: 2) == "Claude asks about note 2")
        let blank = OverlayChrome.askedTitle(agent: "  ", pin: 5)
        #expect(blank.hasPrefix(ReviewHint.displayName("")))
        #expect(blank.contains("5"))
    }
}

// MARK: - ReviewHint / LauncherStatus / DeliveryStage: the agent's open question

@Suite struct AgentLoopCoreQuestionHintTests {
    private static let presence = AgentPresence(
        agent: "Claude Code", mode: .push, via: "mcp", project: nil, updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )

    private static let otherStages: [DeliveryStage] = [
        .sent(count: 2), .unclaimed, .delivered, .received, .working(message: nil),
        .done(message: nil), .failed(message: nil), .notSaved, .noAgent
    ]

    @Test func questionStageResolvesToADeliveryHint() {
        let hint = ReviewHint.resolve(ReviewHint.Inputs(agent: Self.presence, isIntro: true, delivery: .question(pin: 2)))
        guard case .delivery(.question(pin: 2), let agent) = hint else {
            Issue.record("expected .delivery(.question(pin: 2), …), got \(hint)")
            return
        }
        #expect(agent == ReviewHint.displayName("Claude Code"))

        let noAgent = ReviewHint.resolve(ReviewHint.Inputs(agent: nil, isIntro: false, delivery: .question(pin: 2)))
        #expect(noAgent == .delivery(.question(pin: 2), agent: ReviewHint.displayName("")))
    }

    @Test func questionHintNeedsAttentionAndKeepsCounting() {
        let hint = ReviewHint.delivery(.question(pin: 2), agent: "Claude Code")
        #expect(hint.dot == .attention)
        #expect(hint.showsElapsed)
        #expect(hint.text.contains("2"))
        #expect(hint.text.contains(ReviewHint.displayName("Claude Code")))
        #expect(!hint.text.contains("Claude Code"))
        // Not `.noAgent`, so the bar keeps reading Send
        #expect(hint.actionTitle == OverlayChrome.sendTitle)
    }

    @Test("no other delivery stage uses the attention dot", arguments: otherStages)
    func attentionIsReservedForQuestions(stage: DeliveryStage) {
        #expect(ReviewHint.delivery(stage, agent: "Claude").dot != .attention)
    }

    @Test func launcherTitleNamesThePin() {
        let title = LauncherStatus.delivery(.question(pin: 3)).title
        #expect(title.contains("3"))
        #expect(title == "Question on note 3")
        #expect(LauncherStatus.resolve(LauncherStatus.Inputs(delivery: .question(pin: 3), pendingCount: 4)) == .delivery(.question(pin: 3)))
    }

    @Test(arguments: [1, 2, 7])
    func questionIsNotFinal(pin: Int) {
        #expect(!DeliveryStage.question(pin: pin).isFinal)
    }
}

// MARK: - AnnotationIntent

@Suite struct AgentLoopCoreIntentTests {
    @Test func annotationWithoutIntentDecodesAsNil() throws {
        var legacy = Fixtures.element
        legacy.intent = nil
        let data = try AnnotationSession.encoder.encode(legacy)
        let json = String(decoding: data, as: UTF8.self)
        // A nil intent is omitted, so the JSON matches what older builds wrote
        #expect(!json.contains("\"intent\""))

        let decoded = try AnnotationSession.decoder.decode(Annotation.self, from: data)
        #expect(decoded.intent == nil)
        #expect(decoded == legacy)
    }

    @Test func annotationRoundTripsWithQuestionIntent() throws {
        var asked = Fixtures.region
        asked.intent = .question
        let data = try AnnotationSession.encoder.encode(asked)
        #expect(String(decoding: data, as: UTF8.self).contains("\"intent\" : \"question\""))
        let decoded = try AnnotationSession.decoder.decode(Annotation.self, from: data)
        #expect(decoded.intent == .question)
        #expect(decoded == asked)
    }

    @Test func sessionWithIntentsRoundTripsAndStaysSchemaOne() throws {
        var question = Fixtures.element
        question.intent = .question
        let session = Fixtures.session(annotations: [question, Fixtures.spot])
        let decoded = try AnnotationSession.decoder.decode(AnnotationSession.self, from: AnnotationSession.encoder.encode(session))
        #expect(decoded == session)
        #expect(decoded.schemaVersion == 1)
        #expect(AnnotationSession.currentSchemaVersion == 1)
    }

    @Test func rawValuesAreTheSchemaStrings() {
        #expect(AnnotationIntent.allCases.map(\.rawValue) == ["fix", "question"])
    }

    @Test("an intent this version doesn't know (the removed approve and move) loads as fix",
          arguments: ["approve", "move", "somethingNew"])
    func unknownIntentDecodesAsFix(raw: String) throws {
        let data = Data("[\"\(raw)\", \"question\"]".utf8)
        #expect(try JSONDecoder().decode([AnnotationIntent].self, from: data) == [.fix, .question])
    }

    @Test func onlyFixHasNoPromptTag() {
        #expect(AnnotationIntent.allCases.filter { $0.promptTag == nil } == [.fix])
        #expect(AnnotationIntent.question.promptTag == "[Question]")
    }

    @Test func fixKeepsTheOverlayPlaceholder() {
        #expect(AnnotationIntent.fix.placeholder == OverlayChrome.placeholder)
        // Every intent has its own non-empty copy
        let placeholders = AnnotationIntent.allCases.map(\.placeholder)
        #expect(Set(placeholders).count == AnnotationIntent.allCases.count)
        #expect(!AnnotationIntent.allCases.contains { $0.title.isEmpty || $0.detail.isEmpty || $0.symbol.isEmpty })
    }
}

@Suite struct AgentLoopCoreStatusKeepsPinsTests {
    @Test func aSessionLevelStatusKeepsPerPinResults() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("annotate-keep-pins-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }
        let session = AnnotationSession(
            id: "20261029-010203-keep", createdAt: Date(), app: AppInfo(),
            device: DeviceInfo(model: "iPhone", systemName: "iOS", systemVersion: "26.0", isSimulator: true,
                               screen: AnnotationSize(width: 402, height: 874), scale: 3, colorScheme: "light",
                               contentSize: "L", orientation: "portrait"),
            screens: [], annotations: []
        )
        try SessionWriter.write(SessionBundle(session: session, images: [:]), prompt: "p", to: output)
        try SessionInbox.updatePin(PinStatus(index: 1, state: .resolved, note: "Edited X"), id: session.id, in: output)

        // What `annotate status`, annotation_status and "received" write: no pins of their own
        try SessionInbox.writeStatus(SessionStatus(state: .working, message: "Rebuilding"), id: session.id, in: output)

        let status = try #require(SessionInbox.readStatus(id: session.id, in: output))
        #expect(status.state == .working)
        #expect(status.message == "Rebuilding")
        #expect(status.pins?.map(\.state) == [.resolved])
    }
}
