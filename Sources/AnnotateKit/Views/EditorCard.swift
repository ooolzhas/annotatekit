// The comment card that opens next to a selection or region, the in-place text retype field, and
// the region sketch surface. Return saves (TextField submit), Esc cancels (key command), and the
// card measures itself so OverlayPlacement can keep it on screen and clear of the toolbar.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI

struct EditorCard: View {
    let controller: AnnotateController
    let draft: AnnotateController.Draft

    @FocusState private var isFocused: Bool
    @State private var size = CGSize(width: 288, height: 112)

    private let width: CGFloat = 288

    var body: some View {
        @Bindable var controller = controller
        let frame = OverlayPlacement.cardFrame(size: size, anchoredTo: controller.focusFrame(for: draft), in: placementBounds)

        VStack(alignment: .leading, spacing: 10) {
            header

            TextField("Describe the change", text: $controller.commentText)
                .font(.system(size: 15))
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit { controller.saveDraft() }

            if let edit = draft.annotation.textEdit {
                DiffRow(edit: edit)
            }

            if draft.annotation.kind == .region || (draft.annotation.kind == .sketch && controller.isDrawing) {
                SketchTools(controller: controller, draft: draft)
            }
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { size = proxy.size }
                    .onChange(of: proxy.size) { _, newSize in size = newSize }
            }
        }
        .offset(x: frame.minX, y: frame.minY)
        .animation(.snappy(duration: 0.18), value: frame)
        .onAppear { isFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(tagTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AnnotateStyle.accentText)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(AnnotateStyle.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            if let source = draft.annotation.source {
                Text(source.shortDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 4)

            if controller.canEditText {
                CardIconButton(systemName: "character.cursor.ibeam") { controller.beginTextEdit() }
            }
            CardIconButton(systemName: "trash") { controller.deleteDraft() }
            CardIconButton(systemName: draft.isNew ? "plus" : "checkmark", prominent: true) { controller.saveDraft() }
        }
    }

    private var tagTitle: String {
        let frame = draft.annotation.frame
        switch draft.annotation.kind {
        case .element: return draft.annotation.element?.title ?? "Element"
        case .point: return "Spot \(Int(draft.annotation.anchor.x)), \(Int(draft.annotation.anchor.y))"
        case .region: return "Region \(Int(frame.width)) × \(Int(frame.height))"
        case .sketch: return draft.annotation.element.map { "Sketch over \($0.title)" } ?? "Sketch"
        }
    }

    /// Safe bounds minus the strip the toolbar occupies.
    private var placementBounds: CGRect {
        var bounds = controller.safeBounds
        let reserved = AnnotateController.toolbarHeight + 8
        if controller.toolbarAtTop {
            bounds.origin.y += reserved
        }
        bounds.size.height -= reserved
        return bounds
    }
}

private struct CardIconButton: View {
    let systemName: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.secondary)
                .frame(width: 26, height: 26)
                .background(prominent ? AnnotateStyle.accentFill : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct DiffRow: View {
    let edit: TextEdit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(edit.from)
                .strikethrough()
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(edit.to)
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }
}

private struct SketchTools: View {
    let controller: AnnotateController
    let draft: AnnotateController.Draft

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Stroke.Tool.allCases, id: \.self) { tool in
                let isSelected = draft.tool == tool
                Button {
                    controller.selectTool(tool)
                } label: {
                    Image(systemName: tool.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? AnnotateStyle.accentText : Color.secondary)
                        .frame(width: 32, height: 28)
                        .background(isSelected ? AnnotateStyle.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button {
                controller.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(draft.annotation.sketch?.strokes.isEmpty ?? true)
        }
    }
}

extension Stroke.Tool {
    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .ellipse: "circle"
        case .rectangle: "square"
        case .arrow: "arrow.up.right"
        }
    }
}

/// Retype a label in place, like editing text on a web page. Return saves the pin.
struct InlineTextEditor: View {
    let controller: AnnotateController
    let frame: CGRect

    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var controller = controller
        let fontSize = min(max(frame.height * 0.72, 12), 28)
        let safe = controller.safeBounds
        let width = min(max(frame.width + 8, 180), safe.width)
        let x = min(max(frame.minX - 4, safe.minX), safe.maxX - width)

        TextField("", text: $controller.replacementText)
            .font(.system(size: fontSize))
            .textFieldStyle(.plain)
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit { controller.saveDraft() }
            .padding(.horizontal, 4)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: max(frame.height, 28))
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(AnnotateStyle.accent, lineWidth: 2))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .offset(x: x, y: frame.minY)
            .onAppear { isFocused = true }
    }
}

/// Draw mode: the whole frozen screen is the canvas. Strokes are kept in screen points until the
/// draft is saved, when the controller rebases them onto the drawing's bounds.
struct DrawingCanvas: View {
    let controller: AnnotateController
    let draft: AnnotateController.Draft

    @State private var live: Stroke?

    var body: some View {
        let strokes = (draft.annotation.sketch?.strokes ?? []) + (live.map { [$0] } ?? [])
        SketchStrokes(strokes: strokes)
            .frame(width: controller.bounds.width, height: controller.bounds.height)
            .contentShape(Rectangle())
            .gesture(StrokeGesture.make(tool: draft.tool, live: $live) { controller.addStroke($0) })
    }
}

/// Shared pen/shape gesture for regions and draw mode, in the attached view's local space.
@MainActor
enum StrokeGesture {
    static func make(tool: Stroke.Tool, live: Binding<Stroke?>, commit: @escaping (Stroke) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = AnnotationPoint(value.location)
                guard var stroke = live.wrappedValue else {
                    live.wrappedValue = Stroke(tool: tool, points: [AnnotationPoint(value.startLocation), point])
                    return
                }
                if stroke.tool == .pen {
                    // Skip sub-point jitter so pen paths stay light
                    if let last = stroke.points.last, hypot(last.x - point.x, last.y - point.y) < 1.5 { return }
                    stroke.points.append(point)
                } else {
                    stroke.points = [stroke.points[0], point]
                }
                live.wrappedValue = stroke
            }
            .onEnded { _ in
                defer { live.wrappedValue = nil }
                guard let stroke = live.wrappedValue, let first = stroke.points.first, let last = stroke.points.last else { return }
                if stroke.tool == .pen || hypot(last.x - first.x, last.y - first.y) >= 4 {
                    commit(stroke)
                }
            }
    }
}

/// Dims everything but the region and turns it into a drawing surface for the selected tool.
struct RegionEditor: View {
    let controller: AnnotateController
    let draft: AnnotateController.Draft

    @State private var live: Stroke?

    var body: some View {
        let frame = draft.annotation.frame.cgRect
        let strokes = (draft.annotation.sketch?.strokes ?? []) + (live.map { [$0] } ?? [])

        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(controller.bounds)
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.22), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            SketchStrokes(strokes: strokes)
                .frame(width: frame.width, height: frame.height)
                .background(Color.white.opacity(0.3))
                .overlay(Rectangle().strokeBorder(AnnotateStyle.accent, lineWidth: 2))
                .contentShape(Rectangle())
                .gesture(StrokeGesture.make(tool: draft.tool, live: $live) { controller.addStroke($0) })
                .offset(x: frame.minX, y: frame.minY)

            ElementChip(title: "Region \(Int(frame.width)) × \(Int(frame.height))")
                .fixedSize()
                .offset(x: frame.minX, y: max(frame.minY - 24, controller.safeBounds.minY))
                .allowsHitTesting(false)
        }
    }
}
#endif
