// Shared overlay chrome for the redesigned annotate mode (Figma PVX9n74hzo5BWauvymG141, group
// 9257:13754): the 44pt round icon button every surface uses, the shared chrome button style
// (press feedback only, no disabled dimming), the glass helper, the white number
// badge, white sketch strokes, and the review bar shown when no pin is open (9257:13549). Also
// owns the floating launcher with its delivery ring and the toast, which predate the redesign.

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
    @ViewBuilder
    func annotateGlass<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
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
                CircleIconButton(systemName: "trash", style: canSend ? .plain : .dimmed) { controller.clearAll() }
                    .disabled(!canSend)
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
        .annotateGlass(in: Capsule())
        // Glass alone isn't hit-testable; taps between the buttons must not reach the frozen screen
        .contentShape(Capsule())
        .onTapGesture {}
    }
}

// MARK: - Launcher

struct LauncherButton: View {
    let controller: AnnotateController
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        let center = controller.resolvedLauncherCenter
        let count = controller.annotations.count

        Image(systemName: "pencil.and.scribble")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: AnnotateController.launcherSize, height: AnnotateController.launcherSize)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.primary.opacity(0.1)))
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Circle().fill(AnnotateStyle.accentFill))
                        .offset(x: 3, y: -3)
                }
            }
            .overlay { DeliveryRing(delivery: controller.delivery) }
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            .contentShape(Circle())
            .onTapGesture { controller.start() }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .updating($dragOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        controller.moveLauncher(to: CGPoint(x: center.x + value.translation.width, y: center.y + value.translation.height))
                    }
            )
            .position(x: center.x + dragOffset.width, y: center.y + dragOffset.height)
            .animation(.snappy(duration: 0.3), value: center)
    }
}

/// Ring around the launcher narrating the last Send: dashed while waiting, spinning while Claude
/// works, green when done, red on failure.
private struct DeliveryRing: View {
    let delivery: AnnotateController.Delivery?
    @State private var spin = false

    var body: some View {
        Group {
            switch delivery {
            case .none:
                EmptyView()
            case .waiting?, .unclaimed?, .delivered?:
                Circle()
                    .strokeBorder(AnnotateStyle.accent.opacity(delivery == .unclaimed ? 0.35 : 0.8), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
            case .received?, .working?:
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(AnnotateStyle.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
                    .padding(1)
            case .done?:
                Circle().strokeBorder(Color.green, lineWidth: 2.5)
            case .failed?:
                Circle().strokeBorder(Color.red, lineWidth: 2.5)
            }
        }
        .allowsHitTesting(false)
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
