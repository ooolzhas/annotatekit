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
// (`BottomChrome`, a separate view so it can) takes to rise into place and sink away; swaps between
// the review bar and the comment or reply card follow one rule on the same timing: the arriving
// piece rises from below like the chrome does, the leaving one shrinks and fades in place like the
// launcher pill; each pin keeps one marker whose glyph and fill change in place; the launcher pill scales down and fades about its own center, and
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
    fileprivate static let launcherHiddenScale: CGFloat = 0.8
    /// How far below its place the bottom chrome starts as annotate mode opens (and ends as it closes).
    fileprivate static let chromeEntranceOffset: CGFloat = 48
    /// How long entering and leaving annotate mode takes: the chrome's rise and the fade of the frozen
    /// screen, its dim, glow and frost all share it, so they arrive and leave together.
    static let modeDuration: Double = 0.3
    /// The chrome's rise and sink, and the launcher's scale.
    fileprivate static let modeAnimation: Animation = .snappy(duration: modeDuration)
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
        // Held in place while a leaving card waits for the keyboard (AnnotateController.holdCardDock)
        let dock = controller.cardDock
        let cardSides = dock.isKeyboardUp ? Self.keyboardInset : Self.screenInset
        let belowCard = max(bounds.maxY - dock.bottom, 0) + (dock.isKeyboardUp ? Self.keyboardInset : 0)

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
                        .transition(swapTransition)
                }
            case .composing:
                if let draft = controller.draft {
                    // No `.id` per pin: moving to another pin keeps the card and changes what changed
                    ComposerCard(controller: controller, draft: draft)
                        .padding(.horizontal, cardSides)
                        .padding(.bottom, belowCard)
                        .transition(swapTransition)
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
        // Bar ↔ card swaps share annotate mode's own timing, so they move like the launcher ↔ bar swap
        .animation(OverlayRoot.modeAnimation, value: chromeKind)
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

    /// Which chrome shows, for the swap animation: the case without its payload. A submit-state or
    /// count change isn't a swap, and neither is moving to another pin: the card stays and updates.
    private var chromeKind: ChromeKind {
        switch controller.chrome {
        case .replying: .replying
        case .composing: .composing
        case .review: .review
        }
    }

    private enum ChromeKind: Hashable {
        case replying, composing, review
    }

    /// Every swap between the bar and a card runs one way: the arriving piece rises into place from
    /// `chromeEntranceOffset` below, fading in, as the chrome does when annotate mode opens; the
    /// leaving one shrinks about its center and fades out where it is, as the launcher pill does
    /// (owner request). Glass alone barely fades, so the offset and the scale carry the motion.
    private var swapTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: OverlayRoot.chromeEntranceOffset).combined(with: .opacity),
            removal: .scale(scale: OverlayRoot.launcherHiddenScale).combined(with: .opacity)
        )
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
        // The open draft draws its own strokes and box from the live draft, and its marker comes from
        // it too (`pinMarkers`), so its saved copy is left out here.
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

            LiveStrokeLayer(controller: controller, size: bounds.size)

            // One marker per pin, keyed by the pin: saving the open pin, reopening a saved one and
            // sending only change its face (Figma 9378:5659 + while new, 9378:5178 pencil while
            // edited, 9378:6116 number, 9378:6440 outcome), so the glyph and fill change in place
            // instead of one marker leaving and another arriving
            ForEach(pinMarkers(saved: saved, sent: sent)) { marker in
                PinBadge(number: marker.number, face: marker.face) {
                    switch marker.face {
                    case .saved: controller.openExisting(marker.id)
                    case .sent: controller.openNotes()
                    case .drafting: break
                    }
                }
                .badgePlaced(at: OverlayPlacement.pinCenter(
                    for: marker.anchor,
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

    /// One pin's marker: the pin's id, its number, what it shows and where it attaches.
    private struct PinMarkerItem: Identifiable {
        let id: UUID
        let number: Int
        let face: PinFace
        let anchor: CGRect
    }

    /// Every marker on screen: saved pins, the last Send's pins, then the open pin. The open pin's
    /// saved copy is already out of `saved`, so a pin never has two markers; a sent pin that is also
    /// saved or open keeps the newer one.
    private func pinMarkers(saved: [Annotation], sent: [Annotation]) -> [PinMarkerItem] {
        var items = saved.map { PinMarkerItem(id: $0.id, number: $0.index, face: .saved, anchor: $0.pinAnchorFrame) }
        let draft = controller.draft
        let taken = Set(items.map(\.id) + [draft?.annotation.id].compactMap { $0 })
        items += sent.filter { !taken.contains($0.id) }.map {
            PinMarkerItem(id: $0.id, number: $0.index, face: .sent(controller.sentPinMark(for: $0)), anchor: $0.pinAnchorFrame)
        }
        if let draft {
            items.append(PinMarkerItem(
                id: draft.annotation.id,
                number: draft.annotation.index,
                face: .drafting(isNew: draft.isNew),
                anchor: Self.draftAnchor(draft)
            ))
        }
        return items
    }

    /// Where the open draft's marker attaches. A sketch reads the live strokes (already in screen
    /// points), since the draft's saved sketch lags the strokes being drawn; everything else uses the
    /// saved pin's anchor.
    private static func draftAnchor(_ draft: AnnotateController.Draft) -> CGRect {
        guard draft.annotation.kind == .sketch else { return draft.annotation.pinAnchorFrame }
        return OverlayPlacement.sketchPin(for: draft.strokes)
            .map { CGRect(origin: $0, size: .zero) } ?? draft.annotation.pinAnchorFrame
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
/// `from-[rgba(0,136,255,0)] to-[rgba(0,136,255,0.5)]`): a softer even wash plus a few soft blobs
/// that drift sideways at their own pace, so the color pools and thins along the bottom like liquid.
/// The whole thing fades to clear toward its top, as Figma's does. Drawn and moved by Core Animation
/// (`FluidFrostView`), so it costs the app nothing per frame.
private struct BottomFrost: View {
    /// Blue normally, green while Claude works.
    let palette: GlowPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Strength of the even wash at the bottom edge; the blobs bring the peaks to about Figma's 0.5.
    private static let washOpacity: CGFloat = 0.28
    /// Where the frost reaches full strength, from its top (the top fades in, like Figma's gradient).
    private static let fadeEnd: CGFloat = 0.6
    /// The drifting pools of color: where each rests and how big it is (fractions of the frost's
    /// size), how far and how fast it sways, and how strong it is.
    private static let blobs: [FluidFrostView.Blob] = [
        .init(x: 0.2, y: 0.85, width: 0.95, height: 1.1, sway: 0.18, period: 11, phase: 0, opacity: 0.42),
        .init(x: 0.65, y: 0.95, width: 0.8, height: 0.9, sway: 0.22, period: 8, phase: 2, opacity: 0.28),
        .init(x: 0.9, y: 0.75, width: 0.7, height: 1.0, sway: 0.16, period: 14, phase: 4, opacity: 0.3)
    ]

    var body: some View {
        FluidFrost(palette: palette, animates: !reduceMotion)
    }

    private struct FluidFrost: UIViewRepresentable {
        let palette: GlowPalette
        let animates: Bool

        func makeUIView(context: Context) -> FluidFrostView {
            FluidFrostView(blobs: BottomFrost.blobs, washOpacity: BottomFrost.washOpacity, fadeEnd: BottomFrost.fadeEnd)
        }

        func updateUIView(_ view: FluidFrostView, context: Context) {
            view.color = palette.color
            view.animates = animates
        }
    }
}

/// The one color the edge glow and the frost are mixed from, varied by opacity only: Accents/Blue
/// normally, the indicators' green while Claude works (owner request 2026-11-01: opacities, not
/// cyan/indigo or mint/teal hues).
@MainActor
struct GlowPalette {
    let color: UIColor

    static let idle = GlowPalette(color: UIColor(AnnotateStyle.action))
    static let working = GlowPalette(color: UIColor(ReviewHintLine.connectedColor))
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
    /// Where the numbered badge attaches: on the spot the user tapped to pick an element or held, on a
    /// sketch's first stroke 15% short of its end, or a legacy region's outer top-trailing corner.
    var pinAnchorFrame: CGRect {
        switch kind {
        case .point:
            // Owner request 2026-11-01: the pin itself marks the held spot, centered on it, with no
            // ring or dot of its own
            return CGRect(origin: anchor.cgPoint, size: .zero)
        case .sketch:
            // Owner request 2026-11-01 (Figma 9378:5659): the badge sits centered ON the first line, 15%
            // short of where it ends (more strokes never move it), rather than on the strokes' bounding corner. A zero-size rect, so
            // pinCenter clamps that point inside the screen. Falls back to the frame with no strokes
            if let point = OverlayPlacement.sketchPin(for: sketchInScreenPoints) {
                return CGRect(origin: point, size: .zero)
            }
            return frame.cgRect
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

/// The stroke under the finger. Its own view so it is the only reader of `liveStroke`: read in
/// ActiveOverlay's body, every drag sample re-ran that whole body (every pin's sketch placement and
/// badge) for one growing path.
private struct LiveStrokeLayer: View {
    let controller: AnnotateController
    let size: CGSize

    var body: some View {
        LiveStrokeShape(stroke: controller.liveStroke)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
    }
}

/// Draws the live stroke with a `CAShapeLayer`, which the render server rasterizes. A screen-sized
/// SwiftUI `Canvas` here re-rendered through Metal on the main thread for every drag sample (most of
/// the drawing cost in a profile). Same path (`SketchPath`) and style as `SketchStrokes`, which
/// still draws saved strokes: those don't change while the finger moves.
private struct LiveStrokeShape: UIViewRepresentable {
    let stroke: Stroke?

    func makeUIView(context: Context) -> StrokeLayerView {
        StrokeLayerView()
    }

    func updateUIView(_ view: StrokeLayerView, context: Context) {
        view.show(stroke)
    }
}

private final class StrokeLayerView: UIView {
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(shape)
        shape.fillColor = nil
        shape.strokeColor = UIColor(AnnotateStyle.marker).cgColor
        shape.lineWidth = AnnotateStyle.sketchLineWidth
        shape.lineCap = .round
        shape.lineJoin = .round
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutAnimation { shape.frame = bounds }
    }

    func show(_ stroke: Stroke?) {
        withoutAnimation { shape.path = stroke.map { SketchPath.path(for: $0) } }
    }

    /// A sublayer animates property changes implicitly; the path must follow the finger exactly.
    private func withoutAnimation(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}

/// Everything drawn for one pin except its badge: the element box (also used for legacy regions) and
/// the pen strokes in screen points. A hold pin draws nothing here: its badge marks the spot. Never
/// takes touches.
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
                SelectionBox()
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
            case .point, .sketch:
                // A hold pin is marked by its pin alone (centered on the spot); a sketch by its strokes
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

/// The box around a picked element (Figma 9378:6110 / 9378:6113 "Selection"): a faint white tint
/// lightening the element (`mix-blend-plus-lighter`), plus white brackets on its four corners only.
private struct SelectionBox: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AnnotateStyle.elementBoxRadius, style: .continuous)
                .fill(Color.white.opacity(AnnotateStyle.elementBoxTintOpacity))
                .blendMode(.plusLighter)
            // Figma's Corners SVG centers the 2pt stroke on the frame's edge, so no inset
            SelectionCorners(radius: AnnotateStyle.elementBoxCornerRadius)
                .stroke(
                    AnnotateStyle.marker,
                    style: StrokeStyle(lineWidth: AnnotateStyle.elementBoxLineWidth, lineCap: .round)
                )
        }
    }
}

/// Only the four corner arcs of a rounded rect laid on the rect's own edge (Figma 9378:6113
/// "Corners"): each runs from `radius` along one edge, round the corner, to `radius` along the other.
private struct SelectionCorners: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        // Clamped so a tiny element's arcs never cross each other (design choice)
        let r = max(min(radius, rect.width / 2, rect.height / 2), 0)
        var path = Path()
        guard r > 0 else { return path }
        // Each corner: start r along one edge, tangent at the corner, end r along the other
        func bracket(_ start: CGPoint, _ corner: CGPoint, _ end: CGPoint) {
            path.move(to: start)
            path.addArc(tangent1End: corner, tangent2End: end, radius: r)
        }
        bracket(CGPoint(x: rect.minX, y: rect.minY + r), CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.minX + r, y: rect.minY))
        bracket(CGPoint(x: rect.maxX - r, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + r))
        bracket(CGPoint(x: rect.maxX, y: rect.maxY - r), CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.maxX - r, y: rect.maxY))
        bracket(CGPoint(x: rect.minX + r, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY - r))
        return path
    }
}

/// Blue glow along the screen's rounded edge while annotating (Figma 9257:13385: `rounded-[62px]`,
/// `shadow-[inset_0_0_62px_0_rgba(0,136,255,0.5)]`), made fluid (design choice): rather than one even
/// band, two edge bands of different depth are each lit by a slowly turning ring of uneven color, in
/// opposite directions, so the glow swells, thins and runs along the edge like liquid. Each band is an
/// inset-shadow bitmap (`EdgeBandMask`). The bands never change; only the light behind them turns,
/// on Core Animation (`FluidRingsView`). Reduce Motion holds the light still.
private struct ScreenGlow: View {
    /// Blue normally, green while Claude works.
    let palette: GlowPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The rings, deep under near. Seconds per turn: they turn at different paces and in opposite
    /// directions, so where they overlap keeps changing instead of the whole pattern just spinning.
    private static let rings: [FluidRingsView.Ring] = [
        // The deeper band reaches about twice Figma's 62pt into the screen: a few faint pools, clear
        // in between
        .init(stops: [
            FluidStop(opacity: 0.3, location: 0),
            FluidStop(opacity: 0, location: 0.18),
            FluidStop(opacity: 0.28, location: 0.37),
            FluidStop(opacity: 0, location: 0.55),
            FluidStop(opacity: 0.3, location: 0.72),
            FluidStop(opacity: 0, location: 0.88),
            FluidStop(opacity: 0.3, location: 1)
        ], period: 9, clockwise: false, band: 140),
        // The near band (Figma's 62pt glow): the color swelling past Figma's 0.5 and thinning well
        // below it. The ring wraps, so it ends where it starts
        .init(stops: [
            FluidStop(opacity: 0.7, location: 0),
            FluidStop(opacity: 0.25, location: 0.13),
            FluidStop(opacity: 0.55, location: 0.27),
            FluidStop(opacity: 0.18, location: 0.41),
            FluidStop(opacity: 0.75, location: 0.56),
            FluidStop(opacity: 0.35, location: 0.7),
            FluidStop(opacity: 0.2, location: 0.85),
            FluidStop(opacity: 0.7, location: 1)
        ], period: 14, clockwise: true, band: AnnotateStyle.glowBlur)
    ]

    var body: some View {
        FluidRings(palette: palette, animates: !reduceMotion)
    }

    private struct FluidRings: UIViewRepresentable {
        let palette: GlowPalette
        let animates: Bool

        func makeUIView(context: Context) -> FluidRingsView {
            FluidRingsView(rings: ScreenGlow.rings)
        }

        func updateUIView(_ view: FluidRingsView, context: Context) {
            view.color = palette.color
            view.animates = animates
        }
    }
}

/// The edge band drawn once per screen size with Core Graphics and cached. It used to be a SwiftUI
/// blur (a band outside the edge, `blur(radius: width / 2)`, masked to the screen, `drawingGroup`):
/// on the first open after an install, building that blur's offscreen pipeline held the main thread
/// for ~250 ms, longer than the 0.3 s entrance, so the bar, dim and glow appeared already in place.
/// The bitmap is the same band (filled outside the edge, its shadow blurred inward and clipped to the
/// screen) at 1x: it is soft everywhere, so drawing it at the screen's scale would add nothing but
/// time.
@MainActor
enum EdgeBandMask {
    private struct Key: Hashable {
        let width: CGFloat
        let height: CGFloat
        let band: CGFloat
    }

    private static var cache: [Key: CGImage] = [:]

    static func image(size: CGSize, width: CGFloat) -> CGImage? {
        let key = Key(width: size.width, height: size.height, band: width)
        if let cached = cache[key] { return cached }
        guard let made = render(size: size, width: width) else { return nil }
        cache[key] = made
        return made
    }

    /// White at the edge fading to clear inward; alpha carries the mask.
    nonisolated static func render(size: CGSize, width: CGFloat) -> CGImage? {
        let pixelWidth = Int(size.width.rounded(.up)), pixelHeight = Int(size.height.rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0, width > 0,
              let context = CGContext(
                  data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let screen = CGRect(origin: .zero, size: size)
        let edge = UIBezierPath(roundedRect: screen, cornerRadius: AnnotateStyle.screenCornerRadius).cgPath
        let outer = UIBezierPath(
            roundedRect: screen.insetBy(dx: -width, dy: -width),
            cornerRadius: AnnotateStyle.screenCornerRadius + width
        ).cgPath
        let band = CGMutablePath()
        band.addPath(outer)
        band.addPath(edge)
        context.addPath(edge)
        context.clip()
        // A CG shadow's blur is about twice its Gaussian sigma, so `width` here is SwiftUI's
        // `blur(radius: width / 2)`. The band itself lies outside the clip; only its shadow lands
        context.setShadow(offset: .zero, blur: width, color: UIColor.white.cgColor)
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(band)
        context.fillPath(using: .evenOdd)
        return context.makeImage()
    }
}
#endif
