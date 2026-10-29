// Root of the overlay window: the launcher while idle, and while annotating the frozen screen
// dimmed with a pulsing blue edge glow, the touch catcher that feeds the controller (draw / tap / hold),
// every pin's white markers and number badges, and the bottom chrome docked to the keyboard or the
// home indicator: the reply card while answering an agent's question about a sent pin, the comment
// card while a pin is open, the last Send's results card, otherwise the review bar with its hint
// line above it (which also narrates the last Send while annotate mode is open, and opens the
// results on tap once there are any), all over a blue gradient that runs from the chrome's top
// down to the screen's bottom.
// Motion (no Figma motion context): entering and leaving annotate mode cross-fades the frozen screen
// while the bottom chrome (`BottomChrome`, a separate view so it can) rises into place and sinks
// away; the bar, comment card, reply card and results card swap with a short slide, fade and scale
// from the bottom; the launcher pill scales down and fades about its own center. Reduce Motion keeps
// the fades only.
// The whole tree ignores the safe area so SwiftUI coordinates equal window (= screen) points, which
// is the space every frame from ElementScanner and the registry uses. Things are placed by top-left
// offset inside a full-screen top-leading ZStack. The freeze-frame captured on start sits at the
// bottom of the stack: the app looks paused, and every coordinate refers to exactly that image.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI

struct OverlayRoot: View {
    let controller: AnnotateController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Top of the bottom chrome, measured by BottomChrome; ActiveOverlay's gradient starts there.
    @State private var chromeTop: CGFloat?

    /// How small the launcher pill gets as it fades out (and grows back from as it fades in).
    private static let launcherHiddenScale: CGFloat = 0.8
    /// How far below its place the bottom chrome starts as annotate mode opens (and ends as it closes).
    private static let chromeEntranceOffset: CGFloat = 48

    var body: some View {
        ZStack(alignment: .topLeading) {
            if controller.isActive {
                ActiveOverlay(controller: controller, chromeTop: chromeTop)
                    .transition(.opacity)
                // A sibling rather than part of ActiveOverlay so it gets its own entrance: only the
                // views an `if` inserts run a transition, never their children
                BottomChrome(controller: controller, chromeTop: $chromeTop)
                    .transition(chromeEntrance)
            } else if controller.options.showsLauncher {
                LauncherButton(controller: controller)
                    .transition(launcherTransition)
            }

            // In-mode messages ("Removed pin 2"); delivery progress lives on the launcher pill
            if let toast = controller.toast {
                ToastView(message: toast.message, controller: controller)
                    .id(toast.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .animation(.snappy(duration: 0.3), value: controller.isActive)
        .animation(.snappy(duration: 0.2), value: controller.toast)
    }

    /// Scale and fade about the pill's own center. LauncherButton fills the screen (it places the
    /// pill with `.position`), so an unanchored scale would pull the pill toward the screen's middle.
    private var launcherTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let bounds = controller.bounds
        let pill = controller.launcherFrame
        let anchor = UnitPoint(
            x: bounds.width > 0 ? pill.midX / bounds.width : 0.5,
            y: bounds.height > 0 ? pill.midY / bounds.height : 0.5
        )
        return .scale(scale: Self.launcherHiddenScale, anchor: anchor).combined(with: .opacity)
    }

    /// The bar (or a card) rises into place as annotate mode opens and sinks as it closes, while the
    /// frozen screen behind it cross-fades.
    private var chromeEntrance: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .offset(y: Self.chromeEntranceOffset).combined(with: .opacity)
    }
}

/// The bottom chrome: the reply card, comment card or results card, otherwise the hint line and the
/// review bar. It measures its own top for ActiveOverlay's gradient (`chromeTop`).
private struct BottomChrome: View {
    let controller: AnnotateController
    @Binding var chromeTop: CGFloat?

    /// Gap between the comment card and the keyboard / home indicator, and from the screen sides
    /// (Figma 9272:16850: `pb-[8px] px-[8px]`).
    private static let chromeInset: CGFloat = 8
    /// Review bar inset from each screen side (Figma 9272:17106: `px-[34px]`). Its bottom has no
    /// extra gap: Figma's `pb-[34px]` is the home-indicator inset, which `screenChromeBottom` already is.
    private static let reviewBarInset: CGFloat = 34
    /// Space between the hint line's bottom and the review bar's top (Figma 9272:17120:
    /// `bottom-[110px]` = 34 inset + 60 bar + 16).
    private static let hintGap: CGFloat = 16
    /// The chrome's keyboard snap (no Figma motion), shared by the gradient so the two move together.
    private static let chromeAnimation: Animation = .snappy(duration: 0.25)
    /// Bar ↔ card ↔ results swaps: each comes in from (and leaves toward) this far below, slightly
    /// scaled down from its bottom edge, fading.
    private static let swapOffset: CGFloat = 24
    private static let swapScale: CGFloat = 0.96
    private static let swapAnimation: Animation = .spring(duration: 0.35, bounce: 0.15)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reply card, comment card or results card (all 8pt sides, 8pt above `chromeBottom`, so the
    /// reply and comment cards dock to the keyboard), otherwise the review bar (34pt sides, bottom at
    /// `screenChromeBottom`, never the keyboard) with the hint line 16pt above it. `chromeBottom` is
    /// the keyboard top, or the top of the home-indicator area with no keyboard.
    var body: some View {
        let bounds = controller.bounds
        // Distance from each chrome's bottom down to the screen's bottom edge. Each child carries its
        // own, so a card leaving with the keyboard and the bar arriving at the home indicator overlap
        // correctly while they swap
        let belowCard = max(bounds.maxY - controller.chromeBottom, 0)
        let belowBar = max(bounds.maxY - controller.screenChromeBottom, 0)

        // A ZStack, not a Group: the outgoing and incoming chrome overlap at the bottom while they swap,
        // and the measurement below reads the stack, not each child
        return ZStack(alignment: .bottom) {
            switch controller.chrome {
            case .replying:
                // No Figma: placed exactly like the comment card, keyboard-docked through
                // `chromeBottom`
                if let reply = controller.replyDraft {
                    ReplyCard(controller: controller, reply: reply)
                        .padding(.horizontal, Self.chromeInset)
                        .padding(.bottom, Self.chromeInset + belowCard)
                        .transition(swapTransition)
                }
            case .composing:
                if let draft = controller.draft {
                    ComposerCard(controller: controller, draft: draft)
                        .id(draft.annotation.id)
                        .padding(.horizontal, Self.chromeInset)
                        .padding(.bottom, Self.chromeInset + belowCard)
                        .transition(swapTransition)
                }
            case .results:
                // No Figma: placed like the comment card (8pt sides, 8pt above `chromeBottom`)
                ResultsCard(controller: controller)
                    .padding(.horizontal, Self.chromeInset)
                    .padding(.bottom, Self.chromeInset + belowCard)
                    .transition(swapTransition)
            case .review:
                VStack(spacing: Self.hintGap) {
                    ReviewHintLine(
                        hint: controller.reviewHint,
                        startedAt: controller.deliveryStartedAt,
                        // Tapping the hint reopens the last Send's results, once there are any
                        onTap: controller.pinResults.isEmpty ? nil : { controller.openResults() }
                    )
                        // Delivery narration ("Changes applied, reinstalling 9s") runs wider than
                        // the gestures hint: keep it on one centered line within the bar's 34pt insets
                        .padding(.horizontal, Self.reviewBarInset)
                    ReviewBar(controller: controller)
                        .padding(.horizontal, Self.reviewBarInset)
                }
                // Anchored to the home indicator: the bar never rides the keyboard
                .padding(.bottom, belowBar)
                .transition(swapTransition)
            }
        }
        .animation(Self.swapAnimation, value: chromeKind)
        .frame(width: bounds.width)
        // The gradient lives in ActiveOverlay (under markers and badges), so it can't simply be
        // this stack's background; it reads the stack's top from here instead. The tree ignores
        // the safe area in its own window, so global = screen points, like `bounds`.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).minY
        } action: { newTop in
            // Layout reports the end value once; animate the gradient there with the chrome's
            // own snap so it follows card ↔ bar and the keyboard instead of jumping
            withAnimation(Self.chromeAnimation) { chromeTop = newTop }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .bottom)
        // No Figma motion: follow the keyboard with a short snap rather than jumping
        .animation(Self.chromeAnimation, value: controller.keyboardTop)
        // The bar's count ("2 notes") follows pins saved and removed
        .animation(.snappy(duration: 0.2), value: controller.annotations)
    }

    /// Which chrome shows, for the swap animation: the case without its payload (a submit-state or
    /// count change isn't a swap), plus the open pin, so moving to another pin swaps the card too.
    private var chromeKind: ChromeKind {
        switch controller.chrome {
        case .replying: .replying
        case .composing: .composing(controller.draft?.annotation.id)
        case .results: .results
        case .review: .review
        }
    }

    private enum ChromeKind: Hashable {
        case replying, composing(UUID?), results, review
    }

    private var swapTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .offset(y: Self.swapOffset)
            .combined(with: .scale(scale: Self.swapScale, anchor: .bottom))
            .combined(with: .opacity)
    }
}

private struct ActiveOverlay: View {
    let controller: AnnotateController

    /// Top edge of the bottom chrome in screen points (BottomChrome measures it); the gradient starts
    /// here. Nil until the first layout pass.
    let chromeTop: CGFloat?

    /// Strength of the bottom gradient at the screen's bottom edge; it fades to clear at the
    /// chrome's top (Figma 9272:16849 / 9272:17105: `from-[rgba(0,136,255,0)] to-[rgba(0,136,255,0.5)]`).
    private static let gradientOpacity: Double = 0.5
    var body: some View {
        let bounds = controller.bounds
        let openID = controller.draft?.annotation.id
        // Figma's composing frames show no badge for the pin being written: the open draft draws
        // its own marker from the live draft instead of its saved copy.
        let saved = controller.visibleAnnotations.filter { $0.id != openID }

        ZStack(alignment: .topLeading) {
            if let frozen = controller.frozenImage {
                Image(uiImage: frozen)
                    .resizable()
                    .frame(width: bounds.width, height: bounds.height)
                    .allowsHitTesting(false)
            }

            Color.black.opacity(AnnotateStyle.dimOpacity)
                .frame(width: bounds.width, height: bounds.height)
                .allowsHitTesting(false)

            // Figma 9257:13546: the Overlay layer (dim + glow, 9257:13547) sits below every marker
            // and badge, so pins near the edge stay pure white
            ScreenGlow()
                .frame(width: bounds.width, height: bounds.height)
                .allowsHitTesting(false)

            // Figma layer order: Overlay (dim + glow), then the gradient, then pins and chrome
            bottomGradient

            captureLayer

            ForEach(saved) { annotation in
                PinMarker(
                    annotation: annotation,
                    strokes: annotation.sketchInScreenPoints,
                    bounds: bounds
                )
            }

            if let draft = controller.draft {
                PinMarker(annotation: draft.annotation, strokes: draft.strokes, bounds: bounds)
            }

            if let live = controller.liveStroke {
                SketchStrokes(strokes: [live])
                    .frame(width: bounds.width, height: bounds.height)
                    .allowsHitTesting(false)
            }

            ForEach(saved) { pin in
                PinBadge(number: pin.index) {
                    controller.openExisting(pin.id)
                }
                .position(OverlayPlacement.pinCenter(
                    for: pin.pinAnchorFrame,
                    radius: AnnotateStyle.badgeSize / 2,
                    in: bounds
                ))
                .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: controller.annotations)
    }

    /// Full-screen catcher: every touch goes to the controller, which tells draw, tap and hold apart.
    private var captureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: controller.bounds.width, height: controller.bounds.height)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { controller.touchChanged(start: $0.startLocation, location: $0.location) }
                    .onEnded { controller.touchEnded(start: $0.startLocation, location: $0.location) }
            )
    }

    /// Blue wash behind the bottom chrome (Figma 9272:16849 composing / 9272:17105 review): full
    /// screen width, from the chrome stack's top (card, or hint line) down past the keyboard /
    /// home indicator to the screen's bottom edge. Nothing is drawn until the chrome is measured.
    @ViewBuilder
    private var bottomGradient: some View {
        if let top = chromeTop {
            let bounds = controller.bounds
            LinearGradient(
                colors: [
                    AnnotateStyle.action.opacity(0),
                    AnnotateStyle.action.opacity(Self.gradientOpacity)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: bounds.width, height: max(bounds.maxY - top, 0))
            .offset(y: top)
            // Decoration only: drawing on the frozen screen behind it must keep working
            .allowsHitTesting(false)
        }
    }
}

extension Annotation {
    /// Where the numbered badge attaches: the drawn box's outer top-trailing corner, just beside a
    /// spot, or a sketch's own stroke corner.
    var pinAnchorFrame: CGRect {
        switch kind {
        case .point:
            // Derived, no Figma row: SpotMarker.size / 2 (ring radius 9) plus badgeSize / 2 (12),
            // along the 45° diagonal, so the ring and the badge touch without overlapping
            let offset = AnnotateStyle.spotBadgeOffset
            return CGRect(x: anchor.x + offset, y: anchor.y - offset, width: 0, height: 0)
        case .sketch:
            // The controller pads stroke bounds; Figma puts the badge on the stroke's own corner
            // (9257:13566 vs 9257:13562), so undo that same padding here.
            let padding = AnnotateController.sketchPadding
            return frame.cgRect.insetBy(dx: padding, dy: padding)
        case .element, .region:
            // Badge center on the box's outer corner (Figma 9257:13564 corner = 9257:13570 center);
            // the box is the element frame grown by the outset, matching PinMarker
            return frame.cgRect.insetBy(
                dx: -AnnotateStyle.elementBoxOutset,
                dy: -AnnotateStyle.elementBoxOutset
            )
        }
    }
}

/// Everything drawn for one pin except its badge: the element box (also used for legacy regions),
/// the spot ring, and the pen strokes in screen points. Never takes touches.
private struct PinMarker: View {
    let annotation: Annotation
    let strokes: [Stroke]
    let bounds: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch annotation.kind {
            case .element, .region:
                // Regions are no longer created; old in-memory sessions render like element boxes
                let box = annotation.frame.cgRect.insetBy(
                    dx: -AnnotateStyle.elementBoxOutset,
                    dy: -AnnotateStyle.elementBoxOutset
                )
                RoundedRectangle(cornerRadius: AnnotateStyle.elementBoxRadius, style: .continuous)
                    .strokeBorder(AnnotateStyle.marker, lineWidth: AnnotateStyle.elementBoxLineWidth)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
            case .point:
                SpotMarker()
                    .offset(
                        x: annotation.anchor.x - SpotMarker.size / 2,
                        y: annotation.anchor.y - SpotMarker.size / 2
                    )
            case .sketch:
                EmptyView()
            }

            if !strokes.isEmpty {
                SketchStrokes(strokes: strokes)
                    .frame(width: bounds.width, height: bounds.height)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Ring marking an exact spot (hold pins). No Figma frame: the 0.1.x spot marker restyled white.
private struct SpotMarker: View {
    /// Outer ring diameter (0.1.x SpotMarker).
    static let size: CGFloat = 18
    /// Ring stroke width (0.1.x SpotMarker; matches the element box's 2pt border).
    private static let ringWidth: CGFloat = 2
    /// Center dot diameter (0.1.x SpotMarker).
    private static let dotSize: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().strokeBorder(AnnotateStyle.marker, lineWidth: Self.ringWidth)
            Circle().fill(AnnotateStyle.marker).frame(width: Self.dotSize, height: Self.dotSize)
        }
        .frame(width: Self.size, height: Self.size)
    }
}

/// Blue inset glow along the screen's rounded edge while annotating (Figma 9257:13385:
/// `rounded-[62px]`, `shadow-[inset_0_0_62px_0_rgba(0,136,255,0.5)]`). SwiftUI has no inset
/// shadow, so a wide stroke is blurred and masked back inside the same shape.
private struct ScreenGlow: View {
    /// Trough of the pulse, as a fraction of the Figma glow (which is the peak). Low enough to read
    /// as breathing, high enough that the edge never goes dark while annotating.
    private static let pulseFloor: Double = 0.4
    /// One half of the pulse (bright → dim). A slow breath, so it signals the mode without
    /// pulling the eye away from what's being drawn.
    private static let pulseHalfPeriod: Double = 1.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AnnotateStyle.screenCornerRadius, style: .continuous)
        // CSS `inset 0 0 62px`: the area just outside the edge, blurred inward (σ ≈ blur / 2) and
        // clipped to the screen, so the edge itself sits at half strength and it fades within ~40pt
        let glow = shape
            .inset(by: -AnnotateStyle.glowBlur / 2)
            .stroke(AnnotateStyle.glow, lineWidth: AnnotateStyle.glowBlur)
            .blur(radius: AnnotateStyle.glowBlur / 2)
            .mask(shape)

        // Pulses while annotate mode is on (not in Figma, which has no motion). Only opacity
        // animates, so the blur is rasterized once. Reduce Motion keeps the static Figma glow.
        if reduceMotion {
            glow
        } else {
            glow.phaseAnimator([false, true]) { content, isDim in
                content.opacity(isDim ? Self.pulseFloor : 1)
            } animation: { _ in
                .easeInOut(duration: Self.pulseHalfPeriod)
            }
        }
    }
}
#endif
