// Root of the overlay window. The whole tree ignores the safe area so SwiftUI coordinates equal
// window (= screen) points, which is the space every frame from ElementScanner and the registry
// uses. Elements are placed by top-left offset inside a full-screen top-leading ZStack.
// Safe-area-aware chrome reads insets from the controller instead.
// While active, the freeze-frame captured on start sits at the bottom of the stack: the app looks
// paused, and every coordinate refers to exactly that image.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI

struct OverlayRoot: View {
    let controller: AnnotateController

    var body: some View {
        ZStack(alignment: .topLeading) {
            if controller.isActive {
                ActiveOverlay(controller: controller)
                    .transition(.opacity)
            } else if controller.options.showsLauncher {
                LauncherButton(controller: controller)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            // Outside the active layer so delivery progress survives leaving annotate mode
            if let toast = controller.toast {
                ToastView(message: toast.message, controller: controller)
                    .id(toast.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .animation(.snappy(duration: 0.22), value: controller.isActive)
        .animation(.snappy(duration: 0.2), value: controller.toast)
    }
}

private struct ActiveOverlay: View {
    let controller: AnnotateController

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let frozen = controller.frozenImage {
                Image(uiImage: frozen)
                    .resizable()
                    .frame(width: controller.bounds.width, height: controller.bounds.height)
                    .allowsHitTesting(false)
            }

            captureLayer

            ScreenEdgeGlow()
                .allowsHitTesting(false)

            ForEach(controller.visibleAnnotations) { annotation in
                if controller.draft?.annotation.id != annotation.id {
                    SavedOutline(annotation: annotation)
                }
            }

            if controller.isDrawing, let draft = controller.draft {
                DrawingCanvas(controller: controller, draft: draft)
            }

            if let draft = controller.draft, draft.annotation.kind == .element || draft.annotation.kind == .point {
                SelectionHighlight(
                    annotation: draft.annotation,
                    title: controller.chipTitle(for: draft.annotation),
                    safeBounds: controller.safeBounds
                )
            }

            if let rect = controller.dragRect {
                RegionDragPreview(rect: rect)
            }

            if let draft = controller.draft, draft.annotation.kind == .region {
                RegionEditor(controller: controller, draft: draft)
            }

            ForEach(controller.visibleAnnotations) { annotation in
                PinBadge(
                    number: annotation.index,
                    isActive: controller.draft?.annotation.id == annotation.id
                ) {
                    controller.openExisting(annotation.id)
                }
                .position(OverlayPlacement.pinCenter(
                    for: annotation.pinAnchorFrame,
                    radius: AnnotateStyle.pinRadius,
                    in: controller.bounds
                ))
                .transition(.scale(scale: 0.3).combined(with: .opacity))
            }

            if let draft = controller.draft {
                if draft.isEditingText {
                    InlineTextEditor(controller: controller, frame: draft.annotation.frame.cgRect)
                } else {
                    EditorCard(controller: controller, draft: draft)
                        .id(draft.annotation.id)
                }
            }

            OverlayToolbar(controller: controller)
        }
        .animation(.snappy(duration: 0.2), value: controller.annotations)
    }

    /// Full-screen catcher: a short touch selects, a drag draws a region.
    private var captureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { controller.dragChanged(from: $0.startLocation, to: $0.location) }
                    .onEnded { controller.dragEnded(from: $0.startLocation, to: $0.location) }
            )
    }
}

extension Annotation {
    /// Where the numbered pin attaches: a box's top-trailing corner, or just beside a spot.
    var pinAnchorFrame: CGRect {
        let offset = AnnotateStyle.spotBadgeOffset
        return kind == .point ? CGRect(x: anchor.x + offset, y: anchor.y - offset, width: 0, height: 0) : frame.cgRect
    }
}

/// Crosshair ring marking an exact spot (point pins).
struct SpotMarker: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(AnnotateStyle.accent, lineWidth: 2)
            Circle().fill(AnnotateStyle.accent).frame(width: 4, height: 4)
        }
        .frame(width: 18, height: 18)
        .shadow(color: .black.opacity(0.25), radius: 2)
    }
}

/// Thin accent line around the screen while annotate mode is on, like Cursor's framed browser.
private struct ScreenEdgeGlow: View {
    var body: some View {
        Rectangle()
            .strokeBorder(AnnotateStyle.accent.opacity(0.85), lineWidth: 3)
            .ignoresSafeArea()
    }
}

private struct SavedOutline: View {
    let annotation: Annotation

    var body: some View {
        let frame = annotation.frame.cgRect
        Group {
            if annotation.kind == .point {
                SpotMarker()
                    .offset(x: annotation.anchor.x - 9, y: annotation.anchor.y - 9)
            } else {
                ZStack(alignment: .topLeading) {
                    if annotation.kind != .sketch {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(
                                AnnotateStyle.accent.opacity(0.55),
                                style: StrokeStyle(lineWidth: 1.5, dash: annotation.kind == .region ? [5, 4] : [])
                            )
                    }
                    if let sketch = annotation.sketch {
                        SketchStrokes(strokes: sketch.strokes)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SelectionHighlight: View {
    let annotation: Annotation
    let title: String
    let safeBounds: CGRect

    private let chipHeight: CGFloat = 20

    var body: some View {
        let frame = annotation.frame.cgRect
        // Chip sits above the box, or inside its top edge when there's no room above
        let chipAbove = frame.minY - chipHeight - 4 >= safeBounds.minY
        let chipY = chipAbove ? frame.minY - chipHeight - 4 : frame.minY + 4
        let chipX = min(max(frame.minX, safeBounds.minX), safeBounds.maxX - 120)

        ZStack(alignment: .topLeading) {
            if annotation.kind == .point {
                SpotMarker()
                    .offset(x: annotation.anchor.x - 9, y: annotation.anchor.y - 9)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(AnnotateStyle.accent.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(AnnotateStyle.accent, lineWidth: 1.5))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }

            ElementChip(title: title, height: chipHeight)
                .frame(maxWidth: max(safeBounds.maxX - chipX, 60), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: chipX, y: chipY)
        }
        .allowsHitTesting(false)
        .animation(.snappy(duration: 0.18), value: frame)
    }
}

private struct RegionDragPreview: View {
    let rect: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(AnnotateStyle.accent.opacity(0.08))
                .overlay(Rectangle().strokeBorder(AnnotateStyle.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            ElementChip(title: "Region \(Int(rect.width)) × \(Int(rect.height))", height: 20)
                .fixedSize()
                .offset(x: rect.minX, y: max(rect.minY - 24, 0))
        }
        .allowsHitTesting(false)
    }
}
#endif
