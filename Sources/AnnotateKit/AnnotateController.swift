// Annotate-mode state machine, observed by the overlay views.
// Tap → SelectionStack of everything under the finger (↑↓ walks it) → draft pin with comment.
// Drag → region draft with sketch tools. Return saves, Esc backs out one level, ⌘Z undoes.
// Send → captures the screen, renders crops, writes the bundle (SessionWriter), copies the prompt.
// Each pin keeps only a padded crop of the screen as it looked when the pin was made; markup is
// drawn onto it at Send, so later edits to a sketch or comment still land in the PNG.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import Observation
import UIKit

@MainActor
@Observable
final class AnnotateController {
    struct Draft: Equatable {
        /// `index` is 0 until a new draft is saved.
        var annotation: Annotation
        var isNew: Bool
        var isEditingText = false
        var replacementText = ""
        var tool: Stroke.Tool = .pen
    }

    struct Toast: Equatable {
        let id = UUID()
        let message: String
    }

    /// Screen region under a pin at the moment it was made, without markup.
    struct CropBase {
        let image: UIImage
        /// Where `image` sits in screen points.
        let origin: CGPoint
    }

    // MARK: Configuration

    @ObservationIgnored private(set) var options = AnnotateOptions()
    @ObservationIgnored private var callerFile = ""
    @ObservationIgnored weak var window: OverlayWindow?
    @ObservationIgnored private var cachedProjectRoot: URL??

    // MARK: Layout (pushed by the hosting controller)

    private(set) var bounds: CGRect = .zero
    private(set) var safeInsets: UIEdgeInsets = .zero

    // MARK: State

    private(set) var isActive = false
    private(set) var annotations: [Annotation] = []
    private(set) var selection: SelectionStack?
    var draft: Draft?
    private(set) var dragRect: CGRect?
    private(set) var toast: Toast?
    private(set) var launcherCenter: CGPoint?

    @ObservationIgnored private var cropBases: [UUID: CropBase] = [:]
    @ObservationIgnored private var draftCropBase: CropBase?

    static let cropPadding: CGFloat = 24
    static let minimumRegionSide: CGFloat = 16
    static let dragThreshold: CGFloat = 6

    func configure(options: AnnotateOptions, callerFile: String) {
        self.options = options
        self.callerFile = callerFile
    }

    func updateLayout(bounds: CGRect, safeInsets: UIEdgeInsets) {
        if self.bounds != bounds { self.bounds = bounds }
        if self.safeInsets != safeInsets { self.safeInsets = safeInsets }
    }

    // MARK: Mode

    func start() {
        guard !isActive else { return }
        isActive = true
        window?.activate()
    }

    func stop() {
        guard isActive else { return }
        finishDraft()
        selection = nil
        dragRect = nil
        isActive = false
        window?.deactivate()
    }

    // MARK: Pointer

    func dragChanged(from start: CGPoint, to location: CGPoint) {
        guard hypot(location.x - start.x, location.y - start.y) > Self.dragThreshold || dragRect != nil else { return }
        if dragRect == nil { finishDraft() }
        dragRect = CGRect.spanning(start, location)
    }

    func dragEnded(from start: CGPoint, to location: CGPoint) {
        guard let rect = dragRect else {
            tap(at: location)
            return
        }
        dragRect = nil
        if rect.width >= Self.minimumRegionSide && rect.height >= Self.minimumRegionSide {
            beginRegion(rect)
        } else {
            tap(at: location)
        }
    }

    func tap(at point: CGPoint) {
        finishDraft()
        let candidates = ElementScanner.candidates(at: point, excluding: window)
            + AnnotatableRegistry.shared.visible(in: bounds).map(\.candidate)
        let stack = SelectionStack(candidates: candidates, at: point)
        guard let current = stack.current else {
            selection = nil
            return
        }
        selection = stack
        let screenshot = Snapshotter.captureApp(excluding: window)
        draftCropBase = screenshot.flatMap { Self.cropBase(of: $0, around: current.frame) }
        draft = Draft(
            annotation: Annotation(
                index: 0,
                kind: .element,
                frame: AnnotationRect(current.frame),
                element: stack.currentInfo,
                source: stack.resolvedSource
            ),
            isNew: true
        )
    }

    /// ↑ (`expand`) / ↓ — retarget the unsaved pin at the next larger or smaller element.
    func adjustSelection(expand: Bool) {
        guard var stack = selection, var current = draft, current.isNew, !current.isEditingText else { return }
        let moved = expand ? stack.expand() : stack.narrow()
        guard moved, let candidate = stack.current else { return }
        selection = stack
        current.annotation.frame = AnnotationRect(candidate.frame)
        current.annotation.element = stack.currentInfo
        current.annotation.source = stack.resolvedSource
        draft = current
        // Re-crop from the full capture only when the new box escapes the stored crop
        if let base = draftCropBase {
            let stored = CGRect(origin: base.origin, size: base.image.size)
            if !stored.encloses(candidate.frame.padded(by: Self.cropPadding), tolerance: 0.5),
               let screenshot = Snapshotter.captureApp(excluding: window) {
                draftCropBase = Self.cropBase(of: screenshot, around: candidate.frame)
            }
        }
    }

    func beginRegion(_ rect: CGRect) {
        finishDraft()
        selection = nil
        let screenshot = Snapshotter.captureApp(excluding: window)
        draftCropBase = screenshot.flatMap { Self.cropBase(of: $0, around: rect) }
        draft = Draft(
            annotation: Annotation(
                index: 0,
                kind: .region,
                frame: AnnotationRect(rect),
                source: SourceResolver.resolve(frame: rect, in: AnnotatableRegistry.shared.visible(in: bounds)),
                sketch: Sketch(size: AnnotationSize(rect.size))
            ),
            isNew: true
        )
    }

    // MARK: Draft editing

    func setComment(_ comment: String) {
        draft?.annotation.comment = comment
    }

    func selectTool(_ tool: Stroke.Tool) {
        draft?.tool = tool
    }

    func addStroke(_ stroke: Stroke) {
        draft?.annotation.sketch?.strokes.append(stroke)
    }

    var canEditText: Bool {
        guard let draft, draft.annotation.kind == .element, let element = draft.annotation.element else { return false }
        return !(element.label ?? "").isEmpty && ["text", "header", "button", "link"].contains(element.role)
    }

    func beginTextEdit() {
        guard canEditText, var current = draft else { return }
        current.isEditingText = true
        current.replacementText = current.annotation.textEdit?.to ?? current.annotation.element?.label ?? ""
        draft = current
    }

    func setReplacementText(_ text: String) {
        draft?.replacementText = text
    }

    /// Saves the draft as a pin, or drops it when there is nothing to act on.
    func saveDraft() {
        guard var current = draft else { return }
        if current.isEditingText {
            let original = current.annotation.element?.label ?? ""
            let replacement = current.replacementText
            current.annotation.textEdit = replacement == original ? nil : TextEdit(from: original, to: replacement)
        }
        defer { clearDraft() }

        guard !current.annotation.isEmpty else {
            if !current.isNew { removeAnnotation(id: current.annotation.id) }
            return
        }
        if current.isNew {
            current.annotation.index = annotations.count + 1
            annotations.append(current.annotation)
            if let base = draftCropBase { cropBases[current.annotation.id] = base }
        } else if let position = annotations.firstIndex(where: { $0.id == current.annotation.id }) {
            annotations[position] = current.annotation
        }
    }

    func cancelDraft() {
        clearDraft()
    }

    func deleteDraft() {
        if let current = draft, !current.isNew {
            removeAnnotation(id: current.annotation.id)
        }
        clearDraft()
    }

    func openExisting(_ id: UUID) {
        finishDraft()
        guard let annotation = annotations.first(where: { $0.id == id }) else { return }
        draft = Draft(annotation: annotation, isNew: false)
    }

    // MARK: Keys

    func escape() {
        if draft?.isEditingText == true {
            draft?.isEditingText = false
        } else if draft != nil {
            cancelDraft()
        } else if selection != nil {
            selection = nil
        } else {
            stop()
        }
    }

    func undo() {
        if let strokes = draft?.annotation.sketch?.strokes, !strokes.isEmpty {
            draft?.annotation.sketch?.strokes.removeLast()
        } else if draft == nil, let last = annotations.last {
            removeAnnotation(id: last.id)
            showToast("Removed pin \(last.index)")
        }
    }

    // MARK: Send

    func clearAll() {
        clearDraft()
        annotations.removeAll()
        cropBases.removeAll()
    }

    func send(keepAnnotating: Bool) {
        finishDraft()
        guard !annotations.isEmpty else {
            showToast("Nothing to send yet")
            return
        }

        var images: [String: Data] = [:]
        var outgoing = annotations
        for position in outgoing.indices {
            let annotation = outgoing[position]
            if let base = cropBases[annotation.id], let crop = Self.renderCrop(base, annotation: annotation), let data = crop.pngData() {
                let path = "crops/\(annotation.index).png"
                images[path] = data
                outgoing[position].crop = path
            }
            if let root = projectRoot, let file = annotation.source?.file {
                outgoing[position].source?.file = ProjectRoot.relativePath(of: file, to: root)
            }
        }

        let screenshot = Snapshotter.captureApp(excluding: window)
        if let screenshot, let clean = screenshot.pngData(),
           let annotated = Snapshotter.annotatedScreenshot(screenshot, annotations: outgoing).pngData() {
            images["screenshot.png"] = clean
            images["annotated.png"] = annotated
        }

        let appWindow = ElementScanner.appWindows(excluding: window).first
        let session = AnnotationSession(
            id: SessionWriter.makeSessionID(),
            createdAt: Date(),
            app: .current,
            device: .current(window: appWindow ?? window),
            screenshot: images["screenshot.png"] == nil ? nil : "screenshot.png",
            annotatedScreenshot: images["annotated.png"] == nil ? nil : "annotated.png",
            annotations: outgoing
        )

        let output = outputDirectory()
        let sessionDir = output
            .appendingPathComponent(SessionWriter.sessionsFolder, isDirectory: true)
            .appendingPathComponent(session.id, isDirectory: true)
        let prompt = PromptRenderer.render(session, sessionPath: sessionDir.path)
        UIPasteboard.general.string = prompt

        do {
            try SessionWriter.write(SessionBundle(session: session, images: images), prompt: prompt, to: output)
            let count = outgoing.count
            showToast("Sent \(count) \(count == 1 ? "annotation" : "annotations") · prompt copied")
        } catch {
            showToast("Prompt copied, but writing the session failed: \(error.localizedDescription)")
            return
        }

        if !keepAnnotating {
            clearAll()
            stop()
        }
    }

    // MARK: Chrome

    var hint: String {
        if let draft {
            if draft.isEditingText { return "Return to save · Esc to cancel" }
            if draft.annotation.kind == .region { return "Draw to sketch · ⌘Z undo · Esc cancel" }
            return draft.isNew ? "Return to save · ↑↓ to adjust" : "Return to save · Esc to close"
        }
        return "Tap to select · Drag for an area"
    }

    /// Bounds inside the safe area with a small margin; cards and chips stay within it.
    var safeBounds: CGRect {
        bounds.inset(by: UIEdgeInsets(
            top: safeInsets.top + 8,
            left: safeInsets.left + 8,
            bottom: safeInsets.bottom + 8,
            right: safeInsets.right + 8
        ))
    }

    /// The toolbar moves to the top while the user works in the lower part of the screen.
    var toolbarAtTop: Bool {
        let focus = dragRect ?? draft?.annotation.frame.cgRect ?? selection?.current?.frame
        guard let focus, bounds.height > 0 else { return false }
        return focus.maxY > bounds.height * 0.6
    }

    static let toolbarHeight: CGFloat = 44
    static let launcherSize: CGFloat = 44

    var resolvedLauncherCenter: CGPoint {
        if let launcherCenter { return launcherCenter }
        let radius = Self.launcherSize / 2
        return CGPoint(x: bounds.maxX - safeInsets.right - 16 - radius, y: bounds.maxY - safeInsets.bottom - 72 - radius)
    }

    /// Touch target the overlay window accepts while annotate mode is off.
    var launcherHitFrame: CGRect {
        guard options.showsLauncher else { return .zero }
        let center = resolvedLauncherCenter
        let side = Self.launcherSize + 8
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// Snaps to the nearest side edge, clamped inside the safe area.
    func moveLauncher(to point: CGPoint) {
        let radius = Self.launcherSize / 2
        let area = safeBounds.insetBy(dx: 8 + radius, dy: radius)
        let x = point.x < bounds.midX ? area.minX : area.maxX
        let y = min(max(point.y, area.minY), area.maxY)
        launcherCenter = CGPoint(x: x, y: y)
    }

    func showToast(_ message: String) {
        let toast = Toast(message: message)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if self.toast == toast { self.toast = nil }
        }
    }

    // MARK: Private

    /// Commits a draft with content, drops an empty one. Called before any new interaction.
    private func finishDraft() {
        guard let current = draft else { return }
        if current.isNew && current.annotation.isEmpty && !current.isEditingText {
            clearDraft()
        } else {
            saveDraft()
        }
    }

    private func clearDraft() {
        draft = nil
        selection = nil
        draftCropBase = nil
    }

    private func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        cropBases[id] = nil
        for position in annotations.indices {
            annotations[position].index = position + 1
        }
    }

    /// Found once from the `install` call site; nil on a device, where host paths don't exist.
    private var projectRoot: URL? {
        if let cachedProjectRoot { return cachedProjectRoot }
        let root = ProjectRoot.locate(fromSourceFile: callerFile)
        cachedProjectRoot = .some(root)
        return root
    }

    private func outputDirectory() -> URL {
        if let custom = options.outputDirectory { return custom }
        if let root = projectRoot, FileManager.default.isWritableFile(atPath: root.path) {
            return root.appendingPathComponent(".annotate", isDirectory: true)
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(".annotate", isDirectory: true)
    }

    private static func cropBase(of screenshot: UIImage, around frame: CGRect) -> CropBase? {
        let area = frame.padded(by: cropPadding).clipped(to: CGRect(origin: .zero, size: screenshot.size))
        guard area.width >= 1, area.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenshot.scale
        let image = UIGraphicsImageRenderer(size: area.size, format: format).image { _ in
            screenshot.draw(at: CGPoint(x: -area.minX, y: -area.minY))
        }
        return CropBase(image: image, origin: area.origin)
    }

    private static func renderCrop(_ base: CropBase, annotation: Annotation) -> UIImage? {
        var shifted = annotation
        shifted.frame = AnnotationRect(annotation.frame.cgRect.offsetBy(dx: -base.origin.x, dy: -base.origin.y))
        return Snapshotter.markup(shifted, onto: base.image)
    }
}
#endif
