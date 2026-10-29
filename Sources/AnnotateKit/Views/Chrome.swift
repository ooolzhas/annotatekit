// Shared overlay chrome for the redesigned annotate mode (Figma PVX9n74hzo5BWauvymG141, group
// 9257:13754): the 44pt round icon button every surface uses, the shared chrome button style
// (press feedback only, no disabled dimming), the glass helper, the white number badge and the sent
// pin's progress badge (spinner, outcome glyph or number; 9276:28552), white sketch strokes, and the
// review bar shown when no pin is open (9276:27550: back, the note count and ↑, each its own glass
// shape; the count opens the notes sheet). Also owns the hint
// line drawn above that bar (9272:17120 / 17213 / 17307, 9276:28045), which says how to annotate or
// whether an agent is connected, and narrates a Send with the seconds since it started
// (9273:18004 / 18099 / 18194); its copy and dot come from `ReviewHint` in AnnotateCore. It is a label,
// never a button (the notes sheet lists the results); its dot turns orange (`ReviewHint.Dot.attention`)
// when the agent asked about a pin. Also owns the launcher pill (9265:14439 / 9265:14691): a solid capsule
// docked above the home indicator whose title narrates the last Send ("Annotate", "4 notes
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

// MARK: - Sending from a card

/// Sending from the comment or reply card (owner request): the card vanishes at once but stays in
/// place while its field lets go of the keyboard, and only once the keyboard has slid away does `send`
/// run and take the card out for real. Taking the field out with the keyboard still up made iOS drop
/// the keyboard without its slide. Callers send directly when no keyboard is up.
struct SendAfterKeyboard: ViewModifier {
    @Binding var isLeaving: Bool
    let send: () -> Void

    /// If iOS never reports the keyboard gone, the card leaves anyway after this; longer than the
    /// keyboard's own slide.
    static let timeout: Duration = .milliseconds(600)

    func body(content: Content) -> some View {
        content
            .opacity(isLeaving ? 0 : 1)
            .allowsHitTesting(!isLeaving)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                finish()
            }
            .task(id: isLeaving) {
                guard isLeaving else { return }
                try? await Task.sleep(for: Self.timeout)
                finish()
            }
    }

    private func finish() {
        guard isLeaving else { return }
        // Stays hidden through its own removal: un-hiding in the same update faded a ghost of the
        // card in under the arriving bar. The ↑ that started this only works when a send can go
        // through, so the card always leaves here.
        send()
    }
}

// MARK: - Glass

extension View {
    /// Liquid Glass on iOS 26 (Xcode 26 toolchain), regular material before.
    /// The compiler check keeps the package building on older Xcode, where `glassEffect` is unknown.
    /// `interactive` makes the glass react to touch (the system's press shimmer and flex), for
    /// surfaces people press on: the review bar's buttons and the comment card. `tint` colors the
    /// glass (the review bar's ↑, Figma 9276:27565 Tint); before iOS 26 it is a solid fill.
    @ViewBuilder
    func annotateGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(annotateGlassStyle(interactive: interactive, tint: tint), in: shape)
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

/// White numbered badge at a pin's top-trailing corner (9257:13566/13567); tap reopens the pin.
struct PinBadge: View {
    let number: Int
    let action: () -> Void

    /// Bigger than the 24pt dot so badges are easy to hit on a phone.
    static let hitSize: CGFloat = 40

    var body: some View {
        Button(action: action) {
            BadgeNumber(number: number)
                .modifier(BadgeShape())
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel("Pin \(number)")
    }
}

/// A sent pin's badge while the Send's pins stay on screen (Figma 9276:28552): the same white 24pt
/// badge holding a spinner while the agent has the pin (9276:27574), the outcome's glyph once it
/// reports one (9276:27954: green 12pt bold checkmark for resolved), or the number. Which one comes
/// from `SentPinMark`; tap opens the notes sheet.
struct SentPinBadge: View {
    let number: Int
    let mark: SentPinMark
    let action: () -> Void

    /// Figma 9276:27955: SF Pro Bold 12.
    static let glyphSize: CGFloat = 12
    /// Not in Figma (no motion context): the spinner turning into a checkmark pops rather than cuts.
    static let changeAnimation: Animation = .snappy(duration: 0.25)

    var body: some View {
        Button(action: action) {
            ZStack {
                switch mark {
                case .number:
                    BadgeNumber(number: number)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                case .progress:
                    // Figma draws SF Symbols' progress.indicator; the system spinner is the same glyph, animated
                    ProgressView()
                        .controlSize(.mini)
                        .tint(AnnotateStyle.badgeText)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                case .symbol(let name, let tone):
                    Image(systemName: name)
                        .font(.system(size: Self.glyphSize, weight: .bold))
                        .foregroundStyle(Self.color(for: tone))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .modifier(BadgeShape())
            .animation(Self.changeAnimation, value: mark)
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel("Pin \(number)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Show the notes")
    }

    private var accessibilityValue: String {
        switch mark {
        case .number: "Sent"
        case .progress: "In progress"
        case .symbol(let name, _):
            switch name {
            case "checkmark": "Resolved"
            case "questionmark": "Question"
            case "xmark": "Dismissed"
            default: name
            }
        }
    }

    /// Glyphs on the white badge: Figma Primitive/Green #34C759 (systemGreen) for resolved; the
    /// other tones match the notes sheet (derived).
    private static func color(for tone: PinOutcome.Tone) -> Color {
        switch tone {
        case .neutral: AnnotateStyle.badgeText
        case .success: Color(uiColor: .systemGreen)
        case .muted: Color(uiColor: .systemGray)
        case .attention: Color(uiColor: .systemOrange)
        }
    }
}

/// The badge's number: SF Pro Semibold 15, black (Figma 9257:13567 / 9276:28055).
private struct BadgeNumber: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(AnnotateStyle.badgeText)
    }
}

/// The white 24pt circle every pin badge draws, inside a larger square that takes the taps.
private struct BadgeShape: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: AnnotateStyle.badgeSize, height: AnnotateStyle.badgeSize)
            .background(Circle().fill(AnnotateStyle.marker))
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
/// sheet (owner request), where notes open, delete and clear. ↑ is tinted blue while there is
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

        // One glass group (owner request): pressing one piece makes it swell into its neighbours
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

    /// Figma `gap-[6px]` between the dot and the text (9276:27745).
    static let spacing: CGFloat = 6
    /// Figma `gap-[4px]` between the headline and what follows it, detail or elapsed (9276:27747).
    static let textSpacing: CGFloat = 4
    /// Figma dot 8×8 (9272:17214 / 9272:17308).
    static let dotSize: CGFloat = 8
    /// Figma Colors/Green #34C759, which is systemGreen in light mode.
    static let connectedColor = Color(uiColor: .systemGreen)
    /// Figma Primitive/Red #F8001A, exact: it is a primitive, not a semantic system red.
    static let offlineColor = Color(red: 248 / 255, green: 0, blue: 26 / 255)
    /// No Figma: the agent asked about a pin. Orange, matching the question badge in the notes sheet
    /// and the dot on the reply card, so the three read as one signal.
    static let attentionColor = Color(uiColor: .systemOrange)
    /// Figma `text-shadow 0 2 4 rgba(0,0,0,0.25)`; SwiftUI's radius is about half the CSS blur.
    /// It keeps white text legible over a light frozen screen.
    static let shadowOpacity: Double = 0.25
    static let shadowRadius: CGFloat = 2
    static let shadowY: CGFloat = 2
    /// Not in Figma (no motion context): the line crossfades when the hint changes, e.g. when the
    /// connection news yields to the gestures hint.
    static let changeAnimation: Animation = .snappy(duration: 0.25)
    /// The elapsed counts whole seconds ("1s", "2s", 9273:18007 / 18102), so it ticks once a second.
    static let tickInterval: TimeInterval = 1
    /// The detail and the elapsed sit at half the headline's strength (Figma 9276:27749 / 9276:28049
    /// `opacity-50`).
    static let secondaryOpacity: Double = 0.5

    var body: some View {
        line
            // A label over the frozen screen; touches go to the annotate canvas beneath it
            .allowsHitTesting(false)
    }

    private var line: some View {
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
        .animation(Self.changeAnimation, value: hint)
        // VoiceOver reads the text and the elapsed as one element, e.g. "Delivered to Claude, 1s"
        .accessibilityElement(children: .combine)
    }

    private func row(elapsed: String?) -> some View {
        HStack(spacing: Self.spacing) {
            if let dot = hint.dot {
                Circle()
                    .fill(Self.color(for: dot))
                    .frame(width: Self.dotSize, height: Self.dotSize)
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

// MARK: - Launcher

/// The launcher pill (9265:14504): a solid capsule whose title is `controller.launcherStatus.title`,
/// so it reads "Annotate" when idle (9265:14439) and narrates the last Send afterwards
/// (9265:14691 and the gap stages). The view never inspects the status itself; every case's copy
/// lives on `LauncherStatus` in AnnotateCore, so the wording stays testable on Linux.
struct LauncherButton: View {
    let controller: AnnotateController
    /// Vertical drag only: the pill stays centered, so a side-edge snap has nothing to do and the
    /// user can only lift it off an app's own bottom bar.
    @GestureState private var dragOffset: CGFloat = 0

    /// Figma's horizontal title padding (9265:14504 `px-[16px]`).
    static let horizontalPadding: CGFloat = 16
    /// Figma container `px-[8px]` (9265:14502): 8pt on each side caps the pill at `bounds.width - 16`,
    /// which is what a long agent message truncates against.
    static let containerInset: CGFloat = 8
    /// Figma title: SF Pro Medium 17 (9265:14505). Its 22pt leading is the 17pt default, so no
    /// line spacing modifier.
    static let titleSize: CGFloat = 17
    /// Drag threshold kept from the old launcher, so a tap with a little jitter still taps.
    static let dragThreshold: CGFloat = 8
    /// Not in Figma (no motion context for either frame): title and width changes animate so the
    /// pill visibly grows into "4 notes sent" instead of jumping.
    static let statusAnimation: Animation = .snappy(duration: 0.25)

    /// Figma is black on white in light mode. Dark mode has no frame, so the pair inverts through
    /// semantic colors: a fixed black pill would vanish into dark app UI.
    private static let fill = Color(uiColor: .label)
    private static let text = Color(uiColor: .systemBackground)
    /// Connection dot (no Figma frame): solid green when a Send starts an agent by itself, a ring
    /// when one is connected but only reads when asked, absent when nothing listens.
    static let dotSize: CGFloat = 7
    static let dotSpacing: CGFloat = 6

    var body: some View {
        let status = controller.launcherStatus
        let frame = controller.launcherFrame
        let maxWidth = max(controller.bounds.width - Self.containerInset * 2, 0)
        let agent = controller.agent

        HStack(spacing: Self.dotSpacing) {
            if let agent {
                ConnectionDot(mode: agent.mode, ringColor: Self.text)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(status.title)
                .font(.system(size: Self.titleSize, weight: .medium))
                .foregroundStyle(Self.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
            .padding(.horizontal, Self.horizontalPadding)
            // The 44pt Figma height wins over its py-8 (22 + 16 = 38)
            .frame(height: AnnotateController.launcherHeight)
            .background(Self.fill, in: Capsule())
            .animation(Self.statusAnimation, value: status)
            .animation(Self.statusAnimation, value: agent?.mode)
            // The controller's hit frame (OverlayWindow hit-tests it) must match the rendered width,
            // which changes with every title; measured here, before `.position` expands the view
            .onGeometryChange(for: CGSize.self) { $0.size } action: { controller.updateLauncherSize($0) }
            .contentShape(Capsule())
            .onTapGesture { controller.start() }
            .gesture(
                DragGesture(minimumDistance: Self.dragThreshold)
                    .updating($dragOffset) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        controller.moveLauncher(toCenterY: frame.midY + value.translation.height)
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status.title)
            .accessibilityValue(agent?.accessibilityDescription ?? "No agent connected")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Annotate the screen")
            // Caps the proposal so long titles truncate inside the capsule. It must come after the
            // measurement and the hit shape, or they would take the capped frame's width (a
            // maxWidth-only frame grows to the proposal) instead of the pill's
            .frame(maxWidth: maxWidth)
            .position(x: frame.midX, y: frame.midY + dragOffset)
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
/// The launcher's connection dot: filled when a Send will start the agent by itself, a ring when
/// the agent only reads sessions when asked.
struct ConnectionDot: View {
    let mode: AgentPresence.Mode
    /// The ring uses the pill's title color so it reads on both the light and the dark pill.
    let ringColor: Color

    var body: some View {
        Group {
            switch mode {
            case .push:
                Circle().fill(Color(uiColor: .systemGreen))
            case .pull:
                Circle().strokeBorder(ringColor.opacity(0.7), lineWidth: 1.5)
            }
        }
        .frame(width: LauncherButton.dotSize, height: LauncherButton.dotSize)
        .accessibilityHidden(true)
    }
}
#endif
