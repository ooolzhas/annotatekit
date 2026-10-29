// LauncherModel: whether the launcher pill is idle or narrating the last Send, which delivery
// stages are final, which haptic each stage plays, and the rules behind the pill's one-line title.

import Foundation
import Testing
@testable import AnnotateCore

@Suite struct LauncherModelTests {
    private static func resolve(_ delivery: DeliveryStage?, pending: Int) -> LauncherStatus {
        LauncherStatus.resolve(LauncherStatus.Inputs(delivery: delivery, pendingCount: pending))
    }

    private static func title(_ stage: DeliveryStage) -> String {
        LauncherStatus.delivery(stage).title
    }

    // MARK: LauncherStatus.resolve

    @Test("a showing delivery wins over pending pins",
          arguments: [
              (DeliveryStage.sent(count: 2), 0),
              (.unclaimed, 3),
              (.working(message: "x"), 5),
              (.done(message: nil), -1),
              (.notSaved, 7)
          ])
    func deliveryWins(stage: DeliveryStage, pending: Int) {
        #expect(Self.resolve(stage, pending: pending) == .delivery(stage))
    }

    @Test("no delivery resolves to idle with the pending count, clamped at 0",
          arguments: [(0, 0), (3, 3), (-1, 0), (-5, 0)])
    func noDeliveryIsIdle(pending: Int, expected: Int) {
        #expect(Self.resolve(nil, pending: pending) == .idle(pending: expected))
    }

    // MARK: DeliveryStage.isFinal

    @Test("only done, failed, notSaved and noAgent are final",
          arguments: [
              (DeliveryStage.sent(count: 1), false),
              (.unclaimed, false),
              (.delivered, false),
              (.received, false),
              (.working(message: nil), false),
              (.working(message: "busy"), false),
              (.done(message: nil), true),
              (.done(message: "ok"), true),
              (.failed(message: nil), true),
              (.failed(message: "no"), true),
              (.notSaved, true),
              (.noAgent, true)
          ])
    func isFinal(stage: DeliveryStage, expected: Bool) {
        #expect(stage.isFinal == expected)
    }

    // MARK: LauncherStatus.sentTitle

    @Test("sent title is singular for 1 and plural above; ≤ 0 reads as 1",
          arguments: [
              (1, "1 note sent"),
              (2, "2 notes sent"),
              (0, "1 note sent"),
              (-3, "1 note sent")
          ])
    func sentTitle(count: Int, expected: String) {
        #expect(LauncherStatus.sentTitle(count) == expected)
    }

    @Test("the sent stage's title is sentTitle of its count")
    func sentStageUsesSentTitle() {
        #expect(Self.title(.sent(count: 4)) == LauncherStatus.sentTitle(4))
    }

    // MARK: Idle title

    @Test("idle with no pending pins is exactly idleTitle")
    func idleZeroIsIdleTitle() {
        #expect(LauncherStatus.idle(pending: 0).title == LauncherStatus.idleTitle)
    }

    @Test("idle with pending pins carries the idle title and the count", arguments: [1, 12])
    func idlePendingCarriesCount(pending: Int) {
        let title = LauncherStatus.idle(pending: pending).title
        #expect(title != LauncherStatus.idleTitle)
        #expect(title.hasPrefix(LauncherStatus.idleTitle))
        #expect(title.hasSuffix(String(pending)))
    }

    // MARK: Agent message cleaning

    private static let blanks: [String] = ["", " ", "  \t", "\n", " \n\t \r\n"]

    @Test("a blank working message reads like no message", arguments: blanks)
    func blankWorkingIsNil(message: String) {
        #expect(Self.title(.working(message: message)) == Self.title(.working(message: nil)))
    }

    @Test("a blank done message reads like no message", arguments: blanks)
    func blankDoneIsNil(message: String) {
        #expect(Self.title(.done(message: message)) == Self.title(.done(message: nil)))
    }

    @Test("a blank failed message reads like no message", arguments: blanks)
    func blankFailedIsNil(message: String) {
        #expect(Self.title(.failed(message: message)) == Self.title(.failed(message: nil)))
    }

    @Test("a non-blank agent message is trimmed and shown in the title",
          arguments: [
              DeliveryStage.working(message: "  fixing padding \n"),
              .done(message: "\tfixing padding  "),
              .failed(message: " fixing padding")
          ])
    func messageTrimmedAndShown(stage: DeliveryStage) {
        let title = Self.title(stage)
        #expect(title.contains("fixing padding"))
        #expect(title == title.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(!title.contains("  "))
        #expect(!title.contains("\t") && !title.contains("\n"))
    }

    @Test("a working message replaces the default title outright")
    func workingMessageIsTheTitle() {
        #expect(Self.title(.working(message: "  reading bundle ")) == "reading bundle")
    }

    // MARK: Holds

    @Test("holds are positive and a final result lingers longer than the unclaimed notice")
    func holdOrdering() {
        #expect(LauncherStatus.unclaimedHold > 0)
        #expect(LauncherStatus.finalHold > LauncherStatus.unclaimedHold)
    }

    // MARK: DeliveryStage.haptic

    @Test("progress ticks; done succeeds; needing the user warns; failure errors",
          arguments: [
              (DeliveryStage.sent(count: 1), DeliveryHaptic.tick),
              (.delivered, .tick),
              (.received, .tick),
              (.working(message: "x"), .tick),
              (.done(message: nil), .success),
              (.question(pin: 2), .warning),
              (.unclaimed, .warning),
              (.noAgent, .warning),
              (.failed(message: nil), .error),
              (.notSaved, .error)
          ])
    func haptic(stage: DeliveryStage, expected: DeliveryHaptic) {
        #expect(stage.haptic == expected)
    }

    @Test("every final stage plays a notification, never a bare tick")
    func finalStagesNotify() {
        let finals: [DeliveryStage] = [.done(message: nil), .failed(message: "x"), .notSaved, .noAgent]
        for stage in finals {
            #expect(stage.isFinal)
            #expect(stage.haptic != .tick)
        }
    }
}
