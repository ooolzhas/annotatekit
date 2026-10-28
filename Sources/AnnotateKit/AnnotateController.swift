// Annotate-mode state machine, observed by the overlay views.
// Start → freeze-frame: the app is captured (pixels + visible-text outline) and the overlay shows
// that still image, so what you annotate is exactly what gets sent and coordinates can't drift.
// Tap → SelectionStack of everything under the finger; a tap on nothing distinct pins the spot
// itself, so every pixel is annotatable. ↑↓ walks spot → element → containers.
// Drag → region with sketch tools. Return saves, Esc backs out one level, ⌘Z undoes.
// Send → renders 1x/annotated/hi-res images and crops per screen, writes the bundle, then polls
// its status.json so the overlay can show the agent picking it up and finishing. No copy/paste.

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

    /// One freeze-frame. Pixels stay out of observation; views read `frozenImage`.
    struct CapturedScreen {
        let index: Int
        let capturedAt: Date
        let image: UIImage
        let elements: [ScreenElement]
    }

    /// Progress of the most recent Send, read back from the bundle's status.json.
    enum Delivery: Equatable {
        /// Written; no agent has picked it up yet.
        case waiting
        /// Still nobody after a while: no watcher is running.
        case unclaimed
        /// Handed to Claude Code, not opened yet (Claude may be busy with another turn).
        case delivered
        case received
        case working(String?)
        case done(String?)
        case failed(String?)

        var isFinal: Bool {
            if case .done = self { return true }
            if case .failed = self { return true }
            return false
        }
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
    private(set) var draft: Draft?
    private(set) var dragRect: CGRect?
    private(set) var toast: Toast?
    private(set) var launcherCenter: CGPoint?
    /// The still image shown under the overlay while annotating.
    private(set) var frozenImage: UIImage?
    private(set) var currentScreen = 0
    private(set) var delivery: Delivery?

    @ObservationIgnored private var screens: [Int: CapturedScreen] = [:]
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?

    static let cropPadding: CGFloat = 32
    static let minimumRegionSide: CGFloat = 16
    static let dragThreshold: CGFloat = 6
    static let spotSize: CGFloat = 44

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
        freezeScreen()
        isActive = true
        window?.activate()
    }

    func stop() {
        guard isActive else { return }
        finishDraft()
        selection = nil
        dragRect = nil
        isActive = false
        frozenImage = nil
        window?.deactivate()
    }

    /// Pins on the frozen screen currently shown.
    var visibleAnnotations: [Annotation] {
        annotations.filter { $0.screen == currentScreen }
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
        let stack = SelectionStack(candidates: candidates, at: point, screenArea: bounds.area)
        selection = stack
        draft = Draft(annotation: annotation(for: stack, updating: nil), isNew: true)
    }

    /// ↑ (`expand`) / ↓ — retarget the unsaved pin: spot → element → enclosing containers.
    func adjustSelection(expand: Bool) {
        guard var stack = selection, var current = draft, current.isNew, !current.isEditingText else { return }
        guard expand ? stack.expand() : stack.narrow() else { return }
        selection = stack
        current.annotation = annotation(for: stack, updating: current.annotation)
        draft = current
    }

    func beginRegion(_ rect: CGRect) {
        finishDraft()
        selection = nil
        var region = Annotation(
            index: 0,
            screen: currentScreen,
            kind: .region,
            frame: AnnotationRect(rect),
            source: SourceResolver.resolve(frame: rect, in: AnnotatableRegistry.shared.visible(in: bounds)),
            sketch: Sketch(size: AnnotationSize(rect.size))
        )
        region.nearbyText = ScreenOutline.nearbyText(for: rect, in: screens[currentScreen]?.elements ?? [])
        draft = Draft(annotation: region, isNew: true)
    }

    // MARK: Draft editing

    /// Bindable text of the open draft's comment.
    var commentText: String {
        get { draft?.annotation.comment ?? "" }
        set { draft?.annotation.comment = newValue }
    }

    /// Bindable text of the in-place retype field.
    var replacementText: String {
        get { draft?.replacementText ?? "" }
        set { draft?.replacementText = newValue }
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
        } else if draft == nil, let last = visibleAnnotations.last {
            removeAnnotation(id: last.id)
            showToast("Removed pin \(last.index)")
        }
    }

    // MARK: Send

    func clearAll() {
        clearDraft()
        annotations.removeAll()
        screens = screens.filter { $0.key == currentScreen }
    }

    func send(keepAnnotating: Bool) {
        finishDraft()
        guard !annotations.isEmpty else {
            showToast("Nothing to send yet")
            return
        }

        var images: [String: Data] = [:]
        var outgoing = annotations
        var outgoingScreens: [Screen] = []

        if let root = projectRoot {
            for position in outgoing.indices {
                if let file = outgoing[position].source?.file {
                    outgoing[position].source?.file = ProjectRoot.relativePath(of: file, to: root)
                }
            }
        }

        for (index, captured) in screens.sorted(by: { $0.key < $1.key }) {
            let pinPositions = outgoing.indices.filter { outgoing[$0].screen == index }
            guard !pinPositions.isEmpty else { continue }
            let pins = pinPositions.map { outgoing[$0] }
            let oneX = Snapshotter.rescaled(captured.image, to: 1)
            let scale = Int(captured.image.scale.rounded())
            var screen = Screen(index: index, capturedAt: captured.capturedAt, size: AnnotationSize(captured.image.size), elements: captured.elements)

            if let data = oneX.pngData() {
                screen.image = "screens/\(index).png"
                images[screen.image!] = data
            }
            if let data = Snapshotter.annotatedScreenshot(oneX, annotations: pins).pngData() {
                screen.annotatedImage = "screens/\(index)-annotated.png"
                images[screen.annotatedImage!] = data
            }
            if scale > 1, let data = captured.image.pngData() {
                screen.hiResImage = "screens/\(index)@\(scale)x.png"
                images[screen.hiResImage!] = data
            }
            for position in pinPositions {
                let pin = outgoing[position]
                if let crop = Snapshotter.crop(pin, from: captured.image, padding: Self.cropPadding), let data = crop.pngData() {
                    let path = "crops/\(pin.index).png"
                    images[path] = data
                    outgoing[position].crop = path
                }
            }
            outgoingScreens.append(screen)
        }

        let appWindow = ElementScanner.appWindows(excluding: window).first
        let session = AnnotationSession(
            id: SessionWriter.makeSessionID(),
            createdAt: Date(),
            app: .current,
            device: .current(window: appWindow ?? window),
            screens: outgoingScreens,
            annotations: outgoing
        )

        let output = outputDirectory()
        let sessionDir = SessionInbox.sessionDirectory(session.id, in: output)
        let prompt = PromptRenderer.render(session, sessionPath: sessionDir.path, completion: options.completionNote)
        if options.copiesPromptToClipboard {
            UIPasteboard.general.string = prompt
        }

        do {
            try SessionWriter.write(SessionBundle(session: session, images: images), prompt: prompt, to: output)
        } catch {
            UIPasteboard.general.string = prompt
            showToast("Couldn't write the session (\(error.localizedDescription)). Prompt copied instead.")
            return
        }

        let count = outgoing.count
        showToast("Sent \(count) \(count == 1 ? "pin" : "pins")")
        trackDelivery(id: session.id, in: output)

        if !keepAnnotating {
            annotations.removeAll()
            screens.removeAll()
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
        return "Tap anything · Drag for an area"
    }

    /// Short title for the selection chip: the element, or the spot's coordinates.
    func chipTitle(for annotation: Annotation) -> String {
        let name: String
        switch annotation.kind {
        case .element: name = annotation.element?.displayName(maxLabelLength: 22) ?? "Element"
        case .point: name = "Spot \(Int(annotation.anchor.x)), \(Int(annotation.anchor.y))"
        case .region: name = "Region \(Int(annotation.frame.width)) × \(Int(annotation.frame.height))"
        }
        guard let source = annotation.source else { return name }
        return "\(name) · \(source.shortDescription)"
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
        let focus = dragRect ?? draft?.annotation.frame.cgRect
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

    func showToast(_ message: String, duration: Double = 2.6) {
        let toast = Toast(message: message)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(duration))
            if self.toast == toast { self.toast = nil }
        }
    }

    // MARK: Private

    /// Captures the app as it looks right now. A previous screen with no pins is replaced, so
    /// opening and closing annotate mode doesn't pile up empty screens.
    private func freezeScreen() {
        guard let image = Snapshotter.captureApp(excluding: window) else {
            frozenImage = nil
            return
        }
        let outline = ScreenOutline.normalized(ElementScanner.outline(excluding: window), in: bounds)
        let reuse = currentScreen > 0 && !annotations.contains { $0.screen == currentScreen }
        let index = reuse ? currentScreen : (screens.keys.max() ?? 0) + 1
        screens[index] = CapturedScreen(index: index, capturedAt: Date(), image: image, elements: outline)
        currentScreen = index
        frozenImage = image
    }

    /// Builds or retargets an element/spot annotation from the selection, keeping the comment.
    private func annotation(for stack: SelectionStack, updating existing: Annotation?) -> Annotation {
        var result = existing ?? Annotation(
            index: 0,
            screen: currentScreen,
            kind: .point,
            anchor: AnnotationPoint(stack.point),
            frame: AnnotationRect(x: 0, y: 0, width: 0, height: 0)
        )
        if let current = stack.current {
            result.kind = .element
            result.frame = AnnotationRect(current.frame)
            result.element = stack.currentInfo
        } else {
            let side = Self.spotSize
            let spot = CGRect(x: stack.point.x - side / 2, y: stack.point.y - side / 2, width: side, height: side)
            result.kind = .point
            result.frame = AnnotationRect(spot.clipped(to: bounds))
            result.element = nil
            result.textEdit = nil
        }
        result.source = stack.resolvedSource
        result.nearbyText = ScreenOutline.nearbyText(
            for: result.frame.cgRect,
            in: screens[currentScreen]?.elements ?? [],
            excluding: result.element?.label
        )
        return result
    }

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
    }

    private func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        for position in annotations.indices {
            annotations[position].index = position + 1
        }
    }

    /// Polls status.json written by the receiving agent and narrates the transitions.
    private func trackDelivery(id: String, in output: URL) {
        deliveryTask?.cancel()
        delivery = .waiting
        deliveryTask = Task { [weak self] in
            let started = Date()
            var last: SessionStatus.State?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(started)
                guard let status = SessionInbox.readStatus(id: id, in: output) else {
                    if elapsed > self.options.unclaimedAfter, self.delivery == .waiting {
                        self.delivery = .unclaimed
                        self.showToast("Saved, but nothing picked it up. Is the Claude Code watcher running?", duration: 4)
                    }
                    if elapsed > 3600 { return }
                    continue
                }
                guard status.state != last else { continue }
                last = status.state
                switch status.state {
                case .delivered:
                    self.delivery = .delivered
                    self.showToast("Delivered to Claude Code")
                case .received:
                    self.delivery = .received
                    self.showToast("Claude picked it up")
                case .working:
                    self.delivery = .working(status.message)
                    if let message = status.message { self.showToast(message) }
                case .done:
                    self.delivery = .done(status.message)
                    self.showToast(status.message.map { "Done · \($0)" } ?? "Done", duration: 4)
                case .failed:
                    self.delivery = .failed(status.message)
                    self.showToast(status.message.map { "Claude couldn't finish · \($0)" } ?? "Claude couldn't finish", duration: 5)
                }
                if status.isFinal {
                    try? await Task.sleep(for: .seconds(6))
                    if self.delivery?.isFinal == true { self.delivery = nil }
                    return
                }
            }
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
}
#endif
