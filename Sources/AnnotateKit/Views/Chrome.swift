// Shared overlay chrome for the redesigned annotate mode (Figma PVX9n74hzo5BWauvymG141, group
// 9257:13754): the 44pt round icon button every surface uses, the shared chrome button style
// (press feedback only, no disabled dimming), the glass helper, the white number badge, white
// sketch strokes, and the review bar shown when no pin is open (9257:13549), whose trash asks for
// confirmation first. Also owns the launcher pill (9265:14439 / 9265:14691): a solid capsule
// docked above the home indicator whose title narrates the last Send ("Annotate", "4 comments
// sent", …) so delivery progress needs no separate toast or ring. The toast below predates the
// redesign and now only carries in-mode messages.

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
    /// Figma `opacity-50` on the ↑ glyph while the comment is empty (9257:13400); also the
    /// disabled Send pill in `.review(count: 0)` (contract gap value).
    static let dimmedOpacity: Double = 0.5

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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleIcon(systemName: systemName, style: style)
                .contentShape(Circle())
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel(Self.accessibilityLabel(for: systemName))
    }

    /// Symbols are the only label these buttons carry, so VoiceOver gets a spoken name.
    private static func accessibilityLabel(for systemName: String) -> String {
        switch systemName {
        case "xmark": "Close"
        case "trash": "Clear all"
        case "arrow.up": "Save comment"
        case "paperclip": "Attach image"
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

// MARK: - Glass

extension View {
    /// Liquid Glass on iOS 26 (Xcode 26 toolchain), regular material before.
    /// The compiler check keeps the package building on older Xcode, where `glassEffect` is unknown.
    /// `interactive` makes the glass react to touch (the system's press shimmer and flex), for
    /// surfaces people press on: the review bar and the comment card.
    @ViewBuilder
    func annotateGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }
}

// MARK: - Pins

/// White numbered badge at a pin's top-trailing corner (9257:13566/13567); tap reopens the pin.
struct PinBadge: View {
    let number: Int
    let action: () -> Void

    /// Bigger than the 24pt dot so badges are easy to hit on a phone.
    static let hitSize: CGFloat = 40

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AnnotateStyle.badgeText)
                .frame(width: AnnotateStyle.badgeSize, height: AnnotateStyle.badgeSize)
                .background(Circle().fill(AnnotateStyle.marker))
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChromeButtonStyle())
        .accessibilityLabel("Pin \(number)")
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

/// Bottom bar while no pin is open (9257:13549): ×, count, trash, Send. Fills the width it is
/// given; OverlayRoot positions it. State comes from `controller.chrome`, never from `annotations`.
struct ReviewBar: View {
    let controller: AnnotateController
    @State private var isConfirmingClear = false

    var body: some View {
        let chrome = controller.chrome
        let canSend = chrome.canSend
        let count: Int = if case .review(let count) = chrome { count } else { 0 }

        HStack(spacing: 16) {
            CircleIconButton(systemName: "xmark") { controller.stop() }
            Text(OverlayChrome.countTitle(count))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                CircleIconButton(systemName: "trash", style: canSend ? .plain : .dimmed) { isConfirmingClear = true }
                    .disabled(!canSend)
                    // Trash wipes every pin with no undo, so it asks first. Anchored to the button,
                    // it shows as a popover from the trash icon on iOS 26
                    .confirmationDialog(OverlayChrome.clearTitle(count), isPresented: $isConfirmingClear,
                                        titleVisibility: .visible) {
                        Button(OverlayChrome.clearAction, role: .destructive) { controller.clearAll() }
                    }
                Button {
                    controller.send(keepAnnotating: false)
                } label: {
                    Text(OverlayChrome.sendTitle)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: CircleIcon.size)
                        .background(AnnotateStyle.action, in: Capsule())
                }
                .buttonStyle(ChromeButtonStyle())
                .disabled(!canSend)
                // Flatten first so the label and capsule fade together, like a Figma layer opacity
                .compositingGroup()
                .opacity(canSend ? 1 : CircleIcon.dimmedOpacity)
            }
        }
        .padding(8)
        .frame(height: AnnotateController.barHeight)
        .annotateGlass(in: Capsule(), interactive: true)
        // Glass alone isn't hit-testable; taps between the buttons must not reach the frozen screen
        .contentShape(Capsule())
        .onTapGesture {}
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
    /// pill visibly grows into "4 comments sent" instead of jumping.
    static let statusAnimation: Animation = .snappy(duration: 0.25)

    /// Figma is black on white in light mode. Dark mode has no frame, so the pair inverts through
    /// semantic colors: a fixed black pill would vanish into dark app UI.
    private static let fill = Color(uiColor: .label)
    private static let text = Color(uiColor: .systemBackground)

    var body: some View {
        let status = controller.launcherStatus
        let frame = controller.launcherFrame
        let maxWidth = max(controller.bounds.width - Self.containerInset * 2, 0)

        Text(status.title)
            .font(.system(size: Self.titleSize, weight: .medium))
            .foregroundStyle(Self.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Self.horizontalPadding)
            // The 44pt Figma height wins over its py-8 (22 + 16 = 38)
            .frame(height: AnnotateController.launcherHeight)
            .background(Self.fill, in: Capsule())
            .animation(Self.statusAnimation, value: status)
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

    var body: some View {
        let safe = controller.safeInsets
        let width = controller.bounds.width - safe.left - safe.right - 48

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
        // Sits just above the review bar, which OverlayRoot docks 8pt above `chromeBottom`.
        .offset(x: safe.left + 24, y: controller.chromeBottom - 8 - AnnotateController.barHeight - 52)
        .allowsHitTesting(false)
    }
}
#endif
