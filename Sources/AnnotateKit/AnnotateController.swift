// Annotate-mode state machine, observed by the overlay views.
// Start → freeze-frame: the app is captured (pixels + visible-text outline) and the overlay shows
// that still image, so what you annotate is exactly what gets sent and coordinates can't drift.
// Tap → SelectionStack of everything under the finger; a tap on nothing distinct pins the spot
// itself, so every pixel is annotatable. ↑↓ walks spot → element → containers.
// Drag → region with sketch tools. Draw mode → the whole frozen screen is a canvas; the drawing
// becomes one pin framed by its bounds and attributed to the view it was drawn over.
// Return saves, Esc backs out one level, ⌘Z undoes.
// Send → hands a SendJob to BundleRenderer off the main thread (1x/annotated images, crops, PNG
// encoding, write, prune), then polls status.json so the overlay can show the agent picking it up
// and finishing. No copy/paste.
// Live scans (taps, sketch attribution) wait until they match the frozen image: SwiftUI's
// accessibility tree is built right after the bootstrap, and while the comment keyboard is up the
// app's labeled elements must still sit where they froze (an app may re-lay out for any keyboard;
// if it did, the scan waits for the keyboard to go). The overlay itself never moves for the
// keyboard; the card and toolbar sit above it. A launch-time start waits for the first screen the
// app settles on.
// Idle cost is near zero: the accessibility tree and `.annotatable()` frame tracking switch on
// only while annotating, and the text outline is scanned once the tree is warm.

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
        /// Visible-text outline; nil until first needed (see `elements(for:)`).
        var elements: [ScreenElement]?
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
    /// Draw mode: drags make strokes anywhere instead of selecting or making regions.
    private(set) var isDrawing = false
    /// Top of the software keyboard (or hardware-keyboard bar) in overlay points while it's up.
    private(set) var keyboardTop: CGFloat?

    @ObservationIgnored private var screens: [Int: CapturedScreen] = [:]
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    @ObservationIgnored private var launchStart: Task<Void, Never>?
    @ObservationIgnored private var accessibilityWarmUp: Task<Void, Never>?
    @ObservationIgnored private var isTreeWarm = false
    /// The outline the warm-up took, before any keyboard: the reference for "has the app moved".
    @ObservationIgnored private var frozenOutline: (screen: Int, elements: [ScreenElement])?
    @ObservationIgnored private var isKeyboardShown = false
    @ObservationIgnored private var keyboardObservers: [NSObjectProtocol] = []
    /// A tap waiting for scans to match the frozen image; a newer interaction replaces it.
    @ObservationIgnored private var pendingTap: Task<Void, Never>?
    @ObservationIgnored private var pendingAttributions: [Task<Void, Never>] = []

    static let cropPadding: CGFloat = 32
    static let minimumRegionSide: CGFloat = 16
    static let dragThreshold: CGFloat = 6
    static let spotSize: CGFloat = 44
    /// Selection chip height plus its gap above the box.
    static let chipClearance: CGFloat = 24
    /// Longest wait for SwiftUI's accessibility tree after the bootstrap; pure UIKit apps never
    /// grow accessibility nodes and wait this out once.
    static let warmUpTimeout: Double = 0.8
    /// Longest wait for our keyboard to go away before a scan goes ahead anyway.
    static let keyboardTimeout: Double = 0.8

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
        launchStart?.cancel()
        launchStart = nil
        // Paid only once someone actually annotates, not on every DEBUG launch
        if options.enablesAccessibilityTree {
            AccessibilityBootstrap.enable()
        }
        AnnotatableRegistry.shared.setCollecting(true)
        freezeScreen()
        isActive = true
        observeKeyboard()
        window?.activate()
        warmUpAccessibility()
    }

    func stop() {
        guard isActive else { return }
        finishDraft()
        selection = nil
        dragRect = nil
        isActive = false
        frozenImage = nil
        accessibilityWarmUp?.cancel()
        pendingAttributions.forEach { $0.cancel() }
        pendingAttributions.removeAll()
        stopObservingKeyboard()
        AnnotatableRegistry.shared.setCollecting(false)
        window?.deactivate()
    }

    /// Launch-time start (`ANNOTATE=1`): freezes the first screen the app settles on instead of
    /// its launch screen or splash (see `LaunchSettle`). `<key>_DELAY=<seconds>` in the launch
    /// environment waits a fixed time instead, for apps whose splash holds still for longer.
    func startWhenSettled() {
        guard !isActive, launchStart == nil else { return }
        let delayKey = options.launchEnvironmentKey + "_DELAY"
        let fixedDelay = ProcessInfo.processInfo.environment[delayKey].flatMap(Double.init)
        launchStart = Task { [weak self] in
            if let fixedDelay {
                try? await Task.sleep(for: .seconds(max(fixedDelay, 0)))
            } else {
                var settle = LaunchSettle()
                var activeAge = 0.0
                var lastTick = Date()
                while !Task.isCancelled {
                    guard let self else { return }
                    let now = Date()
                    // Only active time counts: a permission alert at first launch makes the scene
                    // inactive, and apps often hold their splash still until they're active again
                    if self.window?.windowScene?.activationState == .foregroundActive {
                        activeAge += now.timeIntervalSince(lastTick)
                        if settle.observe(Snapshotter.grayThumbnail(excluding: self.window), at: activeAge) { break }
                    } else {
                        settle.interrupt()
                    }
                    lastTick = now
                    try? await Task.sleep(for: .seconds(LaunchSettle.interval))
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.launchStart = nil
            self.start()
        }
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
        guard isScannable else {
            pendingTap = Task { [weak self] in
                await self?.untilScannable()
                guard let self, !Task.isCancelled, self.isActive else { return }
                self.pendingTap = nil
                self.select(at: point)
            }
            return
        }
        select(at: point)
    }

    private func select(at point: CGPoint) {
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
        region.nearbyText = ScreenOutline.nearbyText(for: rect, in: elements(for: currentScreen))
        draft = Draft(annotation: region, isNew: true)
    }

    // MARK: Draw mode

    func toggleDrawing() {
        if isDrawing {
            saveDraft()
        } else {
            beginDrawing()
        }
    }

    /// Opens a full-screen sketch draft; strokes stay in screen points until it's saved.
    func beginDrawing() {
        finishDraft()
        selection = nil
        let canvas = Annotation(
            index: 0,
            screen: currentScreen,
            kind: .sketch,
            frame: AnnotationRect(bounds),
            sketch: Sketch(size: AnnotationSize(bounds.size))
        )
        draft = Draft(annotation: canvas, isNew: true)
        isDrawing = true
    }

    /// Bounds of what's been drawn so far, in screen points (nil before the first stroke).
    var drawingBounds: CGRect? {
        guard let draft, draft.annotation.kind == .sketch else { return nil }
        let points = (draft.annotation.sketch?.strokes ?? []).flatMap(\.points)
        guard let first = points.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        let origin = isDrawing ? CGPoint.zero : draft.annotation.frame.cgRect.origin
        return CGRect(x: minX + origin.x, y: minY + origin.y, width: maxX - minX, height: maxY - minY)
    }

    /// What the comment card and toolbar should stay clear of for `draft`.
    func focusFrame(for draft: Draft) -> CGRect {
        if draft.annotation.kind == .sketch, isDrawing {
            // Before anything is drawn, park the card near the bottom
            return drawingBounds?.padded(by: 8)
                ?? CGRect(x: bounds.midX, y: bounds.maxY - safeInsets.bottom - 60, width: 0, height: 0)
        }
        let frame = draft.annotation.frame.cgRect
        guard draft.annotation.kind == .element || draft.annotation.kind == .point else { return frame }
        // Leave room for the selection chip above the box, so a card placed above doesn't cover it
        let chip = Self.chipClearance
        return CGRect(x: frame.minX, y: frame.minY - chip, width: frame.width, height: frame.height + chip)
    }

    // MARK: Draft editing

    /// Text of the open draft's comment.
    var commentText: String {
        draft?.annotation.comment ?? ""
    }

    /// Comment edits from the card opened for draft `id`. The keyboard delivers text out of
    /// process, so a card that a tap just replaced can still write late input; it's dropped
    /// instead of landing in the next pin's comment.
    func setComment(_ text: String, forDraft id: UUID) {
        guard draft?.annotation.id == id else { return }
        draft?.annotation.comment = text
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
        var drawnArea: CGRect?
        if current.isNew, current.annotation.kind == .sketch, isDrawing {
            drawnArea = drawingBounds
            current.annotation = settledSketch(current.annotation)
        }
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
            if let drawnArea { attributeSketch(current.annotation.id, drawn: drawnArea) }
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
        if isDrawing {
            cancelDraft()
        } else if draft?.isEditingText == true {
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

    /// Gathers what's needed on the main actor, clears the overlay at once, and renders, encodes
    /// and writes the bundle off the main thread; the toast and delivery ring follow when it lands.
    func send(keepAnnotating: Bool) {
        finishDraft()
        guard !annotations.isEmpty else {
            showToast("Nothing to send yet")
            return
        }

        var outgoing = annotations
        if let root = projectRoot {
            for position in outgoing.indices {
                if let file = outgoing[position].source?.file {
                    outgoing[position].source?.file = ProjectRoot.relativePath(of: file, to: root)
                }
            }
        }
        let pinnedScreens = Set(outgoing.map(\.screen))
        let captures = screens.keys.sorted().filter(pinnedScreens.contains).compactMap { index -> SendJob.Capture? in
            guard let captured = screens[index] else { return nil }
            return SendJob.Capture(index: index, capturedAt: captured.capturedAt, image: captured.image, elements: elements(for: index))
        }
        let appWindow = ElementScanner.appWindows(excluding: window).first
        let job = SendJob(
            sessionID: SessionWriter.makeSessionID(),
            app: .current,
            device: .current(window: appWindow ?? window),
            captures: captures,
            annotations: outgoing,
            outputDirectory: outputDirectory(),
            completionNote: options.completionNote,
            includesHiRes: options.includesHiResScreens,
            keepSessions: options.keepsSessions,
            cropPadding: Self.cropPadding
        )

        annotations.removeAll()
        if keepAnnotating {
            screens = screens.filter { $0.key == currentScreen }
        } else {
            screens.removeAll()
            stop()
        }
        deliveryTask?.cancel()
        delivery = .waiting

        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { BundleRenderer.write(job) }.value
            guard let self else { return }
            if self.options.copiesPromptToClipboard || outcome.error != nil {
                UIPasteboard.general.string = outcome.prompt
            }
            if let error = outcome.error {
                self.delivery = nil
                self.showToast("Couldn't write the session (\(error)). Prompt copied instead.", duration: 5)
                return
            }
            self.showToast("Sent \(outcome.pinCount) \(outcome.pinCount == 1 ? "pin" : "pins")")
            self.trackDelivery(id: job.sessionID, in: job.outputDirectory)
        }
    }

    // MARK: Chrome

    var hint: String {
        if let draft {
            if isDrawing { return "Draw anywhere · Return to save · ⌘Z undo" }
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
        case .sketch: name = annotation.element.map { "Sketch over \($0.displayName(maxLabelLength: 18))" } ?? "Sketch"
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
        let focus = dragRect ?? draft.map { focusFrame(for: $0) }
        guard let focus, bounds.height > 0 else { return false }
        return focus.maxY > (keyboardTop ?? bounds.height) * 0.6
    }

    static let toolbarHeight: CGFloat = 44
    static let launcherSize: CGFloat = 44

    /// Lowest y bottom chrome (toolbar, toasts) may reach: above the home indicator, or above the
    /// keyboard while it's up.
    var chromeBottom: CGFloat {
        let screenBottom = bounds.maxY - max(safeInsets.bottom, 12)
        return keyboardTop.map { min($0, screenBottom) } ?? screenBottom
    }

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
        let reuse = currentScreen > 0 && !annotations.contains { $0.screen == currentScreen }
        let index = reuse ? currentScreen : (screens.keys.max() ?? 0) + 1
        screens[index] = CapturedScreen(index: index, capturedAt: Date(), image: image)
        currentScreen = index
        frozenImage = image
    }

    /// The screen's visible-text outline, scanned on first use rather than at freeze time: entering
    /// annotate mode stays a single capture, and the accessibility tree (switched on lazily in
    /// `start`) has settled by the time the first pin needs nearby text.
    private func elements(for index: Int) -> [ScreenElement] {
        guard let captured = screens[index] else { return [] }
        if let elements = captured.elements { return elements }
        let bounds = CGRect(origin: .zero, size: captured.image.size)
        let elements = index == currentScreen && isActive
            ? ScreenOutline.normalized(ElementScanner.outline(excluding: window), in: bounds)
            : []
        screens[index]?.elements = elements
        return elements
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
            in: elements(for: currentScreen),
            excluding: result.element?.label
        )
        return result
    }

    /// Commits a draft with content, drops an empty one. Called before any new interaction.
    private func finishDraft() {
        cancelPendingTap()
        guard let current = draft else { return }
        if current.isNew && current.annotation.isEmpty && !current.isEditingText {
            clearDraft()
        } else {
            saveDraft()
        }
    }

    private func clearDraft() {
        cancelPendingTap()
        draft = nil
        selection = nil
        isDrawing = false
    }

    private func cancelPendingTap() {
        pendingTap?.cancel()
        pendingTap = nil
    }

    /// Turns a full-screen drawing into a pin: frame = stroke bounds (padded), points rebased to
    /// it, and nearby text. `attributeSketch` names the view it was drawn over.
    private func settledSketch(_ annotation: Annotation) -> Annotation {
        guard let drawn = drawingBounds, let strokes = annotation.sketch?.strokes, !strokes.isEmpty else { return annotation }
        let frame = drawn.padded(by: 8).clipped(to: bounds)
        var result = annotation
        result.frame = AnnotationRect(frame)
        result.anchor = AnnotationPoint(x: frame.midX, y: frame.midY)
        result.sketch = Sketch(
            size: AnnotationSize(frame.size),
            strokes: strokes.map { stroke in
                Stroke(tool: stroke.tool, points: stroke.points.map { AnnotationPoint(x: $0.x - frame.minX, y: $0.y - frame.minY) })
            }
        )

        result.nearbyText = ScreenOutline.nearbyText(for: frame, in: elements(for: currentScreen), excluding: nil)
        return result
    }

    /// Attributes a saved drawing to the smallest real view under it that encloses it. That takes a
    /// live scan; drawings are saved with the keyboard up, so if the app has re-laid out for it, this
    /// waits until scans match the frozen image and fills the pin in afterwards.
    private func attributeSketch(_ id: UUID, drawn: CGRect) {
        guard !isScannable else {
            applySketchAttribution(id, drawn: drawn)
            return
        }
        pendingAttributions.append(Task { [weak self] in
            await self?.untilScannable()
            guard let self, !Task.isCancelled, self.isActive else { return }
            self.applySketchAttribution(id, drawn: drawn)
        })
    }

    private func applySketchAttribution(_ id: UUID, drawn: CGRect) {
        guard let position = annotations.firstIndex(where: { $0.id == id }) else { return }
        var pin = annotations[position]
        let center = CGPoint(x: drawn.midX, y: drawn.midY)
        let registered = AnnotatableRegistry.shared.visible(in: bounds)
        let candidates = ElementScanner.candidates(at: center, excluding: window) + registered.map(\.candidate)
        let enclosing = SelectionStack(candidates: candidates, at: center).candidates.first {
            $0.frame.encloses(drawn, tolerance: 6) && $0.frame.area < bounds.area * 0.4
        }
        if var element = enclosing?.info {
            element.breadcrumb = []
            pin.element = element
        }
        pin.source = enclosing?.source ?? SourceResolver.resolve(frame: drawn, in: registered)
        pin.nearbyText = ScreenOutline.nearbyText(for: pin.frame.cgRect, in: elements(for: pin.screen), excluding: pin.element?.label)
        annotations[position] = pin
    }

    // MARK: Scan readiness

    /// Whether a live scan matches the frozen image right now.
    private var isScannable: Bool {
        isTreeWarm && (!isKeyboardShown || liveLayoutMatchesFrozen())
    }

    /// With the keyboard up: the app's labeled elements are still where they were at freeze time.
    private func liveLayoutMatchesFrozen() -> Bool {
        guard let frozenOutline, frozenOutline.screen == currentScreen,
              let captured = screens[currentScreen] else { return false }
        let bounds = CGRect(origin: .zero, size: captured.image.size)
        let live = ScreenOutline.normalized(ElementScanner.outline(excluding: window), in: bounds)
        return !ScreenOutline.hasMoved(from: frozenOutline.elements, to: live)
    }

    /// Waits (bounded) until a live scan matches the frozen image.
    private func untilScannable() async {
        await accessibilityWarmUp?.value
        guard isKeyboardShown else { return }
        let deadline = Date().addingTimeInterval(Self.keyboardTimeout)
        while isKeyboardShown, !liveLayoutMatchesFrozen(), Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(25))
        }
        // One more beat for the app's layout pass once the keyboard is gone
        try? await Task.sleep(for: .milliseconds(30))
    }

    /// Right after the bootstrap SwiftUI has no accessibility nodes: the first query of a hosting
    /// view only schedules the build (they appear about 0.1 s later), so a first tap found nothing
    /// but plumbing and fell back to a spot. Queries until the node count holds steady, then keeps
    /// that walk as this screen's text outline, taken before any keyboard can move the app.
    private func warmUpAccessibility() {
        accessibilityWarmUp?.cancel()
        isTreeWarm = false
        frozenOutline = nil
        let screen = currentScreen
        accessibilityWarmUp = Task { [weak self] in
            let started = Date()
            var previousNodes = -1
            while !Task.isCancelled {
                guard let self, self.isActive else { return }
                let scan = ElementScanner.outlineScan(excluding: self.window)
                // Without the bootstrap there's no tree to wait for: the first walk is the outline
                let isSteady = !self.options.enablesAccessibilityTree
                    || (scan.accessibilityNodes > 0 && scan.accessibilityNodes == previousNodes)
                if isSteady || Date().timeIntervalSince(started) > Self.warmUpTimeout {
                    if isSteady { self.cacheOutline(scan.elements, for: screen) }
                    self.isTreeWarm = true
                    return
                }
                previousNodes = scan.accessibilityNodes
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func cacheOutline(_ outline: [ScreenElement], for index: Int) {
        guard index == currentScreen, let captured = screens[index] else { return }
        let normalized = ScreenOutline.normalized(outline, in: CGRect(origin: .zero, size: captured.image.size))
        frozenOutline = (index, normalized)
        if captured.elements == nil { screens[index]?.elements = normalized }
    }

    /// The comment keyboard: `keyboardTop` keeps the card and toolbar above it, and live scans
    /// wait until it's fully gone (`isKeyboardShown` holds until didHide), because an app may
    /// re-lay out for any keyboard while the overlay keeps showing the frozen image.
    private func observeKeyboard() {
        guard keyboardObservers.isEmpty else { return }
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                MainActor.assumeIsolated { self?.keyboardFrameWillChange(to: end) }
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keyboardTop = nil }
            },
            center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isKeyboardShown = false }
            }
        ]
    }

    private func keyboardFrameWillChange(to screenFrame: CGRect?) {
        guard let screenFrame, let window else { return }
        let frame = window.convert(screenFrame, from: window.screen.coordinateSpace)
        // Off screen or zero height: hidden, undocked or floating
        guard frame.height >= 1, frame.minY < bounds.maxY else {
            keyboardTop = nil
            return
        }
        keyboardTop = frame.minY
        isKeyboardShown = true
    }

    private func stopObservingKeyboard() {
        for observer in keyboardObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        keyboardObservers = []
        isKeyboardShown = false
        keyboardTop = nil
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
