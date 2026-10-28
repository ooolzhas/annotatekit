// OverlayModel: which bottom chrome shows (review bar vs comment card) and how a touch on the
// frozen screen classifies (stroke, hold, tap).

import Foundation
import Testing
@testable import AnnotateCore

@Suite struct OverlayModelTests {
    private static func inputs(open: Bool, comment: String = "", pins: Int = 0) -> OverlayChrome.Inputs {
        OverlayChrome.Inputs(isDraftOpen: open, draftComment: comment, pinCount: pins)
    }

    // MARK: OverlayChrome.resolve

    @Test("open draft with an empty or whitespace-only comment can't submit",
          arguments: ["", " ", "   \t", "\n", " \n\t \r\n"])
    func blankDraftCannotSubmit(comment: String) {
        #expect(OverlayChrome.resolve(Self.inputs(open: true, comment: comment, pins: 3))
                == .composing(canSubmit: false))
    }

    @Test("open draft with a non-blank comment can submit, whatever the pin count",
          arguments: [("x", 0), ("  fix padding \n", 0), ("fix padding", 4), ("a", -2)])
    func typedDraftCanSubmit(comment: String, pins: Int) {
        #expect(OverlayChrome.resolve(Self.inputs(open: true, comment: comment, pins: pins))
                == .composing(canSubmit: true))
    }

    @Test("no open draft shows the review bar with the pin count, ignoring any leftover comment",
          arguments: [0, 1, 4])
    func noDraftShowsReview(pins: Int) {
        #expect(OverlayChrome.resolve(Self.inputs(open: false, comment: "stale", pins: pins))
                == .review(count: pins))
    }

    @Test("a negative pin count clamps to review(count: 0)")
    func negativePinCountClamps() {
        #expect(OverlayChrome.resolve(Self.inputs(open: false, pins: -3)) == .review(count: 0))
    }

    // MARK: OverlayChrome.canSend

    @Test("Send is live only on the review bar with at least one pin",
          arguments: [
              (OverlayChrome.review(count: 0), false),
              (.review(count: 1), true),
              (.composing(canSubmit: false), false),
              (.composing(canSubmit: true), false)
          ])
    func canSend(chrome: OverlayChrome, expected: Bool) {
        #expect(chrome.canSend == expected)
    }

    // MARK: OverlayChrome.countTitle (pluralization is the contract)

    @Test("count title pluralizes: 1 is singular, more is plural",
          arguments: [(1, "1 comment"), (2, "2 comments"), (4, "4 comments")])
    func countTitlePluralizes(count: Int, expected: String) {
        #expect(OverlayChrome.countTitle(count) == expected)
    }

    @Test("nothing to count falls back to the empty hint", arguments: [0, -1])
    func countTitleEmpty(count: Int) {
        #expect(OverlayChrome.countTitle(count) == OverlayChrome.emptyHint)
    }

    // MARK: PointerIntent.classify

    private static let threshold = PointerIntent.moveThreshold
    private static let hold = PointerIntent.holdDuration

    @Test("travel strictly past moveThreshold draws, even past holdDuration and before lift",
          arguments: [
              (threshold.nextUp, 0.0, false),
              (threshold.nextUp, 0.0, true),
              (threshold.nextUp, hold, false),
              (threshold.nextUp, hold * 4, true)
          ])
    func movementWinsOverTime(distance: Double, duration: Double, isEnded: Bool) {
        #expect(PointerIntent.classify(distance: distance, duration: duration, isEnded: isEnded) == .draw)
    }

    @Test("travel of exactly moveThreshold is not a draw")
    func exactlyThresholdIsNotDraw() {
        #expect(PointerIntent.classify(distance: Self.threshold, duration: 0, isEnded: true) == .tap)
        #expect(PointerIntent.classify(distance: Self.threshold, duration: Self.hold, isEnded: false) == .hold)
    }

    @Test("still touch becomes a hold at exactly holdDuration, not just before",
          arguments: [
              (hold.nextDown, false, nil as PointerIntent?),
              (hold.nextDown, true, .tap),
              (hold, false, .hold),
              (hold, true, .hold)
          ])
    func holdBoundary(duration: Double, isEnded: Bool, expected: PointerIntent?) {
        #expect(PointerIntent.classify(distance: 0, duration: duration, isEnded: isEnded) == expected)
    }

    @Test("a short still touch is undecided while down and a tap once lifted")
    func shortStillTouch() {
        #expect(PointerIntent.classify(distance: 2, duration: 0.1, isEnded: false) == nil)
        #expect(PointerIntent.classify(distance: 2, duration: 0.1, isEnded: true) == .tap)
    }
}
