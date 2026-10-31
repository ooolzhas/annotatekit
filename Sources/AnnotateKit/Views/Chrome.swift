// Shared overlay chrome for the redesigned annotate mode (Figma group
// 9257:13754): the 44pt round icon button every surface uses, the shared chrome button style
// (press feedback only, no disabled dimming), the glass helper, the 28pt blue pin markers (number,
// the sent pin's spinner or outcome glyph, and the open draft's +; 9378:6116 / 9378:6440 / 9378:5659),
// the status indicator dot with its pulsing wave (9378:5495), white sketch strokes, and the
// review bar shown when no pin is open (9276:27550: back, the note count and ↑, each its own glass
// shape; the count opens the notes sheet). Also owns the hint
// line drawn above that bar (9272:17120 / 17213 / 17307, 9276:28045), which says how to annotate or
// whether an agent is connected, and narrates a Send with the seconds since it started
// (9273:18004 / 18099 / 18194); its copy and dot come from `ReviewHint` in AnnotateCore. It is a label,
// never a button (the notes sheet lists the results); its dot turns orange (`ReviewHint.Dot.attention`)
// when the agent asked about a pin. Also owns the launcher pill (9265:14439 / 9265:14691): a Liquid Glass capsule
// docked above the home indicator (Liquid Glass, design choice) whose title narrates the last Send ("Annotate", "4 notes
// sent", …) so delivery progress needs no separate toast or ring, with a connection dot showing
// whether an agent is listening. The toast below predates the redesign and now only carries
// in-mode messages.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI

// MARK: - Round icon button

/// 44pt circle with an SF Symbol, the label of every round button in the Figma chrome
/// (9257:13394…, 9257:13555, 9257:13559).
struct CircleIcon: View {
    enum Style { case plain, dimmed, prominent }

    let systemName: String
    var style: Style = .plain

    /// Figma circle buttons are 44×44 (9257:13394…).
    static let size: CGFloat = 44
    /// Figma fill `rgba(0,0,0,0.05)`; `.primary` keeps it visible in dark mode.
    static let fillOpacity: Double = 0.05
    /// Figma `opacity-25` on the ↑ glyph while the comment is empty (9276:27117); also the review
    /// bar's ↑ with nothing to send (derived).
    static let dimmedOpacity: Double = 0.25

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(glyphColor)
            .opacity(style == .dimmed ? Self.dimmedOpacity : 1)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(fillColor))
    }

    private var glyphColor: Color {
        switch style {
        case .plain, .dimmed: .primary
        case .prominent: .white
        }
    }

    private var fillColor: Color {
        switch style {
        case .plain, .dimmed: Color.primary.opacity(Self.fillOpacity)
        case .prominent: AnnotateStyle.action
        }
    }
}

struct CircleIconButton: View {
    let systemName: String
    var style: CircleIcon.Style = .plain
    /// Overrides the per-symbol VoiceOver name when one symbol means different things.
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleIcon(systemName: systemName, style: style)
                .contentShape(Circle())
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel(label ?? Self.accessibilityLabel(for: systemName))
    }

    /// Symbols are the only label these buttons carry, so VoiceOver gets a spoken name.
    private static func accessibilityLabel(for systemName: String) -> String {
        switch systemName {
        case "xmark": "Close"
        case "chevron.left": "Back"
        case "trash": "Clear all"
        case "arrow.up": "Save comment"
        case "paperclip": "Attach image"
        case "arrow.uturn.backward": "Undo stroke"
        case "arrow.uturn.forward": "Redo stroke"
        default: systemName
        }
    }
}

/// Button style for every chrome button. Unlike `.plain` it ignores `isEnabled`: Figma dims only
/// the glyph (opacity-50) and keeps the 5% fill, so disabled visuals come solely from
/// `CircleIcon.Style.dimmed` or an explicit opacity. Callers still apply `.disabled(...)` for
/// semantics and VoiceOver.
struct ChromeButtonStyle: ButtonStyle {
    /// Press feedback is not in the Figma file; this is our choice so taps feel acknowledged.
    static let pressedOpacity: Double = 0.6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
    }
}

// MARK: - Leaving a card

/// Leaving the comment or reply card with the keyboard up (send or cancel): the card first lets go of
/// the keyboard, and `leave` runs once the keyboard starts sliding away, taking the card out so it
/// shrinks and fades in place while the bar rises from below (`BottomChrome.swapTransition`).
/// Taking the field out while it still held the keyboard made iOS drop the keyboard without its
/// slide; once focus is gone the slide survives. The card takes no touches in between. Callers run
/// the action directly when no keyboard is up.
struct LeaveAfterKeyboard: ViewModifier {
    /// What leaving does (save, send, discard, cancel); nil while the card stays.
    @Binding var leave: (() -> Void)?

    /// If iOS never reports the keyboard going, the card leaves anyway after this; longer than the
    /// keyboard's own slide.
    static let timeout: Duration = .milliseconds(600)

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(leave == nil)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                finish()
            }
            .task(id: leave != nil) {
                guard leave != nil else { return }
                try? await Task.sleep(for: Self.timeout)
                finish()
            }
    }

    private func finish() {
        guard let action = leave else { return }
        leave = nil
        // A turn later: iOS posts the will-hide while the field is still letting go of focus, and
        // taking the field out inside that call dropped the keyboard without its slide
        DispatchQueue.main.async { action() }
    }
}

// MARK: - Glass

extension View {
    /// Liquid Glass on iOS 26 (Xcode 26 toolchain), regular material before.
    /// The compiler check keeps the package building on older Xcode, where `glassEffect` is unknown.
    /// `interactive` makes the glass react to touch (the system's press shimmer and flex), for
    /// surfaces people press on: the review bar's buttons and the comment card. `tint` colors the
    /// glass (the review bar's ↑, Figma 9276:27565 Tint); before iOS 26 it is a solid fill.
    /// On iOS 26 the glass materializes as its view is inserted and dematerializes as it leaves
    /// (design choice): the material condenses in or melts away rather than the shape sliding.
    @ViewBuilder
    func annotateGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(annotateGlassStyle(interactive: interactive, tint: tint), in: shape)
                .glassEffectTransition(.materialize)
        } else {
            self.annotateGlassFallback(in: shape, tint: tint)
        }
        #else
        self.annotateGlassFallback(in: shape, tint: tint)
        #endif
    }

    @ViewBuilder
    private func annotateGlassFallback<S: Shape>(in shape: S, tint: Color?) -> some View {
        if let tint {
            self.background(tint, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
private func annotateGlassStyle(interactive: Bool, tint: Color?) -> Glass {
    let glass = tint.map { Glass.regular.tint($0) } ?? .regular
    return interactive ? glass.interactive() : glass
}
#endif

// MARK: - Pins

/// What a pin's marker shows. Each pin keeps one marker through every state, so going from one to
/// the next swaps only the glyph (and the fill, when it differs), never the marker itself.
enum PinFace: Equatable {
    /// The pin's comment card is open: + for a pin being created (Figma 9378:5659), a pencil for a
    /// saved pin being edited (9378:5178).
    case drafting(isNew: Bool)
    /// Saved, waiting for a Send: its number (9378:6116).
    case saved
    /// Sent, while the Send's pins stay on screen (9276:28552): number, spinner or outcome glyph.
    case sent(SentPinMark)
}

/// A pin's marker at its anchor (Figma 9378:6116 Marker): the 28pt marker with a white glyph that
/// follows `face`. Saved pins reopen on tap, sent pins open the notes sheet, and the open pin's
/// marker takes no taps (its card is where it's edited). OverlayRoot keys it by the pin, so saving,
/// reopening and sending change the glyph in place: it scales and fades between glyphs, and the
/// fill crossfades when the new face has another color (blue → green on resolve).
struct PinBadge: View {
    let number: Int
    let face: PinFace
    let action: () -> Void

    /// The HIG's 44pt minimum around the 28pt marker, so markers are easy to hit on a phone.
    static let hitSize: CGFloat = 44
    /// Not in Figma (no motion context): the glyph swap and the fill crossfade.
    static let changeAnimation: Animation = .snappy(duration: 0.25)
    /// Figma 9276:27955: SF Pro Bold 12, the notes sheet's outcome glyph (the marker's glyphs are
    /// 15pt semibold, `MarkerGlyph`).
    static let listGlyphSize: CGFloat = 12

    var body: some View {
        Button(action: action) {
            ZStack {
                glyph
                    // A new identity per glyph, so the swap runs the transition; the same glyph in a
                    // new face (saved → sent, both numbered) stays put
                    .id(glyphKey)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            .modifier(BadgeShape(fill: fill))
            .animation(Self.changeAnimation, value: face)
        }
        .buttonStyle(ChromeButtonStyle())
        .allowsHitTesting(!isDrafting)
        .accessibilityHidden(isDrafting)
        .accessibilityLabel("Pin \(number)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
    }

    private var isDrafting: Bool {
        if case .drafting = face { return true }
        return false
    }

    @ViewBuilder
    private var glyph: some View {
        switch face {
        case .drafting(let isNew):
            MarkerGlyph(systemName: isNew ? "plus" : "pencil")
        case .saved, .sent(.number):
            BadgeNumber(number: number)
        case .sent(.progress):
            // Figma draws SF Symbols' progress.indicator in white; the system spinner is the same glyph, animated
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
        case .sent(.symbol(let name, _)):
            MarkerGlyph(systemName: name)
        }
    }

    /// Which glyph shows, for the swap: + / pencil / the number / spinner / a symbol.
    private var glyphKey: String {
        switch face {
        case .drafting(let isNew): isNew ? "plus" : "pencil"
        case .saved, .sent(.number): "number \(number)"
        case .sent(.progress): "progress"
        case .sent(.symbol(let name, _)): name
        }
    }

    /// The marker's fill behind the white glyph. Figma: Accents/Blue while open, saved, numbered or
    /// spinning (9378:6116), green for resolved (9378:6440). The other outcomes have no Figma frame
    /// (derived): gray for dismissed, orange for a question, matching the notes sheet.
    private var fill: Color {
        guard case .sent(.symbol(_, let tone)) = face else { return AnnotateStyle.pinFill }
        switch tone {
        case .neutral: return AnnotateStyle.pinFill
        case .success: return AnnotateStyle.pinResolvedFill
        case .muted: return Color(uiColor: .systemGray)
        case .attention: return Color(uiColor: .systemOrange)
        }
    }

    private var accessibilityValue: String {
        guard case .sent(let mark) = face else { return "" }
        switch mark {
        case .number: return "Sent"
        case .progress: return "In progress"
        case .symbol(let name, _):
            switch name {
            case "checkmark": return "Resolved"
            case "questionmark": return "Question"
            case "xmark": return "Dismissed"
            default: return name
            }
        }
    }

    private var accessibilityHint: String {
        if case .sent = face { return "Show the notes" }
        return ""
    }
}

/// Every marker glyph's type: SF Pro Semibold 15, white (Figma Subheadline/Emphasized, 9378:6116).
private enum MarkerType {
    static let size: CGFloat = 15
    static let weight: Font.Weight = .semibold
}

/// The marker's number: white, tabular so 9 → 10 keeps its center (Figma 9378:6116).
private struct BadgeNumber: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: MarkerType.size, weight: MarkerType.weight))
            .monospacedDigit()
            .foregroundStyle(.white)
    }
}

/// An SF Symbol on the marker: white, the number's type (Figma 9378:6440 checkmark, 9378:5659 plus).
private struct MarkerGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: MarkerType.size, weight: MarkerType.weight))
            .foregroundStyle(.white)
    }
}

/// The marker's disc (Figma 9378:6122 Marker): `fill`, a soft-light white sheen that brightens toward
/// the bottom, a 1pt soft-light rim that brightens toward the top, and a soft drop shadow (y 4,
/// blur 8, 15%). SwiftUI has no per-paint blend modes, so the sheen and the rim are layers of their
/// own, blended inside one compositing group: they mix with the fill only, never with the dimmed
/// screen behind the marker.
private struct MarkerCircle: View {
    let fill: Color

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle()
                .fill(LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(AnnotateStyle.pinSheenOpacity)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .blendMode(.softLight)
            // Inside the edge, as Figma's INSIDE stroke
            Circle()
                .strokeBorder(LinearGradient(
                    colors: [.white.opacity(AnnotateStyle.pinRimOpacity), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                ), lineWidth: AnnotateStyle.pinBorderWidth)
                .blendMode(.softLight)
        }
        // The sheen and rim blend with the fill only, and the shadow falls from the finished disc
        .compositingGroup()
        .shadow(color: .black.opacity(AnnotateStyle.pinShadowOpacity), radius: AnnotateStyle.pinShadowRadius,
                x: 0, y: AnnotateStyle.pinShadowY)
    }
}

/// The marker at `AnnotateStyle.badgeSize` behind a pin's glyph, inside a larger square that takes the taps.
private struct BadgeShape: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .frame(width: AnnotateStyle.badgeSize, height: AnnotateStyle.badgeSize)
            .background(MarkerCircle(fill: fill))
            .frame(width: PinBadge.hitSize, height: PinBadge.hitSize)
            .contentShape(Rectangle())
    }
}

/// Pen strokes as Figma draws them: white, 4pt, round caps (9257:13562).
struct SketchStrokes: View {
    let strokes: [Stroke]
    var color: Color = AnnotateStyle.marker
    var lineWidth: CGFloat = AnnotateStyle.sketchLineWidth

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                context.stroke(
                    Path(SketchPath.path(for: stroke)),
                    with: .color(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

// MARK: - Review bar

/// Bottom bar while no pin is open (Figma 9276:27550): a back chevron that keeps the notes, the note
/// count, and ↑, each its own 52pt glass shape 8pt apart. The count is a button that opens the notes
/// sheet (design choice), where notes open, delete and clear. ↑ is tinted blue while there is
/// something to send, and VoiceOver calls it Save while no agent listens. Fills the width it is
/// given; OverlayRoot positions it. State comes from `controller.chrome`, `reviewTitle` and
/// `reviewHint`, never from `annotations`.
struct ReviewBar: View {
    let controller: AnnotateController

    /// Figma 9276:27550 `gap-[8px]`.
    static let spacing: CGFloat = 8
    /// Count text inset inside its capsule, so a long title scales down before touching the ends
    /// (Figma centers "4 notes" in a 214pt capsule; derived).
    static let countPadding: CGFloat = 16

    var body: some View {
        let canSend = controller.chrome.canSend

        // One glass group (design choice): pressing one piece makes it swell into its neighbours
        AnnotateGlassGroup(spacing: Self.spacing) {
        HStack(spacing: Self.spacing) {
            // A chevron, not ×, because leaving annotate mode keeps the notes (9276:27551)
            BarIconButton(systemName: "chevron.left", label: "Back") { controller.stop() }

            // 9276:27556 — SF Pro Medium 17 / 22, centered in a capsule that takes the rest of the row
            Button {
                controller.openNotes()
            } label: {
                Text(controller.reviewTitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, Self.countPadding)
                    .frame(maxWidth: .infinity)
                    .frame(height: AnnotateController.barHeight)
                    .annotateGlass(in: Capsule(), interactive: true)
                    // Interactive glass in a button label needs an explicit shape to take taps
                    .contentShape(Capsule())
            }
            .buttonStyle(ChromeButtonStyle())
            .accessibilityHint("Show the notes")

            // 9276:27561 — white ↑ on blue-tinted glass; plain glass and a dimmed glyph with nothing to send
            BarIconButton(
                systemName: "arrow.up",
                label: controller.reviewHint.actionTitle,
                tint: canSend ? AnnotateStyle.action : nil,
                isDimmed: !canSend
            ) {
                controller.send(keepAnnotating: true)
            }
            .disabled(!canSend)
        }
        }
        .frame(height: AnnotateController.barHeight)
        // Glass alone isn't hit-testable; taps in the gaps must not reach the frozen screen
        .contentShape(Rectangle())
    }
}

/// Glass shapes that react to each other: on iOS 26 a `GlassEffectContainer`, whose pieces stay
/// apart at rest (gaps no smaller than `spacing`) and blend as a pressed one swells toward the next;
/// before it, the content as is.
struct AnnotateGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// A 52pt glass circle around one symbol (Figma 9276:27551 / 9276:27561, SF Pro Medium 17 glyph).
/// With `tint` the glass takes that color and the glyph turns white.
private struct BarIconButton: View {
    let systemName: String
    let label: String
    var tint: Color?
    var isDimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint == nil ? Color.primary : .white)
                .opacity(isDimmed ? CircleIcon.dimmedOpacity : 1)
                .frame(width: AnnotateController.barHeight, height: AnnotateController.barHeight)
                .annotateGlass(in: Circle(), interactive: true, tint: tint)
                // Interactive glass in a button label needs an explicit shape to take taps
                .contentShape(Circle())
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel(label)
    }
}

/// The hint line above the review bar (9272:17120 / 17213 / 17307, 9276:28045): an optional status dot
/// and one line of white text, a headline with an optional dimmed detail ("Agent offline", "Notes
/// will be saved"). While a Send is in flight (9273:18004 / 18099 / 18194) it also shows the
/// time since the Send, ticking once a second. Copy, dot and whether the elapsed shows come from
/// `ReviewHint`, so the view never decides which hint shows; OverlayRoot places it 16pt above the bar.
/// A label only: touches pass through it to the frozen screen.
struct ReviewHintLine: View {
    let hint: ReviewHint
    /// When the current Send started (`controller.deliveryStartedAt`); nil hides the elapsed.
    let startedAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Figma `gap-[6px]` between the dot and the text (9276:27745).
    static let spacing: CGFloat = 6
    /// Figma `gap-[4px]` between the headline and what follows it, detail or elapsed (9276:27747).
    static let textSpacing: CGFloat = 4
    /// Figma Colors/Green #34C759, which is systemGreen in light mode.
    static let connectedColor = Color(uiColor: .systemGreen)
    /// Figma Colors/Red #FF383C (9378:6738, and the launcher's 9378:5495), which is systemRed in
    /// light mode.
    static let offlineColor = Color(uiColor: .systemRed)
    /// No Figma: the agent asked about a pin. Orange, matching the question badge in the notes sheet
    /// and the dot on the reply card, so the three read as one signal.
    static let attentionColor = Color(uiColor: .systemOrange)
    /// Figma `text-shadow 0 2 4 rgba(0,0,0,0.25)`; SwiftUI's radius is about half the CSS blur.
    /// It keeps white text legible over a light frozen screen.
    static let shadowOpacity: Double = 0.25
    static let shadowRadius: CGFloat = 2
    static let shadowY: CGFloat = 2
    /// Not in Figma (design choice): a new line rises in from below, blurred and faded, while the old
    /// one leaves upward the same way, e.g. when the gestures hint yields to "Claude connected".
    static let changeAnimation: Animation = .smooth(duration: 0.45)
    /// How far the swapping lines travel, and how blurred they start and end.
    static let swapOffset: CGFloat = 8
    static let swapBlur: CGFloat = 4
    /// The elapsed counts whole seconds ("1s", "2s", 9273:18007 / 18102), so it ticks once a second.
    static let tickInterval: TimeInterval = 1
    /// Not in Figma: the digit roll on each tick, well inside the second between ticks.
    static let tickAnimation: Animation = .snappy(duration: 0.3)
    /// The detail and the elapsed sit at half the headline's strength (Figma 9276:27749 / 9276:28049
    /// `opacity-50`).
    static let secondaryOpacity: Double = 0.5

    var body: some View {
        line
            // A label over the frozen screen; touches go to the annotate canvas beneath it
            .allowsHitTesting(false)
    }

    private var line: some View {
        // A ZStack so the outgoing and incoming lines overlap while they swap
        ZStack {
            Group {
                if hint.showsElapsed, let startedAt {
                    // The timeline lives only in this branch, so an idle hint line never ticks. Anchored
                    // to the Send, so ticks land on whole seconds after it and re-renders don't restart it
                    TimelineView(.periodic(from: startedAt, by: Self.tickInterval)) { context in
                        row(elapsed: ReviewHint.elapsedText(Int(context.date.timeIntervalSince(startedAt))))
                    }
                } else {
                    row(elapsed: nil)
                }
            }
            // A new headline is a new line and swaps in; the detail ("1/4") and the counter update
            // in place inside it
            .id(hint.headline)
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(HintSwap()))
        }
        .animation(Self.changeAnimation, value: hint.headline)
        // VoiceOver reads the text and the elapsed as one element, e.g. "Delivered to Claude, 1s"
        .accessibilityElement(children: .combine)
    }

    private func row(elapsed: String?) -> some View {
        HStack(spacing: Self.spacing) {
            if let dot = hint.dot {
                StatusIndicator(color: Self.color(for: dot))
            }
            HStack(spacing: Self.textSpacing) {
                Text(hint.headline)
                    .modifier(HintTextStyle())
                if let detail = hint.detail {
                    Text(detail)
                        .modifier(HintTextStyle())
                        .opacity(Self.secondaryOpacity)
                        // The detail gives way first when the line runs out of room
                        .layoutPriority(-1)
                }
                if let elapsed {
                    // Figma `"lnum" 1, "tnum" 1`: tabular lining figures, so the width holds as it counts
                    Text(elapsed)
                        .monospacedDigit()
                        .modifier(HintTextStyle())
                        .opacity(Self.secondaryOpacity)
                        // Each tick rolls the digits that changed (design choice)
                        .contentTransition(.numericText(countsDown: false))
                        .animation(Self.tickAnimation, value: elapsed)
                        // A long agent message truncates first; the elapsed always shows in full
                        .layoutPriority(1)
                }
            }
        }
    }

    /// Shared by the text and the elapsed (9273:18006 / 18007): SF Pro Medium 15 / 20, white, one
    /// line, Figma text-shadow. A fixed 15pt like the review bar's fixed 17pt, so the two never scale
    /// apart and the line stays 20pt tall (the 15pt default leading, no line spacing modifier).
    private struct HintTextStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(ReviewHintLine.shadowOpacity), radius: ReviewHintLine.shadowRadius,
                        x: 0, y: ReviewHintLine.shadowY)
        }
    }

    private static func color(for dot: ReviewHint.Dot) -> Color {
        switch dot {
        case .connected: connectedColor
        case .offline: offlineColor
        case .attention: attentionColor
        }
    }
}

/// The hint line's swap: the incoming line rises from `swapOffset` below, the outgoing one leaves
/// upward, both blurred and faded at the far end.
private struct HintSwap: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : ReviewHintLine.swapBlur)
            .offset(y: phase == .willAppear ? ReviewHintLine.swapOffset
                    : phase == .didDisappear ? -ReviewHintLine.swapOffset : 0)
    }
}

// MARK: - Launcher

/// The launcher pill (9265:14504): a Liquid Glass capsule whose title is `controller.launcherStatus.title`,
/// so it reads "Annotate" when idle (9265:14439) and narrates the last Send afterwards
/// (9265:14691 and the gap stages). The view never inspects the status itself; every case's copy
/// lives on `LauncherStatus` in AnnotateCore, so the wording stays testable on Linux.
struct LauncherButton: View {
    let controller: AnnotateController
    /// The status indicator is in the pill. Off the first time the pill shows in a run, so it can
    /// introduce itself; on for every later appearance.
    @State private var showsIndicator = LauncherButton.hasIntroducedIndicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The indicator has slid in once this run (owner request): the pill first reads just
    /// "Annotate", then the dot slides out leftward from behind the label and the pill widens to
    /// make room. Later appearances show it from the start.
    @MainActor private static var hasIntroducedIndicator = false
    /// How long the pill shows just its title first: past its own fade-in (`OverlayRoot.modeDuration`)
    /// with a beat to read it (design choice).
    static let indicatorDelay: Duration = .milliseconds(600)
    /// The slide and the widening, together (design choice; no Figma motion context).
    static let indicatorAnimation: Animation = .spring(duration: 0.5, bounce: 0.2)

    /// Figma's horizontal title padding (9289:1310 `px-[16px]`).
    static let horizontalPadding: CGFloat = 16
    /// Figma title: SF Pro Medium 17 (9289:1312). Its 22pt leading is the 17pt default, so no
    /// line spacing modifier.
    static let titleSize: CGFloat = 17
    /// Not in Figma (no motion context for either frame): title and width changes animate so the
    /// pill visibly grows into "4 notes sent" instead of jumping.
    static let statusAnimation: Animation = .snappy(duration: 0.25)
    /// Not in Figma: the pill springs to a new spot when the app's chrome pushes it (or lets it back).
    static let placementAnimation: Animation = .spring(duration: 0.4, bounce: 0.2)

    /// Gap between the status indicator (`StatusIndicator`, always shown, design choice; its color
    /// follows `controller.agentLink`) and the title. Figma 9378:5494 `gap-[8px]`.
    static let dotSpacing: CGFloat = 8

    var body: some View {
        let status = controller.launcherStatus
        let frame = controller.launcherFrame
        let maxWidth = max(controller.bounds.width - AnnotateController.launcherSideInset * 2, 0)
        let agent = controller.agent
        let link = controller.agentLink

        HStack(spacing: Self.dotSpacing) {
            if showsIndicator {
                ConnectionDot(link: link)
                    .transition(indicatorEntrance)
            }
            Text(status.title)
                .font(.system(size: Self.titleSize, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                // Above the dot, so the dot comes out from behind it
                .zIndex(1)
        }
            .task { await introduceIndicator() }
            .padding(.horizontal, Self.horizontalPadding)
            // The 44pt Figma height wins over its py-8 (22 + 16 = 38)
            .frame(height: AnnotateController.launcherHeight)
            // Liquid Glass (design choice) in place of Figma's solid black capsule: it reads over any
            // app screen in light and dark, and presses like the overlay's other glass
            .annotateGlass(in: Capsule(), interactive: true)
            .animation(Self.statusAnimation, value: status)
            .animation(Self.statusAnimation, value: link)
            // The controller's hit frame (OverlayWindow hit-tests it) must match the rendered width,
            // which changes with every title; measured here, before `.position` expands the view
            .onGeometryChange(for: CGSize.self) { $0.size } action: { controller.updateLauncherSize($0) }
            .contentShape(Capsule())
            // Tap only (owner request): the pill can't be dragged; avoidance places it
            .onTapGesture { controller.start() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status.title)
            .accessibilityValue(ConnectionDot.accessibilityValue(link: link, agent: agent))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Annotate the screen")
            // Caps the proposal so long titles truncate inside the capsule. It must come after the
            // measurement and the hit shape, or they would take the capped frame's width (a
            // maxWidth-only frame grows to the proposal) instead of the pill's
            .frame(maxWidth: maxWidth)
            .position(x: frame.midX, y: frame.midY)
            .animation(Self.placementAnimation, value: controller.launcherSpot)
    }

    /// The dot starts behind the label's first letters (one dot plus its gap to the right of its
    /// place) and slides left into place, fading in as it clears the label.
    private var indicatorEntrance: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: Self.dotSpacing + StatusIndicator.dotSize).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func introduceIndicator() async {
        guard !showsIndicator else { return }
        try? await Task.sleep(for: Self.indicatorDelay)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Self.indicatorAnimation) {
            showsIndicator = true
        }
        Self.hasIntroducedIndicator = true
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String
    let controller: AnnotateController

    /// The gap OverlayRoot leaves between the hint line and the review bar (`hintGap`, Figma 16pt).
    static let hintGap: CGFloat = 16
    /// The hint line's height: one line of fixed 15pt text (no Dynamic Type), whose default leading
    /// is 20pt (Figma 15 / 20).
    static let hintHeight: CGFloat = 20
    /// Not in Figma: the toast's bottom edge sits this far above the hint line's top.
    static let gapAboveHint: CGFloat = 12

    /// Where the bar sits, or would: the home indicator while the review bar shows, the keyboard-aware
    /// chrome bottom over a card.
    private var barBottom: CGFloat {
        if case .review = controller.chrome { return controller.screenChromeBottom }
        return controller.chromeBottom
    }

    var body: some View {
        let safe = controller.safeInsets
        let width = controller.bounds.width - safe.left - safe.right - 48
        // The review bar's bottom is AT `screenChromeBottom` (it ignores the keyboard) and the hint line
        // sits `hintGap` above it, so the toast's bottom edge goes `gapAboveHint` above the hint line's
        // top. Over a keyboard-docked card it measures from the keyboard instead, as before
        let toastBottom = barBottom - AnnotateController.barHeight
            - Self.hintGap - Self.hintHeight - Self.gapAboveHint

        HStack {
            Spacer(minLength: 0)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            Spacer(minLength: 0)
        }
        .frame(width: max(width, 0))
        // Positioned by its bottom edge: a frame from the overlay's top down to `toastBottom`,
        // bottom-aligned, so the toast's own height (one line or two) never needs guessing
        .frame(height: max(toastBottom, 0), alignment: .bottom)
        .offset(x: safe.left + 24)
        .allowsHitTesting(false)
    }
}
/// The launcher's connection dot, always shown (design choice): green while an agent listens, red
/// when nothing does (the hint line's two colors), yellow while the app catches up on a late
/// heartbeat. Push and pull agents read alike here; the hint line in annotate mode tells them apart.
struct ConnectionDot: View {
    let link: AgentLink

    /// No Figma frame for resyncing: between "listening" green and "nobody" red, and not the orange
    /// that marks a question waiting for the user.
    static let resyncingColor = Color(uiColor: .systemYellow)

    var body: some View {
        // Figma 9378:5495: the launcher's dot is the same Indicator as the hint line's
        StatusIndicator(color: Self.color(for: link))
    }

    static func color(for link: AgentLink) -> Color {
        switch link {
        case .active: ReviewHintLine.connectedColor
        case .resyncing: resyncingColor
        case .offline: ReviewHintLine.offlineColor
        }
    }

    /// VoiceOver value for the pill: the agent's own description while it listens.
    static func accessibilityValue(link: AgentLink, agent: AgentPresence?) -> String {
        switch link {
        case .active: agent?.accessibilityDescription ?? "Agent connected"
        case .resyncing: "Reconnecting to the agent"
        case .offline: "No agent connected"
        }
    }
}

// MARK: - Status indicator

/// Status dot with its pulsing wave (Figma 9378:5495 Indicator): an 8pt dot over a 16pt halo of the
/// same color at 15%. Lays out at the dot's 8pt (the halo overflows it, as Figma's `inset-[-50%]`).
struct StatusIndicator: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Figma "Circle" r4 inside the 8×8 Indicator frame (9378:5495 / 9378:6420).
    static let dotSize: CGFloat = 8
    /// Figma "Pulsing Wave" r8: twice the dot, centered on it.
    static let haloSize: CGFloat = 16
    /// Figma "Pulsing Wave" opacity 0.15.
    static let haloOpacity: Double = 0.15
    /// Not in Figma (no motion context; design choice from the layer's name): the wave breathes,
    /// shrinking to this scale (back to the dot's size) and swelling to Figma's 16pt. The dot itself
    /// stays solid. Reduce Motion holds the wave at scale 1, Figma's rest frame.
    static let haloRestScale: CGFloat = 0.5
    /// One half of the breath (in or out): a 2 s cycle, the same slow pace the old blinking dot had,
    /// so it reads as alive rather than alarming.
    static let haloHalfPeriod: Double = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: Self.dotSize, height: Self.dotSize)
            // In the background so the halo overflows the 8pt layout instead of widening it
            .background { halo }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var halo: some View {
        let wave = Circle()
            .fill(color)
            .opacity(Self.haloOpacity)
            .frame(width: Self.haloSize, height: Self.haloSize)
        if reduceMotion {
            wave
        } else {
            wave.phaseAnimator([false, true]) { content, isSwollen in
                content.scaleEffect(isSwollen ? 1 : Self.haloRestScale)
            } animation: { _ in
                .easeInOut(duration: Self.haloHalfPeriod)
            }
        }
    }
}
#endif
