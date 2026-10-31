// Selection stack ordering/merging/navigation, source resolution, display names and placement math.

#if canImport(CoreGraphics)
// CGRect's initializers and Equatable conformance live in the CoreGraphics overlay on Apple platforms
import CoreGraphics
#endif
import Foundation
import Testing
@testable import AnnotateCore

@Suite struct SelectionStackTests {
    let screen = ElementCandidate(frame: CGRect(x: 0, y: 0, width: 400, height: 800), info: ElementInfo(role: "view", typeName: "UIWindow"))
    let card = RegisteredView(name: "HeroCard", frame: CGRect(x: 20, y: 100, width: 360, height: 300), file: "/p/App/HomeView.swift", line: 42)
    let button = ElementCandidate(frame: CGRect(x: 40, y: 300, width: 120, height: 44), info: ElementInfo(role: "button", label: "Get started", traits: ["button"]))
    let title = ElementCandidate(frame: CGRect(x: 40, y: 120, width: 300, height: 40), info: ElementInfo(role: "header", label: "Light that follows your day"))

    @Test func picksSmallestCandidateUnderPointFirst() {
        let stack = SelectionStack(candidates: [screen, card.candidate, button, title], at: CGPoint(x: 60, y: 320))
        #expect(stack.current?.info.role == "button")
        #expect(stack.candidates.count == 3) // title doesn't contain the point
    }

    @Test func expandAndNarrowWalkTheStackAndStopAtEnds() {
        var stack = SelectionStack(candidates: [screen, card.candidate, button], at: CGPoint(x: 60, y: 320))
        let toCard = stack.expand()
        #expect(toCard)
        #expect(stack.current?.info.title == "HeroCard")
        let toWindow = stack.expand()
        #expect(toWindow)
        #expect(stack.current?.info.title == "UIWindow")
        let pastTop = stack.expand()
        #expect(pastTop == false)
        let back = stack.narrow()
        #expect(back)
        #expect(stack.current?.info.title == "HeroCard")
    }

    @Test func narrowingPastTheSmallestElementSelectsThePoint() {
        var stack = SelectionStack(candidates: [screen, button], at: CGPoint(x: 60, y: 320))
        #expect(!stack.isAtPoint)
        let toPoint = stack.narrow()
        #expect(toPoint)
        #expect(stack.isAtPoint)
        #expect(stack.current == nil)
        #expect(stack.breadcrumb() == ["Button", "UIWindow"])
        let further = stack.narrow()
        #expect(further == false)
        let back = stack.expand()
        #expect(back)
        #expect(stack.current?.info.role == "button")
    }

    @Test func tapOnOnlyLargeContainersStartsAtThePoint() {
        // 400×800 screen; the smallest thing under (200, 600) is the card-less window
        let stack = SelectionStack(candidates: [screen, card.candidate], at: CGPoint(x: 200, y: 600), screenArea: 400 * 800)
        #expect(stack.isAtPoint)
        let onCard = SelectionStack(candidates: [screen, card.candidate, button], at: CGPoint(x: 60, y: 320), screenArea: 400 * 800)
        #expect(!onCard.isAtPoint)
        #expect(onCard.current?.info.role == "button")
    }

    @Test func pointResolvesEnclosingSource() {
        let stack = SelectionStack(candidates: [screen, card.candidate], at: CGPoint(x: 300, y: 200), screenArea: 400 * 800)
        // Card is 360×300 = 34% of the screen, under the 40% container threshold
        #expect(!stack.isAtPoint)
        var atPoint = stack
        atPoint.narrow()
        #expect(atPoint.resolvedSource?.name == "HeroCard")
        #expect(atPoint.resolvedSource?.match == .enclosing)
    }

    @Test func mergesNearlyEqualFramesKeepingRoleLabelAndSource() {
        // An AX button node and an `.annotatable("CTA")` registration around the same box
        let registration = RegisteredView(name: "CTA", frame: button.frame.insetBy(dx: 0.5, dy: 0.5), file: "/p/App/Hero.swift", line: 9)
        let stack = SelectionStack(candidates: [registration.candidate, button], at: CGPoint(x: 60, y: 320))
        #expect(stack.candidates.count == 1)
        let merged = stack.current
        #expect(merged?.info.role == "button")
        #expect(merged?.info.label == "Get started")
        #expect(merged?.info.typeName == "CTA")
        #expect(merged?.source?.line == 9)
        #expect(stack.resolvedSource?.match == .exact)
    }

    @Test func resolvedSourceFallsBackToEnclosingRegistration() {
        let stack = SelectionStack(candidates: [screen, card.candidate, button], at: CGPoint(x: 60, y: 320))
        let source = stack.resolvedSource
        #expect(source?.name == "HeroCard")
        #expect(source?.line == 42)
        #expect(source?.match == .enclosing)
    }

    @Test func breadcrumbListsEnclosingTitlesNearestFirst() {
        let stack = SelectionStack(candidates: [screen, card.candidate, button], at: CGPoint(x: 60, y: 320))
        #expect(stack.breadcrumb() == ["HeroCard", "UIWindow"])
        #expect(stack.currentInfo?.breadcrumb == ["HeroCard", "UIWindow"])
    }

    @Test func ignoresZeroAreaFrames() {
        let line = ElementCandidate(frame: CGRect(x: 0, y: 320, width: 400, height: 0), info: ElementInfo(role: "view"))
        let stack = SelectionStack(candidates: [line, button], at: CGPoint(x: 60, y: 320))
        #expect(stack.candidates.count == 1)
    }

    @Test func emptyWhenNothingContainsThePoint() {
        let stack = SelectionStack(candidates: [button], at: CGPoint(x: 390, y: 790))
        #expect(stack.isEmpty)
        #expect(stack.isAtPoint)
        #expect(stack.current == nil)
        #expect(stack.resolvedSource == nil)
    }
}

@Suite struct SourceResolverTests {
    let screenView = RegisteredView(name: "HomeView", frame: CGRect(x: 0, y: 0, width: 400, height: 800), file: "Home.swift", line: 10)
    let card = RegisteredView(name: "HeroCard", frame: CGRect(x: 20, y: 100, width: 360, height: 300), file: "Hero.swift", line: 5)

    @Test func picksSmallestEnclosingRegistration() {
        let source = SourceResolver.resolve(frame: CGRect(x: 30, y: 120, width: 100, height: 50), in: [screenView, card])
        #expect(source?.name == "HeroCard")
        #expect(source?.match == .enclosing)
    }

    @Test func exactWhenFramesMatch() {
        let source = SourceResolver.resolve(frame: card.frame, in: [screenView, card])
        #expect(source?.match == .exact)
    }

    @Test func regionStraddlingTheCardResolvesToTheScreen() {
        let source = SourceResolver.resolve(frame: CGRect(x: 10, y: 350, width: 200, height: 200), in: [screenView, card])
        #expect(source?.name == "HomeView")
    }

    @Test func nilWhenNothingEncloses() {
        #expect(SourceResolver.resolve(frame: CGRect(x: 500, y: 0, width: 10, height: 10), in: [card]) == nil)
    }
}

@Suite struct DisplayNameTests {
    @Test func roleTitleWithTruncatedLabel() {
        let info = ElementInfo(role: "text", label: "Adaptive lamps for every room in your home and office")
        #expect(info.displayName(maxLabelLength: 20) == "Text \"Adaptive lamps for…\"")
    }

    @Test func genericRoleUsesTypeName() {
        #expect(ElementInfo(role: "view", typeName: "HeroCard").displayName() == "HeroCard")
        #expect(ElementInfo(role: "view").displayName() == "View")
    }

    @Test func fileStemAndShortDescription() {
        #expect(SourceLocation.fileStem("/a/b/HomeView.swift") == "HomeView")
        #expect(SourceLocation(file: "App/HomeView.swift", line: 3, match: .exact).shortDescription == "HomeView.swift:3")
    }
}

@Suite struct PlacementTests {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    @Test func pinSitsOnTopTrailingCornerClampedInside() {
        #expect(OverlayPlacement.pinCenter(for: CGRect(x: 10, y: 100, width: 100, height: 40), radius: 11, in: bounds) == CGPoint(x: 110, y: 100))
        #expect(OverlayPlacement.pinCenter(for: CGRect(x: 300, y: 0, width: 100, height: 40), radius: 11, in: bounds) == CGPoint(x: 389, y: 11))
    }

    @Test func sketchPinSitsOnTheLineAFractionAlong() {
        // Two strokes, 100 + 100 long; the jump between them doesn't count
        let strokes = [
            Stroke(tool: .pen, points: [AnnotationPoint(x: 0, y: 0), AnnotationPoint(x: 100, y: 0)]),
            Stroke(tool: .pen, points: [AnnotationPoint(x: 100, y: 50), AnnotationPoint(x: 100, y: 150)])
        ]
        #expect(OverlayPlacement.point(along: strokes, fraction: 0.15) == CGPoint(x: 30, y: 0))
        #expect(OverlayPlacement.point(along: strokes, fraction: 0.75) == CGPoint(x: 100, y: 100))
        #expect(OverlayPlacement.point(along: strokes, fraction: 1) == CGPoint(x: 100, y: 150))
        #expect(OverlayPlacement.point(along: strokes, fraction: 2) == CGPoint(x: 100, y: 150))
        #expect(OverlayPlacement.point(along: strokes, fraction: -1) == CGPoint(x: 0, y: 0))
    }

    @Test func sketchPinSitsOnTheDrawnCurveNotTheSamples() throws {
        // The drawn line rounds the corner at (100, 0) through (50, 0) and (100, 50), so halfway
        // along it is inside the corner, not on it as halfway along the samples would be
        let corner = [Stroke(tool: .pen, points: [
            AnnotationPoint(x: 0, y: 0), AnnotationPoint(x: 100, y: 0), AnnotationPoint(x: 100, y: 100)
        ])]
        let line = OverlayPlacement.drawnPoints(of: corner[0])
        #expect(line.first == CGPoint(x: 0, y: 0))
        #expect(line.last == CGPoint(x: 100, y: 100))
        #expect(line.contains(CGPoint(x: 50, y: 0)))
        #expect(line.contains(CGPoint(x: 100, y: 50)))
        let point = try #require(OverlayPlacement.point(along: corner, fraction: 0.5))
        #expect(point.x < 100 && point.y > 0)
        // On the curve: the quadratic from (50, 0) to (100, 50) bulges toward (100, 0) no further
        // than the point at t = 0.5, (87.5, 12.5)
        #expect(abs(point.x - 87.5) < 1 && abs(point.y - 12.5) < 1)
    }

    @Test func sketchPinSitsOnTheFirstStrokeNearItsEnd() {
        let first = Stroke(tool: .pen, points: [AnnotationPoint(x: 0, y: 0), AnnotationPoint(x: 100, y: 0)])
        let second = Stroke(tool: .pen, points: [AnnotationPoint(x: 0, y: 50), AnnotationPoint(x: 300, y: 50)])
        #expect(OverlayPlacement.sketchPin(for: [first]) == CGPoint(x: 85, y: 0))
        // Drawing another shape into the same pin leaves it where it was
        #expect(OverlayPlacement.sketchPin(for: [first, second]) == CGPoint(x: 85, y: 0))
        #expect(OverlayPlacement.sketchPin(for: []) == nil)
    }

    @Test func sketchPinWithoutLengthFallsBack() {
        #expect(OverlayPlacement.point(along: [], fraction: 0.15) == nil)
        let dot = [Stroke(tool: .pen, points: [AnnotationPoint(x: 7, y: 9)])]
        #expect(OverlayPlacement.point(along: dot, fraction: 0.15) == CGPoint(x: 7, y: 9))
    }

    @Test func cardGoesBelowThenAboveThenBottom() {
        let size = CGSize(width: 280, height: 120)
        let below = OverlayPlacement.cardFrame(size: size, anchoredTo: CGRect(x: 20, y: 100, width: 100, height: 40), in: bounds)
        #expect(below.origin.y == 150)
        let above = OverlayPlacement.cardFrame(size: size, anchoredTo: CGRect(x: 20, y: 700, width: 100, height: 40), in: bounds)
        #expect(above.origin.y == 570)
        let fallback = OverlayPlacement.cardFrame(size: size, anchoredTo: CGRect(x: 0, y: 50, width: 400, height: 700), in: bounds)
        #expect(fallback.origin.y == 680)
    }

    @Test func cardClampsHorizontally() {
        let frame = OverlayPlacement.cardFrame(size: CGSize(width: 280, height: 100), anchoredTo: CGRect(x: 300, y: 100, width: 80, height: 40), in: bounds)
        #expect(frame.origin.x == 120)
    }

    @Test func spanningNormalizesDragDirection() {
        #expect(CGRect.spanning(CGPoint(x: 50, y: 80), CGPoint(x: 10, y: 20)) == CGRect(x: 10, y: 20, width: 40, height: 60))
    }
}
