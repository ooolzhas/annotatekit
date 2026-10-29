// PinOutcome / PinResult: how the agent's PinStatus becomes the results card's outcome, badge tone
// and glyph, and the rules behind the per-pin rows and the card's one-line summary.

@testable import AnnotateCore
import Foundation
import Testing

@Suite struct PinOutcomeTests {
    /// Fixed timestamp so no fixture reads the wall clock; `updatedAt` plays no part in the outcome.
    private static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    private static func status(
        _ index: Int, _ state: PinStatus.State, note: String? = nil, reply: String? = nil
    ) -> PinStatus {
        PinStatus(index: index, state: state, note: note, reply: reply, updatedAt: fixedDate)
    }

    private static func pin(
        _ index: Int,
        kind: Annotation.Kind = .point,
        comment: String = "c",
        intent: AnnotationIntent? = .fix
    ) -> Annotation {
        Annotation(
            index: index,
            kind: kind,
            comment: comment,
            frame: AnnotationRect(x: 0, y: 0, width: 10, height: 10),
            intent: intent
        )
    }

    private static func result(_ index: Int, _ outcome: PinOutcome) -> PinResult {
        PinResult(index: index, comment: "", subject: "Spot", intent: .fix, outcome: outcome)
    }

    // MARK: PinOutcome.resolve

    @Test("no status resolves to open")
    func nilIsOpen() {
        #expect(PinOutcome.resolve(nil) == .open)
    }

    @Test("resolved and dismissed carry the trimmed note; blank becomes nil",
          arguments: [
              (PinStatus.State.resolved, "  changed padding \n" as String?, "changed padding" as String?),
              (.resolved, "   \n", nil),
              (.resolved, nil, nil),
              (.dismissed, "\tout of scope ", "out of scope"),
              (.dismissed, "", nil),
              (.dismissed, nil, nil)
          ])
    func resolvedDismissedNote(state: PinStatus.State, note: String?, expected: String?) {
        let outcome = PinOutcome.resolve(Self.status(1, state, note: note))
        switch state {
        case .resolved: #expect(outcome == .resolved(summary: expected))
        default: #expect(outcome == .dismissed(reason: expected))
        }
    }

    @Test("a question with no text is still a question, with empty text",
          arguments: [nil, "", "  \n "] as [String?])
    func blankQuestion(note: String?) {
        #expect(PinOutcome.resolve(Self.status(1, .question, note: note)) == .question(""))
    }

    @Test("a question's text is trimmed")
    func questionTrimmed() {
        #expect(PinOutcome.resolve(Self.status(1, .question, note: " Which color? ")) == .question("Which color?"))
    }

    @Test("answered carries the question from note and the reply, both trimmed")
    func answeredCarriesBoth() {
        let outcome = PinOutcome.resolve(Self.status(1, .answered, note: " Which color? ", reply: "\nBlue "))
        #expect(outcome == .answered(question: "Which color?", reply: "Blue"))
    }

    @Test("answered with blank question and reply: question nil, reply empty")
    func answeredBlank() {
        let outcome = PinOutcome.resolve(Self.status(1, .answered, note: "  ", reply: nil))
        #expect(outcome == .answered(question: nil, reply: ""))
    }

    // MARK: isQuestion / tone / symbol

    static let allOutcomes: [PinOutcome] = [
        .open,
        .resolved(summary: "s"),
        .dismissed(reason: nil),
        .question("q"),
        .answered(question: "q", reply: "r")
    ]

    @Test("isQuestion is true only for .question", arguments: allOutcomes)
    func isQuestion(outcome: PinOutcome) {
        let expected = if case .question = outcome { true } else { false }
        #expect(outcome.isQuestion == expected)
    }

    @Test("tone per case",
          arguments: zip(allOutcomes, [
              PinOutcome.Tone.neutral, .success, .muted, .attention, .neutral
          ]))
    func tone(outcome: PinOutcome, expected: PinOutcome.Tone) {
        #expect(outcome.tone == expected)
    }

    @Test("open and answered show the pin number (nil glyph); the rest show a glyph",
          arguments: zip(allOutcomes, [
              nil, "checkmark", "xmark", "questionmark", nil
          ] as [String?]))
    func symbol(outcome: PinOutcome, expected: String?) {
        #expect(outcome.symbol == expected)
    }

    // MARK: PinResult.results

    @Test("one result per pin, sorted by index, statuses matched by index")
    func resultsSortedAndMatched() {
        let pins = [Self.pin(3), Self.pin(1), Self.pin(2)]
        let statuses = [Self.status(3, .dismissed, note: "no"), Self.status(1, .resolved, note: "done")]
        let results = PinResult.results(for: pins, statuses: statuses)

        #expect(results.map(\.index) == [1, 2, 3])
        #expect(results.map(\.outcome) == [.resolved(summary: "done"), .open, .dismissed(reason: "no")])
    }

    @Test("a status for an index with no pin produces no row")
    func orphanStatusIgnored() {
        let results = PinResult.results(for: [Self.pin(1)], statuses: [Self.status(9, .resolved)])
        #expect(results.map(\.index) == [1])
        #expect(results.first?.outcome == .open)
    }

    @Test("duplicate statuses for one index: the later entry wins")
    func duplicateStatusLaterWins() {
        let statuses = [Self.status(1, .resolved, note: "first"), Self.status(1, .dismissed, note: "second")]
        let results = PinResult.results(for: [Self.pin(1)], statuses: statuses)
        #expect(results.first?.outcome == .dismissed(reason: "second"))
    }

    @Test("no pins gives no results, even with statuses")
    func noPins() {
        #expect(PinResult.results(for: [], statuses: [Self.status(1, .resolved)]).isEmpty)
    }

    @Test("a nil intent becomes .fix; a set intent is kept",
          arguments: [
              (nil, AnnotationIntent.fix), (.question, .question), (.move, .move)
          ] as [(AnnotationIntent?, AnnotationIntent)])
    func intentDefault(intent: AnnotationIntent?, expected: AnnotationIntent) {
        let results = PinResult.results(for: [Self.pin(1, intent: intent)], statuses: [])
        #expect(results.first?.intent == expected)
    }

    @Test("subject names the pin kind; an element pin without element info reads Element",
          arguments: [
              (Annotation.Kind.point, "Spot"),
              (.region, "Region"),
              (.sketch, "Sketch"),
              (.element, "Element")
          ])
    func subject(kind: Annotation.Kind, expected: String) {
        let results = PinResult.results(for: [Self.pin(1, kind: kind)], statuses: [])
        #expect(results.first?.subject == expected)
    }

    @Test("comments are trimmed")
    func commentTrimmed() {
        let results = PinResult.results(for: [Self.pin(1, comment: "  make it bigger \n")], statuses: [])
        #expect(results.first?.comment == "make it bigger")
    }

    // MARK: PinResult.summary

    @Test("nil for no results and when every pin is open",
          arguments: [[], [PinOutcome.open], [.open, .open, .open]])
    func summaryNil(outcomes: [PinOutcome]) {
        let results = outcomes.enumerated().map { Self.result($0.offset + 1, $0.element) }
        #expect(PinResult.summary(results) == nil)
    }

    @Test("only nonzero counts appear, in order resolved, dismissed, question, answered, waiting")
    func summaryOrder() throws {
        // Deliberately shuffled input order so ordering must come from the rule, not the array
        let results = [
            Self.result(1, .open),
            Self.result(2, .answered(question: nil, reply: "r")),
            Self.result(3, .question("q")),
            Self.result(4, .dismissed(reason: nil)),
            Self.result(5, .resolved(summary: nil)),
            Self.result(6, .resolved(summary: "x"))
        ]
        let summary = try #require(PinResult.summary(results))
        let parts = ["2 resolved", "1 dismissed", "1 question", "1 answered", "1 waiting"]
        let positions = try parts.map { part in
            try #require(summary.range(of: part), "missing \(part) in \(summary)").lowerBound
        }
        #expect(positions == positions.sorted())
    }

    @Test("zero counts are omitted")
    func summaryOmitsZero() throws {
        let results = [Self.result(1, .resolved(summary: nil)), Self.result(2, .resolved(summary: nil))]
        let summary = try #require(PinResult.summary(results))
        #expect(summary.contains("2 resolved"))
        for absent in ["dismissed", "question", "answered", "waiting"] {
            #expect(!summary.contains(absent))
        }
    }

    @Test("waiting is reported for open pins once another pin has an outcome")
    func summaryWaitingAlongsideOthers() throws {
        let results = [Self.result(1, .dismissed(reason: nil)), Self.result(2, .open), Self.result(3, .open)]
        let summary = try #require(PinResult.summary(results))
        #expect(summary.contains("2 waiting"))
        let dismissed = try #require(summary.range(of: "1 dismissed"))
        let waiting = try #require(summary.range(of: "2 waiting"))
        #expect(dismissed.lowerBound < waiting.lowerBound)
    }

    @Test("question count is singular for 1 and plural above", arguments: [(1, "1 question"), (2, "2 questions")])
    func summaryQuestionPlural(count: Int, expected: String) throws {
        let results = (1...count).map { Self.result($0, .question("q")) }
        let summary = try #require(PinResult.summary(results))
        #expect(summary.contains(expected))
        if count == 1 { #expect(!summary.contains("questions")) }
    }

    // MARK: SentPinMark

    private static let spinningStages: [DeliveryStage] = [
        .sent(count: 2), .delivered, .received, .working(message: nil), .question(pin: 1)
    ]
    private static let stillStages: [DeliveryStage] = [
        .unclaimed, .done(message: nil), .failed(message: nil), .notSaved, .noAgent
    ]

    @Test("an open pin spins while the Send is on its way to the agent or with it", arguments: spinningStages)
    func openPinSpins(stage: DeliveryStage) {
        #expect(SentPinMark.resolve(outcome: .open, delivery: stage) == .progress)
        #expect(SentPinMark.resolve(outcome: .answered(question: nil, reply: "r"), delivery: stage) == .progress)
    }

    @Test("an open pin shows its number once nothing is in flight", arguments: stillStages)
    func openPinStill(stage: DeliveryStage) {
        #expect(SentPinMark.resolve(outcome: .open, delivery: stage) == .number)
    }

    @Test("with no delivery tracked an open pin shows its number")
    func noDeliveryShowsNumber() {
        #expect(SentPinMark.resolve(outcome: .open, delivery: nil) == .number)
    }

    @Test("an outcome glyph wins over the spinner and the number",
          arguments: [DeliveryStage?.none, .working(message: nil), .done(message: nil)])
    func glyphWins(stage: DeliveryStage?) {
        #expect(SentPinMark.resolve(outcome: .resolved(summary: nil), delivery: stage) == .symbol("checkmark", .success))
        #expect(SentPinMark.resolve(outcome: .question("q"), delivery: stage) == .symbol("questionmark", .attention))
        #expect(SentPinMark.resolve(outcome: .dismissed(reason: nil), delivery: stage) == .symbol("xmark", .muted))
    }
}
