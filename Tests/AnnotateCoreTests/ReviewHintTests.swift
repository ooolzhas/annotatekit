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

    private static func resolve(_ agent: AgentPresence?, news: Bool) -> ReviewHint {
        ReviewHint.resolve(ReviewHint.Inputs(agent: agent, isConnectionNews: news))
    }

    private static let allKinds: [ReviewHint] = [
        .gestures,
        .connected(agent: "Claude Code", mode: .push),
        .connected(agent: "Claude Code", mode: .pull),
        .offline
    ]

    // MARK: resolve

    @Test("no agent resolves to offline whatever the news flag", arguments: [true, false])
    func noAgentIsOffline(news: Bool) {
        #expect(Self.resolve(nil, news: news) == .offline)
    }

    @Test("agent with news resolves to connected, carrying the agent's name and mode",
          arguments: [AgentPresence.Mode.push, .pull])
    func agentWithNewsIsConnected(mode: AgentPresence.Mode) {
        let presence = Self.presence("Cursor", mode: mode)
        #expect(Self.resolve(presence, news: true) == .connected(agent: "Cursor", mode: mode))
    }

    @Test("agent without news yields to the gestures hint", arguments: [AgentPresence.Mode.push, .pull])
    func agentWithoutNewsIsGestures(mode: AgentPresence.Mode) {
        #expect(Self.resolve(Self.presence(mode: mode), news: false) == .gestures)
    }

    @Test("via, project and updatedAt don't affect the resolved hint", arguments: [true, false])
    func irrelevantPresenceFieldsIgnored(news: Bool) {
        let a = Self.presence("Codex", mode: .pull, via: "mcp", project: nil,
                              updatedAt: Date(timeIntervalSince1970: 0))
        let b = Self.presence("Codex", mode: .pull, via: "watch", project: "other-checkout",
                              updatedAt: Self.fixedDate)
        #expect(Self.resolve(a, news: news) == Self.resolve(b, news: news))
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

    // MARK: connectionNewsHold

    @Test("connection news holds for a positive duration")
    func connectionNewsHoldPositive() {
        #expect(ReviewHint.connectionNewsHold > 0)
    }

    // MARK: delivery

    private static let allStages: [DeliveryStage] = [
        .sent(count: 2), .unclaimed, .delivered, .received, .working(message: nil),
        .done(message: nil), .failed(message: nil), .notSaved, .noAgent
    ]

    private static func delivery(_ stage: DeliveryStage) -> ReviewHint {
        .delivery(stage, agent: "Claude")
    }

    @Test("a tracked delivery wins over offline, connection news and gestures",
          arguments: [
              (AgentPresence?.none, false),
              (AgentPresence?.none, true),
              (presence("Cursor"), true),
              (presence("Cursor"), false)
          ])
    func deliveryWins(agent: AgentPresence?, news: Bool) {
        let inputs = ReviewHint.Inputs(agent: agent, isConnectionNews: news, delivery: .received)
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
        let inputs = ReviewHint.Inputs(agent: agent, isConnectionNews: false, delivery: .delivered)
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

    @Test("elapsed time shows exactly while the delivery is still in flight", arguments: allStages)
    func showsElapsedTracksNonFinal(stage: DeliveryStage) {
        #expect(Self.delivery(stage).showsElapsed == !stage.isFinal)
    }

    @Test("non-delivery hints never show elapsed time", arguments: allKinds)
    func nonDeliveryNeverShowsElapsed(hint: ReviewHint) {
        #expect(!hint.showsElapsed)
    }

    @Test("elapsed text: seconds below a minute, floored whole minutes from 60, negative reads 0s",
          arguments: [
              (-5, "0s"),
              (0, "0s"),
              (59, "59s"),
              (60, "1m"),
              (119, "1m"),
              (3600, "60m")
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

    @Test("a non-blank agent message appears trimmed in the text")
    func messageAppearsTrimmed() {
        let stages: [DeliveryStage] = [
            .working(message: "  Reinstalling\n"), .done(message: "  Reinstalling\n"),
            .failed(message: "  Reinstalling\n")
        ]
        for stage in stages {
            let text = Self.delivery(stage).text
            #expect(text.contains("Reinstalling"))
            #expect(!text.contains("  Reinstalling"))
            #expect(!text.contains("Reinstalling\n"))
        }
    }
}
