// Root of the overlay window: the launcher while idle, and while annotating the frozen screen
// dimmed with a pulsing blue edge glow, the touch catcher that feeds the controller (draw / tap / hold),
// every pin's white markers and number badges (after a Send, the sent pins with spinners that turn
// into the agent's outcome), and the bottom chrome docked to the keyboard or the home indicator: the
// reply card while answering an agent's question about a sent pin, the comment card while a pin is
// open, otherwise the review bar with its hint line above it (which also narrates the last Send
// while annotate mode is open), all over a blue frost that runs from the chrome's top down to the
// screen's bottom. The notes sheet (every note and the last Send's outcomes) hangs off the chrome.
// Motion (no Figma motion context): entering and leaving annotate mode fades the frozen screen, its
// dim, the edge glow and the frost in and out over the same `modeDuration` the bottom chrome
// (`BottomChrome`, a separate view so it can) takes to rise into place and sink away; the bar,
// comment card and reply card swap with a fade while their glass materializes (iOS 26; before it a
// short slide, fade and scale from the bottom); the launcher pill scales down and fades about its own center, and
// comes in the same way once on a fresh open (`isLauncherRevealed`) instead of popping up. The edge glow and
// the frost behind the chrome drift like liquid while annotate mode is on. Reduce Motion keeps the
// fades only and holds the glow and frost still.
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
    /// How long entering and leaving annotate mode takes: the chrome's rise and the fade of the frozen
    /// screen, its dim, glow and frost all share it, so they arrive and leave together.
    static let modeDuration: Double = 0.3
    /// The chrome's rise and sink, and the launcher's scale.
    private static let modeAnimation: Animation = .snappy(duration: modeDuration)
    /// The dim, glow and frost fade on an ease rather than the chrome's spring: a spring on opacity
    /// is all but done in its first third and reads as a pop, an ease reads as a gradual fade.
    private static let backdropFade: Animation = .easeInOut(duration: modeDuration)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if controller.isActive {
                ActiveOverlay(controller: controller, chromeTop: chromeTop)
                    .transition(.opacity.animation(Self.backdropFade))
                // A sibling rather than part of ActiveOverlay so it gets its own entrance: only the
                // views an `if` inserts run a transition, never their children
                BottomChrome(controller: controller, chromeTop: $chromeTop)
                    .transition(chromeEntrance)
            } else if controller.options.showsLauncher && controller.isLauncherRevealed {
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
        .animation(Self.modeAnimation, value: controller.isActive)
        .animation(Self.modeAnimation, value: controller.isLauncherRevealed)
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

/// The bottom chrome: the reply card or comment card, otherwise the hint line and the
/// review bar. It measures its own top for ActiveOverlay's gradient (`chromeTop`).
private struct BottomChrome: View {
    let controller: AnnotateController
    @Binding var chromeTop: CGFloat?

    /// A card over the keyboard: 8pt from the screen sides and 8pt above the keyboard (Figma
    /// 9276:27184: `pb-[8px] px-[8px]`).
    private static let keyboardInset: CGFloat = 8
    /// The review bar, and a card with no keyboard up: 34pt from the screen sides (Figma 9276:27550 /
    /// 9276:27098: `px-[34px]`). The bottom has no extra gap: Figma's `pb-[34px]` is the home-indicator
    /// inset, which `screenChromeBottom` already is.
    private static let screenInset: CGFloat = 34
    /// Space between the hint line's bottom and the review bar's top (Figma 9272:17120:
    /// `bottom-[110px]` = 34 inset + 60 bar + 16).
    private static let hintGap: CGFloat = 16
    /// The chrome's keyboard snap (no Figma motion), shared by the gradient so the two move together.
    private static let chromeAnimation: Animation = .snappy(duration: 0.25)
    /// Bar ↔ card swaps: each comes in from (and leaves toward) this far below, slightly
    /// scaled down from its bottom edge, fading.
    private static let swapOffset: CGFloat = 24
    private static let swapScale: CGFloat = 0.96
    private static let swapAnimation: Animation = .spring(duration: 0.35, bounce: 0.15)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reply card or comment card: over the keyboard 8pt sides and 8pt above it, with
    /// no keyboard where the review bar sits (34pt sides, bottom at `screenChromeBottom`). Otherwise
    /// the review bar (34pt sides, bottom at `screenChromeBottom`, never the keyboard) with the hint
    /// line 16pt above it. `chromeBottom` is the keyboard top, or `screenChromeBottom` with none.
    var body: some View {
        let bounds = controller.bounds
        // Distance from each chrome's bottom down to the screen's bottom edge. Each child carries its
        // own, so a card leaving with the keyboard and the bar arriving at the home indicator overlap
        // correctly while they swap
        let belowBar = max(bounds.maxY - controller.screenChromeBottom, 0)
        let isKeyboardUp = controller.isKeyboardUp
        let cardSides = isKeyboardUp ? Self.keyboardInset : Self.screenInset
        let belowCard = max(bounds.maxY - controller.chromeBottom, 0) + (isKeyboardUp ? Self.keyboardInset : 0)

        // A ZStack, not a Group: the outgoing and incoming chrome overlap at the bottom while they swap,
        // and the measurement below reads the stack, not each child
        return ZStack(alignment: .bottom) {
            switch controller.chrome {
            case .replying:
                // No Figma: placed exactly like the comment card, keyboard-docked through
                // `chromeBottom`
                if let reply = controller.replyDraft {
                    ReplyCard(controller: controller, reply: reply)
                        .padding(.horizontal, cardSides)
                        .padding(.bottom, belowCard)
                        .transition(cardTransition)
                }
            case .composing:
                if let draft = controller.draft {
                    ComposerCard(controller: controller, draft: draft)
                        .id(draft.annotation.id)
                        .padding(.horizontal, cardSides)
                        .padding(.bottom, belowCard)
                        .transition(cardTransition)
                }
            case .review:
                VStack(spacing: Self.hintGap) {
                    ReviewHintLine(hint: controller.reviewHint, startedAt: controller.deliveryStartedAt)
                        // Delivery narration ("Changes applied, reinstalling 9s") runs wider than
                        // the gestures hint: keep it on one centered line within the bar's 34pt insets
                        .padding(.horizontal, Self.screenInset)
                    ReviewBar(controller: controller)
                        .padding(.horizontal, Self.screenInset)
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
        // Hung here rather than on the review bar so swapping the bar for a card can't tear it down
        .sheet(isPresented: notesBinding) {
            NotesSheet(controller: controller)
        }
        // No Figma motion: follow the keyboard with a short snap rather than jumping
        .animation(Self.chromeAnimation, value: controller.keyboardTop)
        // The bar's count ("2 notes") follows pins saved and removed
        .animation(.snappy(duration: 0.2), value: controller.annotations)
    }

    private var notesBinding: Binding<Bool> {
        Binding(
            get: { controller.isShowingNotes },
            set: { [controller] isShowing in if !isShowing { controller.closeNotes() } }
        )
    }

    /// Which chrome shows, for the swap animation: the case without its payload (a submit-state or
    /// count change isn't a swap), plus the open pin, so moving to another pin swaps the card too.
    private var chromeKind: ChromeKind {
        switch controller.chrome {
        case .replying: .replying
        case .composing: .composing(controller.draft?.annotation.id)
        case .review: .review
        }
    }

    private enum ChromeKind: Hashable {
        case replying, composing(UUID?), review
    }

    /// On iOS 26 the glass itself materializes and dematerializes (`annotateGlass`), so the view only
    /// fades and the material carries the motion; before it, a short slide and scale from the bottom.
    private var swapTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        if #available(iOS 26.0, *) { return .opacity }
        return .offset(y: Self.swapOffset)
            .combined(with: .scale(scale: Self.swapScale, anchor: .bottom))
            .combined(with: .opacity)
    }

    /// The comment and reply cards slide in like the bar, but leave at once (design choice): by the
    /// time one goes, a send has already hidden it while the keyboard slid away (SendAfterKeyboard).
    private var cardTransition: AnyTransition {
        .asymmetric(insertion: swapTransition, removal: .identity)
    }
}

private struct ActiveOverlay: View {
    let controller: AnnotateController

    /// Top edge of the bottom chrome in screen points (BottomChrome measures it); the gradient starts
    /// here. Nil until the first layout pass.
    let chromeTop: CGFloat?

    /// Not in Figma (design choice): pins' badges scale up from their own center on a spring.
    static let badgeAppearance: AnyTransition = .scale(scale: 0.3).combined(with: .opacity)
        .animation(.spring(duration: 0.45, bounce: 0.35))
    /// The glow and frost's blue ↔ green crossfade when Claude starts or stops working.
    static let paletteChange: Animation = .easeInOut(duration: 0.8)

    var body: some View {
        let bounds = controller.bounds
        let openID = controller.draft?.annotation.id
        // Figma's composing frames show no badge for the pin being written: the open draft draws
        // its own marker from the live draft instead of its saved copy.
        let saved = controller.visibleAnnotations.filter { $0.id != openID }
        // After a Send that kept annotate mode open: the sent pins, with their progress badges
        let sent = controller.sentPinsOnScreen

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
            // and badge, so pins near the edge stay pure white. Green while Claude works (design
            // choice): one glow per palette, crossfading, so only one renders at rest
            ZStack {
                if controller.isAgentWorking {
                    ScreenGlow(palette: .working).transition(.opacity)
                } else {
                    ScreenGlow(palette: .idle).transition(.opacity)
                }
            }
            .frame(width: bounds.width, height: bounds.height)
            .allowsHitTesting(false)
            .animation(Self.paletteChange, value: controller.isAgentWorking)

            // Figma layer order: Overlay (dim + glow), then the gradient, then pins and chrome
            bottomFrost

            captureLayer

            ForEach(saved + sent) { annotation in
                PinMarker(
                    annotation: annotation,
                    strokes: annotation.sketchInScreenPoints,
                    bounds: bounds
                )
                // Saving swaps the open draft's marker for this one; a fade-in here blinked the
                // strokes out for a frame. Badges still animate
                .transition(.identity)
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
                .badgePlaced(at: OverlayPlacement.pinCenter(
                    for: pin.pinAnchorFrame,
                    radius: AnnotateStyle.badgeSize / 2,
                    in: bounds
                ))
                .transition(Self.badgeAppearance)
            }

            ForEach(sent) { pin in
                SentPinBadge(number: pin.index, mark: controller.sentPinMark(for: pin)) {
                    controller.openNotes()
                }
                .badgePlaced(at: OverlayPlacement.pinCenter(
                    for: pin.pinAnchorFrame,
                    radius: AnnotateStyle.badgeSize / 2,
                    in: bounds
                ))
                .transition(Self.badgeAppearance)
            }
        }
        // Screen-sized whatever a layer does: a layer wider than the screen made the window
        // re-center the overlay, shifting the frozen screen under the pins
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .animation(.snappy(duration: 0.2), value: controller.annotations)
        .animation(.snappy(duration: 0.2), value: sent.map(\.id))
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

    /// Blue frost behind the bottom chrome (Figma 9272:16849 composing / 9272:17105 review): full
    /// screen width, from the chrome stack's top (card, or hint line) down past the keyboard / home
    /// indicator to the screen's bottom edge. Until the chrome is measured it starts where the review
    /// bar's hint line sits, so it fades in with everything else instead of popping in a frame later.
    private var bottomFrost: some View {
        let bounds = controller.bounds
        let top = chromeTop ?? estimatedChromeTop
        return ZStack {
            if controller.isAgentWorking {
                BottomFrost(palette: .working).transition(.opacity)
            } else {
                BottomFrost(palette: .idle).transition(.opacity)
            }
        }
        .animation(Self.paletteChange, value: controller.isAgentWorking)
            .frame(width: bounds.width, height: max(bounds.maxY - top, 0))
            .offset(y: top)
            // Decoration only: drawing on the frozen screen behind it must keep working
            .allowsHitTesting(false)
    }

    /// The review bar's hint line top: the chrome annotate mode opens with.
    private var estimatedChromeTop: CGFloat {
        controller.screenChromeBottom - AnnotateController.barHeight - ToastView.hintGap - ToastView.hintHeight
    }
}

/// The frost behind the bottom chrome, made fluid (design choice; Figma draws one even gradient,
/// `from-[rgba(0,136,255,0)] to-[rgba(0,136,255,0.5)]`): a softer even wash plus a few soft blue blobs
/// that drift sideways at their own pace, so the color pools and thins along the bottom like liquid.
/// The whole thing fades to clear toward its top, as Figma's does. Blobs are elliptical gradients,
/// not blurred shapes, so moving them costs no blur per frame.
private struct BottomFrost: View {
    /// Blue normally, green while Claude works.
    let palette: GlowPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One drifting pool of color: where it rests (fractions of the frost's size), how big it is,
    /// how far and how fast it sways, and its color.
    private struct Blob {
        let x: CGFloat, y: CGFloat
        let width: CGFloat, height: CGFloat
        let sway: CGFloat
        let period: Double
        let phase: Double
        let color: Color
    }

    /// Strength of the even wash at the bottom edge; the blobs bring the peaks to about Figma's 0.5.
    private static let washOpacity: Double = 0.28
    /// Where the frost reaches full strength, from its top (the top fades in, like Figma's gradient).
    private static let fadeEnd: CGFloat = 0.6
    private var blobs: [Blob] { [
        Blob(x: 0.2, y: 0.85, width: 0.95, height: 1.1, sway: 0.18, period: 11, phase: 0,
             color: palette.main.opacity(0.42)),
        Blob(x: 0.65, y: 0.95, width: 0.8, height: 0.9, sway: 0.22, period: 8, phase: 2,
             color: palette.light.opacity(0.28)),
        Blob(x: 0.9, y: 0.75, width: 0.7, height: 1.0, sway: 0.16, period: 14, phase: 4,
             color: palette.deep.opacity(0.3))
    ] }

    var body: some View {
        TimelineView(.animation(minimumInterval: FluidMotion.frameInterval, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    LinearGradient(
                        colors: [palette.main.opacity(0), palette.main.opacity(Self.washOpacity)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    ForEach(blobs.indices, id: \.self) { index in
                        let blob = blobs[index]
                        let drift = blob.sway * CGFloat(sin(FluidMotion.angle(time, period: blob.period) + blob.phase))
                        Rectangle()
                            .fill(EllipticalGradient(colors: [blob.color, blob.color.opacity(0)]))
                            .frame(width: size.width * blob.width, height: size.height * blob.height)
                            .position(x: size.width * (blob.x + drift), y: size.height * blob.y)
                    }
                }
                .mask(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .white, location: Self.fadeEnd)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

/// The colors the edge glow and the frost are mixed from: Accents/Blue with cyan and indigo passages
/// normally, green with mint and teal while Claude works (design choice).
struct GlowPalette {
    let main: Color
    let light: Color
    let deep: Color

    static let idle = GlowPalette(
        main: Color(uiColor: .systemBlue), light: Color(uiColor: .systemCyan), deep: Color(uiColor: .systemIndigo)
    )
    static let working = GlowPalette(
        main: Color(uiColor: .systemGreen), light: Color(uiColor: .systemMint), deep: Color(uiColor: .systemTeal)
    )
}

/// Shared clock math for the fluid glow and frost.
private enum FluidMotion {
    /// They drift slowly, so 30 fps is plenty and halves the work of the display's full rate.
    static let frameInterval: TimeInterval = 1.0 / 30

    /// `time` as an angle in radians, one full turn per `period` seconds. Reduced first, so the
    /// reference-date seconds don't lose precision in the trig.
    static func angle(_ time: TimeInterval, period: Double) -> Double {
        (time.truncatingRemainder(dividingBy: period) / period) * 2 * .pi
    }
}

private extension View {
    /// Places a pin badge by its center in the overlay's top-leading ZStack: a zero-size anchor sits
    /// on the center through alignment guides, and the badge rides in its overlay. A scale transition
    /// pivots on the anchor, so the badge grows from its own center (`.position` fills the screen and
    /// `.offset` moves only the drawing, and with either it flew in). The overlay takes no layout
    /// room, so a badge on the screen's edge can't widen the ZStack: when the badge's own hit frame
    /// was laid out there, a pin at the edge pushed it past the screen and the whole overlay shifted.
    func badgePlaced(at center: CGPoint) -> some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay { self }
            .alignmentGuide(.leading) { _ in -center.x }
            .alignmentGuide(.top) { _ in -center.y }
    }
}

extension Annotation {
    /// Where the numbered badge attaches: on the spot the user tapped to pick an element, just beside
    /// a spot, a sketch's own stroke corner, or a legacy region's outer top-trailing corner.
    var pinAnchorFrame: CGRect {
        switch kind {
        case .point:
            // Derived, no Figma row: SpotMarker.size / 2 (ring radius 9) plus badgeSize / 2 (12),
            // along the 45° diagonal, so the ring and the badge touch without overlapping
            let offset = AnnotateStyle.spotBadgeOffset
            return CGRect(x: anchor.x + offset, y: anchor.y - offset, width: 0, height: 0)
        case .sketch:
            // Figma puts the badge on the strokes' own corner (9257:13566), not the padded frame's
            // (9257:13562). Read from the strokes rather than undoing the padding: at a screen edge
            // the padded frame was clipped, and a thin stroke there left less than the padding to
            // undo, a null rect that sent the badge to the bottom-trailing corner
            return BundleRenderer.strokeBounds(sketchInScreenPoints) ?? frame.cgRect
        case .element:
            // Owner request 2026-10-30: the badge sits where the user tapped, not on the box's corner
            // (Figma 9257:13570): a block can be large, and its corner far from what was tapped
            return CGRect(origin: anchor.cgPoint, size: .zero)
        case .region:
            // Badge center on the box's outer corner (Figma 9257:13564 corner = 9257:13570 center);
            // the box is the frame grown by the outset, matching PinMarker
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
        // An element box is laid out at its own size before its offset, so a full-width element
        // plus the outset is wider than the screen; the screen-sized frame keeps it from widening
        // the overlay (which would re-center everything)
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
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

/// Blue glow along the screen's rounded edge while annotating (Figma 9257:13385: `rounded-[62px]`,
/// `shadow-[inset_0_0_62px_0_rgba(0,136,255,0.5)]`), made fluid (design choice): rather than one even
/// band, two edge bands of different depth are each lit by a slowly turning ring of uneven blues, in
/// opposite directions, so the glow swells, thins and runs along the edge like liquid. SwiftUI has no
/// inset shadow, so each band is a wide stroke blurred and masked back inside the screen shape. The
/// bands never change; only the light behind them turns. Reduce Motion holds the light still.
private struct ScreenGlow: View {
    /// Blue normally, green while Claude works.
    let palette: GlowPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The deeper band reaches about twice Figma's 62pt into the screen, faintly.
    private static let deepWidth: CGFloat = 140
    /// Seconds per turn: the two rings turn at different paces and in opposite directions, so where
    /// they overlap keeps changing instead of the whole pattern just spinning.
    private static let nearPeriod: Double = 14
    private static let deepPeriod: Double = 9

    /// Around the near band (Figma's 62pt glow): Accents/Blue swelling past Figma's 0.5 and thinning
    /// well below it, with cyan and indigo passages. The ring wraps, so it ends where it starts.
    private var nearStops: [Gradient.Stop] { [
        .init(color: palette.main.opacity(0.7), location: 0),
        .init(color: palette.light.opacity(0.25), location: 0.13),
        .init(color: palette.main.opacity(0.55), location: 0.27),
        .init(color: palette.deep.opacity(0.18), location: 0.41),
        .init(color: palette.main.opacity(0.75), location: 0.56),
        .init(color: palette.light.opacity(0.35), location: 0.7),
        .init(color: palette.main.opacity(0.2), location: 0.85),
        .init(color: palette.main.opacity(0.7), location: 1)
    ] }
    /// Around the deep band: a few faint pools that reach further in, clear in between.
    private var deepStops: [Gradient.Stop] { [
        .init(color: palette.main.opacity(0.3), location: 0),
        .init(color: .clear, location: 0.18),
        .init(color: palette.deep.opacity(0.28), location: 0.37),
        .init(color: .clear, location: 0.55),
        .init(color: palette.light.opacity(0.3), location: 0.72),
        .init(color: .clear, location: 0.88),
        .init(color: palette.main.opacity(0.3), location: 1)
    ] }

    var body: some View {
        TimelineView(.animation(minimumInterval: FluidMotion.frameInterval, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Self.ring(deepStops, turn: -FluidMotion.angle(time, period: Self.deepPeriod))
                    .mask(EdgeBand(width: Self.deepWidth))
                Self.ring(nearStops, turn: FluidMotion.angle(time, period: Self.nearPeriod))
                    .mask(EdgeBand(width: AnnotateStyle.glowBlur))
            }
        }
    }

    private static func ring(_ stops: [Gradient.Stop], turn: Double) -> some View {
        AngularGradient(stops: stops, center: .center, angle: .radians(turn))
    }
}

/// A soft band just inside the screen's rounded edge, opaque at the edge and fading inward over about
/// `width`: CSS `inset 0 0 <width>px`, as the area just outside the edge blurred inward (σ ≈ width / 2)
/// and clipped to the screen. Used as a mask; it never changes, so it renders once into one layer.
private struct EdgeBand: View {
    let width: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AnnotateStyle.screenCornerRadius, style: .continuous)
        shape
            .inset(by: -width / 2)
            .stroke(Color.white, lineWidth: width)
            .blur(radius: width / 2)
            .mask(shape)
            .drawingGroup()
    }
}
#endif
