// ReviewHint: which line shows above the review bar (gestures, agent connected, or offline),
// the dot and action title each case carries, the agent display-name rule, and the shape of the
// hint text.
// Exact display copy is not pinned here; only case selection and the rules behind the copy.

@testable import AnnotateCore
import Foundation
import Testing

@Suite struct ReviewHintTests {
    private static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    private static func presence(
        _ agent: String = "Claude Code",
        mode: AgentPresence.Mode = .push,
        via: String = "mcp",
        project: String? = nil,
        updatedAt: Date = fixedDate
    ) -> AgentPresence {
        AgentPresence(agent: agent, mode: mode, via: via, project: project, updatedAt: updatedAt)
    }

    private static func resolve(_ agent: AgentPresence?, intro: Bool) -> ReviewHint {
        ReviewHint.resolve(ReviewHint.Inputs(agent: agent, isIntro: intro))
    }

    private static let allKinds: [ReviewHint] = [
        .gestures,
        .connected(agent: "Claude Code", mode: .push),
        .connected(agent: "Claude Code", mode: .pull),
        .offline
    ]

    // MARK: resolve

    @Test("annotate mode opens on the gestures hint whoever listens",
          arguments: [nil, presence(mode: .push), presence(mode: .pull)])
    func introIsGestures(agent: AgentPresence?) {
        #expect(Self.resolve(agent, intro: true) == .gestures)
    }

    @Test("after the intro no agent resolves to offline")
    func noAgentIsOffline() {
        #expect(Self.resolve(nil, intro: false) == .offline)
    }

    @Test("after the intro an agent resolves to connected, carrying the agent's name and mode",
          arguments: [AgentPresence.Mode.push, .pull])
    func agentIsConnected(mode: AgentPresence.Mode) {
        let presence = Self.presence("Cursor", mode: mode)
        #expect(Self.resolve(presence, intro: false) == .connected(agent: "Cursor", mode: mode))
    }

    @Test("via, project and updatedAt don't affect the resolved hint", arguments: [true, false])
    func irrelevantPresenceFieldsIgnored(intro: Bool) {
        let a = Self.presence("Codex", mode: .pull, via: "mcp", project: nil,
                              updatedAt: Date(timeIntervalSince1970: 0))
        let b = Self.presence("Codex", mode: .pull, via: "watch", project: "other-checkout",
                              updatedAt: Self.fixedDate)
        #expect(Self.resolve(a, intro: intro) == Self.resolve(b, intro: intro))
    }

    // MARK: dot

    @Test("dot: none for gestures, green for any connected, red for offline",
          arguments: [
              (ReviewHint.gestures, ReviewHint.Dot?.none),
              (.connected(agent: "Claude Code", mode: .push), .connected),
              (.connected(agent: "Cursor", mode: .pull), .connected),
              (.offline, .offline)
          ])
    func dot(hint: ReviewHint, expected: ReviewHint.Dot?) {
        #expect(hint.dot == expected)
    }

    // MARK: actionTitle

    @Test("action reads Save only while offline, Send otherwise",
          arguments: [
              (ReviewHint.offline, OverlayChrome.saveTitle),
              (.gestures, OverlayChrome.sendTitle),
              (.connected(agent: "Claude Code", mode: .push), OverlayChrome.sendTitle),
              (.connected(agent: "Cursor", mode: .pull), OverlayChrome.sendTitle)
          ])
    func actionTitle(hint: ReviewHint, expected: String) {
        #expect(hint.actionTitle == expected)
    }

    // MARK: displayName

    @Test("display name drops the Claude Code suffix, trims first, falls back to Agent when blank",
          arguments: [
              ("Claude Code", "Claude"),
              ("  Claude Code \n", "Claude"),
              ("", "Agent"),
              (" \t\n ", "Agent"),
              ("Cursor", "Cursor"),
              ("  Cursor  ", "Cursor")
          ])
    func displayName(raw: String, expected: String) {
        #expect(ReviewHint.displayName(raw) == expected)
    }

    // MARK: text

    @Test("connected text names the agent by its display name",
          arguments: [AgentPresence.Mode.push, .pull],
          ["Claude Code", "Cursor", "  "])
    func connectedTextContainsDisplayName(mode: AgentPresence.Mode, agent: String) {
        let text = ReviewHint.connected(agent: agent, mode: mode).text
        #expect(text.contains(ReviewHint.displayName(agent)))
    }

    @Test("pull-mode text differs from push-mode text for the same agent")
    func pullTextDiffersFromPush() {
        let push = ReviewHint.connected(agent: "Cursor", mode: .push).text
        let pull = ReviewHint.connected(agent: "Cursor", mode: .pull).text
        #expect(push != pull)
    }

    @Test("gestures, offline and connected texts are non-empty and pairwise distinct")
    func textsDistinctAndNonEmpty() {
        let texts = Self.allKinds.map(\.text)
        #expect(texts.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(Set(texts).count == texts.count)
    }

    // MARK: introHold

    @Test("the intro holds for a positive duration")
    func introHoldPositive() {
        #expect(ReviewHint.introHold > 0)
    }

    // MARK: delivery

    private static let allStages: [DeliveryStage] = [
        .sent(count: 2), .unclaimed, .delivered, .received, .working(message: nil),
        .done(message: nil), .failed(message: nil), .notSaved, .noAgent
    ]

    private static func delivery(_ stage: DeliveryStage) -> ReviewHint {
        .delivery(stage, agent: "Claude")
    }

    @Test("a tracked delivery wins over offline, connected and the intro",
          arguments: [
              (AgentPresence?.none, false),
              (AgentPresence?.none, true),
              (presence("Cursor"), true),
              (presence("Cursor"), false)
          ])
    func deliveryWins(agent: AgentPresence?, intro: Bool) {
        let inputs = ReviewHint.Inputs(agent: agent, isIntro: intro, delivery: .received)
        let expected = ReviewHint.delivery(.received, agent: ReviewHint.displayName(agent?.agent ?? ""))
        #expect(ReviewHint.resolve(inputs) == expected)
    }

    @Test("the delivery's agent is the display name: nil agent reads Agent, Claude Code reads Claude",
          arguments: [
              (AgentPresence?.none, "Agent"),
              (presence("Claude Code"), "Claude"),
              (presence("  Cursor "), "Cursor")
          ])
    func deliveryCarriesDisplayName(agent: AgentPresence?, expected: String) {
        let inputs = ReviewHint.Inputs(agent: agent, isIntro: false, delivery: .delivered)
        #expect(ReviewHint.resolve(inputs) == .delivery(.delivered, agent: expected))
    }

    @Test("delivery dot: green while on plan, red for stages that need attention",
          arguments: [
              (DeliveryStage.sent(count: 1), ReviewHint.Dot.connected),
              (.delivered, .connected),
              (.received, .connected),
              (.working(message: "busy"), .connected),
              (.done(message: nil), .connected),
              (.unclaimed, .offline),
              (.failed(message: nil), .offline),
              (.notSaved, .offline),
              (.noAgent, .offline)
          ])
    func deliveryDot(stage: DeliveryStage, expected: ReviewHint.Dot) {
        #expect(Self.delivery(stage).dot == expected)
    }

    @Test("offline splits into a headline and a dimmed detail (Figma 9276:28048 / 9276:28049)")
    func offlineParts() {
        #expect(ReviewHint.offline.headline == "No agent connected")
        #expect(ReviewHint.offline.detail == "Notes will be saved")
        #expect(ReviewHint.offline.text == "No agent connected · Notes will be saved")
    }

    @Test("sending counts the notes written so far, never past the total",
          arguments: [(0, 4, "0/4"), (1, 4, "1/4"), (4, 4, "4/4"), (6, 4, "4/4")])
    func sendingProgress(written: Int, notes: Int, expected: String) {
        let hint = ReviewHint.delivery(.sent(count: notes), agent: "Claude", notes: notes, written: written)
        #expect(hint.headline == "Sending notes")
        #expect(hint.detail == expected)
    }

    @Test("a Send with no count says only that it's sending")
    func sendingWithoutCount() {
        #expect(ReviewHint.delivery(.sent(count: 1), agent: "Claude").detail == nil)
    }

    @Test("done counts the Send's notes", arguments: [(1, "1 note"), (4, "4 notes")])
    func doneCountsNotes(notes: Int, expected: String) {
        let hint = ReviewHint.delivery(.done(message: "Shipped"), agent: "Claude", notes: notes)
        #expect(hint.headline == "Claude is done")
        #expect(hint.detail == expected)
    }

    @Test("a failed Send reads Error, with the agent's reason when it gave one")
    func failedReadsError() {
        #expect(ReviewHint.delivery(.failed(message: "Build broke"), agent: "Claude").text == "Error · Build broke")
        #expect(ReviewHint.delivery(.failed(message: nil), agent: "Claude").text == "Error")
    }

    @Test("text is the headline, then the detail after a middle dot",
          arguments: allKinds + allStages.map { delivery($0) } + [
              delivery(.done(message: "Shipped")), delivery(.failed(message: "Build broke")),
              delivery(.working(message: "a · b"))
          ])
    func textJoinsParts(hint: ReviewHint) {
        let expected = hint.detail.map { "\(hint.headline) · \($0)" } ?? hint.headline
        #expect(hint.text == expected)
        #expect(!hint.headline.isEmpty)
        #expect(hint.detail?.isEmpty != true)
    }

    @Test("an agent's working message splits at its first middle dot")
    func workingMessageSplits() {
        let hint = Self.delivery(.working(message: "All changes applied · Reinstalling"))
        #expect(hint.headline == "All changes applied")
        #expect(hint.detail == "Reinstalling")
    }

    @Test("a working message stays whole when a side of the dot would be empty",
          arguments: ["Built · ", " · reinstalling", "Built and reinstalling"])
    func workingMessageStaysWhole(message: String) {
        let hint = Self.delivery(.working(message: message))
        #expect(hint.detail == nil)
    }

    @Test("no working message falls back to the agent working")
    func workingFallback() {
        #expect(Self.delivery(.working(message: nil)).headline == "Claude is working…")
    }

    @Test("elapsed time shows exactly while the delivery is still in flight", arguments: allStages)
    func showsElapsedTracksNonFinal(stage: DeliveryStage) {
        #expect(Self.delivery(stage).showsElapsed == !stage.isFinal)
    }

    @Test("non-delivery hints never show elapsed time", arguments: allKinds)
    func nonDeliveryNeverShowsElapsed(hint: ReviewHint) {
        #expect(!hint.showsElapsed)
    }

    @Test("elapsed text: seconds below a minute, then minutes and seconds, negative reads 0s",
          arguments: [
              (-5, "0s"),
              (0, "0s"),
              (59, "59s"),
              (60, "1m 0s"),
              (65, "1m 5s"),
              (119, "1m 59s"),
              (3600, "60m 0s")
          ])
    func elapsedText(seconds: Int, expected: String) {
        #expect(ReviewHint.elapsedText(seconds) == expected)
    }

    @Test("delivery action reads Save only for noAgent, Send for every other stage", arguments: allStages)
    func deliveryActionTitle(stage: DeliveryStage) {
        let expected = stage == .noAgent ? OverlayChrome.saveTitle : OverlayChrome.sendTitle
        #expect(Self.delivery(stage).actionTitle == expected)
    }

    @Test("a blank agent message falls back to the same text as no message",
          arguments: ["", "   ", " \n\t "])
    func blankMessageFallsBack(blank: String) {
        #expect(Self.delivery(.working(message: blank)).text == Self.delivery(.working(message: nil)).text)
        #expect(Self.delivery(.done(message: blank)).text == Self.delivery(.done(message: nil)).text)
        #expect(Self.delivery(.failed(message: blank)).text == Self.delivery(.failed(message: nil)).text)
    }

    @Test("a non-blank agent message appears trimmed in the text (done shows the note count instead)")
    func messageAppearsTrimmed() {
        let stages: [DeliveryStage] = [
            .working(message: "  Reinstalling\n"), .failed(message: "  Reinstalling\n")
        ]
        for stage in stages {
            let text = Self.delivery(stage).text
            #expect(text.contains("Reinstalling"))
            #expect(!text.contains("  Reinstalling"))
            #expect(!text.contains("Reinstalling\n"))
        }
    }
}
