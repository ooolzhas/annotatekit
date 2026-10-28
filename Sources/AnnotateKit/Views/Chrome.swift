// Small pieces of overlay chrome: element chip, numbered pin, sketch strokes, the toolbar with
// Send, the floating launcher, and the toast. Visual language follows Cursor's Annotate: one
// accent blue for selection and pins, red for sketches, material cards.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI

struct ElementChip: View {
    let title: String
    var height: CGFloat = 20

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .frame(height: height)
            .background(AnnotateStyle.accentFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct PinBadge: View {
    let number: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: AnnotateStyle.pinRadius * 2, height: AnnotateStyle.pinRadius * 2)
                .background(Circle().fill(AnnotateStyle.accentFill))
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .scaleEffect(isActive ? 1.18 : 1)
                // Larger invisible target than the 22pt dot
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: isActive)
    }
}

struct SketchStrokes: View {
    let strokes: [Stroke]

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                context.stroke(
                    Path(SketchPath.path(for: stroke)),
                    with: .color(AnnotateStyle.sketch),
                    style: StrokeStyle(lineWidth: AnnotateStyle.sketchLineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

struct OverlayToolbar: View {
    let controller: AnnotateController

    var body: some View {
        let height = AnnotateController.toolbarHeight
        let safe = controller.safeInsets
        let width = controller.bounds.width - safe.left - safe.right - 24
        let y = controller.toolbarAtTop
            ? safe.top + 6
            : controller.bounds.maxY - max(safe.bottom, 12) - 6 - height

        HStack(spacing: 8) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AnnotateStyle.accentText)
            Text(controller.hint)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
            Spacer(minLength: 4)
            DrawToggle(controller: controller)
            SendButton(controller: controller)
            Button {
                controller.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(width: max(width, 0), height: height)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .offset(x: safe.left + 12, y: y)
        .animation(.snappy(duration: 0.25), value: controller.toolbarAtTop)
        .animation(.snappy(duration: 0.15), value: controller.hint)
    }
}

/// Turns the whole frozen screen into a sketch canvas (and back, saving the drawing).
private struct DrawToggle: View {
    let controller: AnnotateController

    var body: some View {
        let isOn = controller.isDrawing
        Button {
            controller.toggleDrawing()
        } label: {
            Image(systemName: "scribble.variable")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : AnnotateStyle.accentText)
                .frame(width: 32, height: 30)
                .background(isOn ? AnnotateStyle.sketchFill : AnnotateStyle.accent.opacity(0.16), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isOn)
    }
}

private struct SendButton: View {
    let controller: AnnotateController

    var body: some View {
        let count = controller.annotations.count
        Menu {
            Button("Send and keep annotating", systemImage: "paperplane") {
                controller.send(keepAnnotating: true)
            }
            Button("Clear all", systemImage: "trash", role: .destructive) {
                controller.clearAll()
            }
        } label: {
            HStack(spacing: 5) {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(.white.opacity(0.25)))
                Text("Send")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(height: 30)
            .background(AnnotateStyle.accentFill.opacity(count == 0 ? 0.45 : 1), in: Capsule())
            .contentTransition(.numericText())
        } primaryAction: {
            controller.send(keepAnnotating: false)
        }
        .menuIndicator(.hidden)
        .animation(.snappy, value: count)
    }
}

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
        .offset(
            x: safe.left + 24,
            y: controller.toolbarAtTop
                ? controller.bounds.maxY - max(safe.bottom, 12) - 52
                : controller.bounds.maxY - max(safe.bottom, 12) - AnnotateController.toolbarHeight - 52
        )
        .allowsHitTesting(false)
    }
}
#endif
