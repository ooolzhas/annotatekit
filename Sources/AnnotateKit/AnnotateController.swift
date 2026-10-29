// Annotate-mode state machine, observed by the overlay views.
// Start → freeze-frame: the app is captured (pixels + visible-text outline) and the overlay shows
// that still image, so what you annotate is exactly what gets sent and coordinates can't drift.
// Every touch is classified by `PointerIntent`:
// - Draw (the default): a touch that travels past the move threshold is a white pen stroke. With no
//   pin open, the finished stroke opens a new sketch pin; while a pin is open, every further stroke
//   joins that pin, whatever its kind, so you can keep drawing as long as the comment card is up.
//   A saved sketch is framed by its strokes and attributed to the view it was drawn over.
// - Tap: finishes the open pin, then selects the whole element under the finger (no label chip);
//   nothing distinct under it → nothing happens. ↑↓ walks element → containers.
// - Hold: finishes the open pin, then drops a spot pin at the touch-down point. The only way to
//   make a spot.
// The comment card docks to the keyboard (`chromeBottom`), never to the marker. A pin can carry up
// to `maxAttachments` reference images, kept beside the pin and handed to Send. With no pin open the
// review bar shows: × stops (pins kept), trash clears, Send sends and exits. `chrome` resolves which.
// Return / ↑ saves a pin with a comment, × discards it, Esc backs out one level, ⌘Z undoes.
// Send → hands a SendJob to BundleRenderer off the main thread (1x/annotated images, crops,
// attachments, PNG encoding, write, prune), then polls status.json; the launcher pill narrates each
// stage (`delivery` → `launcherStatus`) instead of toasts, so progress stays on screen in one place
// and toasts are left to in-mode messages. No copy/paste.
// The launcher is a pill centered horizontally above the home indicator, or above the keyboard
// while one is up, whether docked or dragged (Figma 9265:14439); a drag moves it vertically only,
// so it can get out of the way of an app's own bottom bar.
// Live scans (taps, sketch attribution) wait until they match the frozen image: SwiftUI's
// accessibility tree is built right after the bootstrap, and while the comment keyboard is up the
// app's labeled elements must still sit where they froze (an app may re-lay out for any keyboard;
// if it did, the scan waits for the keyboard to go). The overlay itself never moves for the
// keyboard; the card, review bar and launcher pill sit above it. A launch-time start waits for
// the first screen the app settles on.
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
        /// Pen strokes in screen points while the pin is open; rebased into `annotation.sketch` on save.
        var strokes: [Stroke] = []
        /// Reference images; they stay out of `Annotation` until Send writes them into the bundle.
        var images: [AttachedImage] = []
    }

    /// One picked reference image. Equatable by id: comparing pixels on every draft change would be
    /// costly, and an image never changes under its id.
    struct AttachedImage: Identifiable, Equatable {
        let id: UUID
        let image: UIImage

        static func == (lhs: AttachedImage, rhs: AttachedImage) -> Bool { lhs.id == rhs.id }
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
        /// Tiny grayscale sample, to recognize this screen when annotate mode starts on it again.
        let thumbnail: [UInt8]?
        /// Visible-text outline; nil until first needed (see `elements(for:)`).
        var elements: [ScreenElement]?
    }

    /// The touch in progress: identified by its start point (constant across a DragGesture's
    /// changes), so the first change of a new touch can be told apart from a continuing one.
    private struct TouchTrack {
        let start: CGPoint
        let began: Date
        var intent: PointerIntent?
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
    /// The stroke under the finger, in screen points; joins a pin when the finger lifts.
    private(set) var liveStroke: Stroke?
    private(set) var toast: Toast?
    /// Where the user dragged the launcher; nil keeps it docked above the home indicator.
    private(set) var launcherCenterY: CGFloat?
    /// The pill's measured size: its width follows the title, so the hit frame must too.
    /// Starts at the Figma "Annotate" pill (9265:14504) until the view reports.
    private(set) var launcherPillSize = CGSize(width: 104, height: 44)
    /// The still image shown under the overlay while annotating.
    private(set) var frozenImage: UIImage?
    private(set) var currentScreen = 0
    /// Progress of the most recent Send, read back from the bundle's status.json; nil once the
    /// launcher has gone back to idle.
    private(set) var delivery: DeliveryStage?
    /// The agent listening for Sends, from `agent.json`; nil when none is (the pill's dot).
    private(set) var agent: AgentPresence?
    /// Top of the software keyboard (or hardware-keyboard bar) in overlay points while it's up.
    private(set) var keyboardTop: CGFloat?

    @ObservationIgnored private var screens: [Int: CapturedScreen] = [:]
    /// Saved pins' reference images in pick order. Kept off `Annotation` so pins stay Codable and
    /// cheap to compare; Send hands them to the bundle writer.
    @ObservationIgnored private var attachmentImages: [UUID: [UIImage]] = [:]
    @ObservationIgnored private var touch: TouchTrack?
    /// Fires the hold once a touch has stayed still for `PointerIntent.holdDuration`.
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?
    /// Times out a stage that shows outside the poll loop (`notSaved`, `unclaimed`), so the poll
    /// keeps running while it waits; a new Send cancels it.
    @ObservationIgnored private var deliveryHold: Task<Void, Never>?
    /// The latest Send's write completion; a newer Send cancels it so a stale outcome is dropped.
    @ObservationIgnored private var deliveryWrite: Task<Void, Never>?
    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
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
    static let spotSize: CGFloat = 44
    /// Reference images per pin. No Figma frame; keeps bundles small.
    static let maxAttachments = 4
    /// Pen samples closer than this to the previous one are dropped, keeping paths light (as 0.1.x did).
    private static let strokeSampleSpacing: CGFloat = 1.5
    /// Padding around a drawing's strokes when it becomes a pin's frame. OverlayRoot undoes it to
    /// place the sketch badge on the strokes' own corner.
    nonisolated static let sketchPadding: CGFloat = 8
    /// Longest wait for SwiftUI's accessibility tree after the bootstrap; pure UIKit apps never
    /// grow accessibility nodes and wait this out once.
    static let warmUpTimeout: Double = 0.8
    /// Longest wait for our keyboard to go away before a scan goes ahead anyway.
    static let keyboardTimeout: Double = 0.8

    func configure(options: AnnotateOptions, callerFile: String) {
        self.options = options
        self.callerFile = callerFile
        observeLifecycle()
        startPresence()
        resumeDelivery()
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
        holdTask?.cancel()
        holdTask = nil
        touch = nil
        liveStroke = nil
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

    /// Every change of the overlay's touch; the first call of a touch is its touch-down.
    func touchChanged(start: CGPoint, location: CGPoint) {
        if touch?.start != start { beginTouch(at: start) }
        guard var track = touch else { return }
        switch track.intent {
        case nil:
            let distance = Double(hypot(location.x - start.x, location.y - start.y))
            let elapsed = Date().timeIntervalSince(track.began)
            guard PointerIntent.classify(distance: distance, duration: elapsed, isEnded: false) == .draw else { return }
            track.intent = .draw
            touch = track
            holdTask?.cancel()
            holdTask = nil
            liveStroke = Stroke(tool: .pen, points: [AnnotationPoint(start), AnnotationPoint(location)])
        case .draw:
            appendToLiveStroke(location)
        case .hold, .tap:
            // A hold already dropped its spot; moving afterwards doesn't turn it into a stroke
            return
        }
    }

    func touchEnded(start: CGPoint, location: CGPoint) {
        holdTask?.cancel()
        holdTask = nil
        guard let track = touch, track.start == start else {
            touch = nil
            liveStroke = nil
            return
        }
        touch = nil
        let distance = Double(hypot(location.x - start.x, location.y - start.y))
        let elapsed = Date().timeIntervalSince(track.began)
        // An ended touch always classifies; `.tap` is only the fallback for the optional's sake
        let intent = track.intent ?? PointerIntent.classify(distance: distance, duration: elapsed, isEnded: true) ?? .tap
        switch intent {
        case .draw:
            // A fast flick can end before any change crossed the threshold: start the stroke here
            var stroke = liveStroke ?? Stroke(tool: .pen, points: [AnnotationPoint(start)])
            if stroke.points.last != AnnotationPoint(location) {
                stroke.points.append(AnnotationPoint(location))
            }
            liveStroke = nil
            commitStroke(stroke)
        case .hold:
            liveStroke = nil
            // The timer already dropped the spot unless the touch lifted just before it fired
            if track.intent == nil { hold(at: start) }
        case .tap:
            liveStroke = nil
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
        // Spots come only from a hold; a tap on nothing distinct does nothing
        guard stack.current != nil else {
            selection = nil
            return
        }
        selection = stack
        draft = Draft(annotation: annotation(for: stack, updating: nil), isNew: true)
    }

    /// ↑ (`expand`) / ↓ — retarget the unsaved pin: element → enclosing containers.
    func adjustSelection(expand: Bool) {
        guard var stack = selection, var current = draft, current.isNew else { return }
        guard expand ? stack.expand() : stack.narrow() else { return }
        selection = stack
        current.annotation = annotation(for: stack, updating: current.annotation)
        draft = current
    }

    private func beginTouch(at start: CGPoint) {
        holdTask?.cancel()
        touch = TouchTrack(start: start, began: Date(), intent: nil)
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(PointerIntent.holdDuration))
            guard let self, !Task.isCancelled, var track = self.touch, track.start == start, track.intent == nil else { return }
            track.intent = .hold
            self.touch = track
            self.hold(at: start)
        }
    }

    private func appendToLiveStroke(_ location: CGPoint) {
        guard var stroke = liveStroke else { return }
        if let last = stroke.points.last?.cgPoint,
           hypot(location.x - last.x, location.y - last.y) < Self.strokeSampleSpacing {
            return
        }
        stroke.points.append(AnnotationPoint(location))
        liveStroke = stroke
    }

    /// A finished stroke joins the open pin, or opens a new sketch pin when none is open.
    private func commitStroke(_ stroke: Stroke) {
        guard stroke.points.count >= 2 else { return }
        if draft != nil {
            draft?.strokes.append(stroke)
            return
        }
        cancelPendingTap()
        selection = nil
        let sketch = Annotation(
            index: 0,
            screen: currentScreen,
            kind: .sketch,
            frame: AnnotationRect(strokeBounds([stroke]))
        )
        draft = Draft(annotation: sketch, isNew: true, strokes: [stroke])
    }

    /// Drops a spot pin at the touch-down point. Needs no scan: a spot is pinned to the pixel.
    private func hold(at point: CGPoint) {
        finishDraft()
        selection = nil
        let side = Self.spotSize
        let spot = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side).clipped(to: bounds)
        var pin = Annotation(
            index: 0,
            screen: currentScreen,
            kind: .point,
            anchor: AnnotationPoint(point),
            frame: AnnotationRect(spot),
            source: SourceResolver.resolve(frame: spot, in: AnnotatableRegistry.shared.visible(in: bounds))
        )
        pin.nearbyText = ScreenOutline.nearbyText(for: spot, in: elements(for: currentScreen))
        draft = Draft(annotation: pin, isNew: true)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: Draft editing

    /// What the overlay shows: the comment card while a pin is open, the review bar otherwise.
    var chrome: OverlayChrome {
        OverlayChrome.resolve(.init(
            isDraftOpen: draft != nil,
            draftComment: draft?.annotation.comment ?? "",
            pinCount: annotations.count
        ))
    }

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

    func addAttachments(_ images: [UIImage]) {
        guard let current = draft else { return }
        let room = Self.maxAttachments - current.images.count
        guard room > 0 else { return }
        draft?.images.append(contentsOf: images.prefix(room).map { AttachedImage(id: UUID(), image: $0) })
    }

    func removeAttachment(_ id: UUID) {
        draft?.images.removeAll { $0.id == id }
    }

    /// ↑ / Return: saves only once there's a comment, so the button and key agree with `chrome`.
    func submitDraft() {
        guard case .composing(canSubmit: true) = chrome else { return }
        saveDraft()
    }

    /// ×: a new pin is dropped, a reopened one is deleted.
    func discardDraft() {
        guard let current = draft else { return }
        if !current.isNew { removeAnnotation(id: current.annotation.id) }
        clearDraft()
    }

    /// Saves the draft as a pin, or drops it when there is nothing to act on.
    func saveDraft() {
        guard var current = draft else { return }
        defer { clearDraft() }

        if current.strokes.isEmpty {
            current.annotation.sketch = nil
        } else {
            if current.annotation.kind == .sketch {
                // A drawing's pin is framed by what was drawn, not where it started
                let area = strokeBounds(current.strokes).padded(by: Self.sketchPadding).clipped(to: bounds)
                current.annotation.frame = AnnotationRect(area)
                current.annotation.anchor = AnnotationPoint(x: area.midX, y: area.midY)
                current.annotation.nearbyText = ScreenOutline.nearbyText(for: area, in: elements(for: currentScreen))
            }
            let frame = current.annotation.frame.cgRect
            current.annotation.sketch = Sketch(
                size: AnnotationSize(frame.size),
                strokes: current.strokes.map { stroke in
                    Stroke(tool: stroke.tool, points: stroke.points.map { AnnotationPoint(x: $0.x - frame.minX, y: $0.y - frame.minY) })
                }
            )
        }

        let id = current.annotation.id
        let hasImages = !current.images.isEmpty
        guard !current.annotation.isEmpty || hasImages else {
            if !current.isNew { removeAnnotation(id: id) }
            return
        }
        attachmentImages[id] = hasImages ? current.images.map(\.image) : nil
        if current.isNew {
            current.annotation.index = annotations.count + 1
            annotations.append(current.annotation)
            if current.annotation.kind == .sketch {
                attributeSketch(id, drawn: strokeBounds(current.strokes))
            }
        } else if let position = annotations.firstIndex(where: { $0.id == id }) {
            annotations[position] = current.annotation
        }
    }

    /// Esc: closes the card without saving; a reopened pin stays as it was.
    func cancelDraft() {
        clearDraft()
    }

    func openExisting(_ id: UUID) {
        finishDraft()
        guard let pin = annotations.first(where: { $0.id == id }) else { return }
        draft = Draft(
            annotation: pin,
            isNew: false,
            strokes: pin.sketchInScreenPoints,
            images: (attachmentImages[id] ?? []).map { AttachedImage(id: UUID(), image: $0) }
        )
    }

    // MARK: Keys

    func escape() {
        if draft != nil {
            cancelDraft()
        } else if selection != nil {
            selection = nil
        } else {
            stop()
        }
    }

    func undo() {
        if let strokes = draft?.strokes, !strokes.isEmpty {
            draft?.strokes.removeLast()
        } else if draft == nil, let last = visibleAnnotations.last {
            removeAnnotation(id: last.id)
            showToast("Removed pin \(last.index)")
        }
    }

    // MARK: Send

    func clearAll() {
        clearDraft()
        annotations.removeAll()
        attachmentImages.removeAll()
        screens = screens.filter { $0.key == currentScreen }
    }

    /// Gathers what's needed on the main actor, clears the overlay at once, and renders, encodes
    /// and writes the bundle off the main thread. The launcher reads "N comments sent" at once and
    /// narrates delivery from there (`trackDelivery`).
    func send(keepAnnotating: Bool) {
        finishDraft()
        guard chrome.canSend else {
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
        let outgoingIDs = Set(outgoing.map(\.id))
        let appWindow = ElementScanner.appWindows(excluding: window).first
        let job = SendJob(
            sessionID: SessionWriter.makeSessionID(),
            app: .current(installFile: callerFile),
            device: .current(window: appWindow ?? window),
            captures: captures,
            annotations: outgoing,
            outputDirectory: outputDirectory(),
            completionNote: options.completionNote,
            includesHiRes: options.includesHiResScreens,
            keepSessions: options.keepsSessions,
            cropPadding: Self.cropPadding,
            attachments: attachmentImages.filter { outgoingIDs.contains($0.key) }
        )

        annotations.removeAll()
        attachmentImages.removeAll()
        if keepAnnotating {
            screens = screens.filter { $0.key == currentScreen }
        } else {
            screens.removeAll()
            stop()
        }
        // A new Send owns the pill: the previous one's write, tracking and holds must not narrate over it
        deliveryWrite?.cancel()
        deliveryTask?.cancel()
        deliveryTask = nil
        deliveryHold?.cancel()
        deliveryHold = nil
        // Set before the write so the pill answers the tap immediately (Figma 9265:14691)
        delivery = .sent(count: outgoing.count)

        deliveryWrite = Task { [weak self] in
            // The detached write isn't cancelled with this task, so the bundle still lands
            let outcome = await Task.detached(priority: .userInitiated) { BundleRenderer.write(job) }.value
            guard let self else { return }
            // A failed write's prompt is the user's only copy of it, so it's copied even when a newer
            // Send superseded this one. The opt-in copy of a successful write is skipped once
            // superseded, so it can't clobber the newer Send's prompt.
            if outcome.error != nil || (self.options.copiesPromptToClipboard && !Task.isCancelled) {
                UIPasteboard.general.string = outcome.prompt
            }
            guard !Task.isCancelled else { return }
            self.deliveryWrite = nil
            if outcome.error != nil {
                // The prompt is on the clipboard already; the pill says so instead of a toast
                self.delivery = .notSaved
                self.clearDelivery(ifStill: .notSaved, after: LauncherStatus.finalHold)
                return
            }
            if self.agent == nil {
                // Nothing is listening: say so now rather than after `unclaimedAfter`. Tracking still
                // runs, so an agent that connects in time picks it up and narrates over this.
                self.delivery = .noAgent
                self.clearDelivery(ifStill: .noAgent, after: LauncherStatus.finalHold)
            }
            self.trackDelivery(id: job.sessionID, in: job.outputDirectory)
        }
    }

    // MARK: Chrome

    /// Bounds inside the safe area with a small margin; the launcher stays within it.
    var safeBounds: CGRect {
        bounds.inset(by: UIEdgeInsets(
            top: safeInsets.top + 8,
            left: safeInsets.left + 8,
            bottom: safeInsets.bottom + 8,
            right: safeInsets.right + 8
        ))
    }

    /// Review bar height, Figma 9257:13549.
    static let barHeight: CGFloat = 60
    /// Launcher pill height, Figma 9265:14504 (`h-[44px]`; it wins over py-8 + the 22pt line).
    static let launcherHeight: CGFloat = 44
    /// Gap between the docked pill and `chromeBottom`, Figma container 9265:14502 (`pb-[8px]`).
    static let launcherBottomGap: CGFloat = 8
    /// Extra touch slop around the pill on every side, so a near miss still opens annotate mode.
    static let launcherHitSlop: CGFloat = 4

    /// Lowest y bottom chrome (comment card, review bar, toasts) may reach: above the home
    /// indicator, or above the keyboard while it's up.
    var chromeBottom: CGFloat {
        let screenBottom = bounds.maxY - max(safeInsets.bottom, 12)
        return keyboardTop.map { min($0, screenBottom) } ?? screenBottom
    }

    /// What the launcher pill says: the delivery stage while one is showing, otherwise idle with
    /// the pins kept from earlier (saved but not sent).
    var launcherStatus: LauncherStatus {
        .resolve(.init(delivery: delivery, pendingCount: annotations.count))
    }

    /// The pill in overlay points: centered horizontally, docked 8pt above `chromeBottom` (so it
    /// rides the keyboard like the rest of the bottom chrome) unless the user dragged it.
    var launcherFrame: CGRect {
        let height = Self.launcherHeight
        let width = launcherPillSize.width
        // Clamped on read too: a rotation or safe-area change can leave a dragged position off screen
        let centerY = launcherCenterY.flatMap { clampedLauncherCenterY($0) }
        let maxY = centerY.map { $0 + height / 2 } ?? chromeBottom - Self.launcherBottomGap
        return CGRect(x: bounds.midX - width / 2, y: maxY - height, width: width, height: height)
    }

    /// Touch target the overlay window accepts while annotate mode is off.
    var launcherHitFrame: CGRect {
        guard options.showsLauncher else { return .zero }
        return launcherFrame.insetBy(dx: -Self.launcherHitSlop, dy: -Self.launcherHitSlop)
    }

    /// The pill's measured size from the view. Equal sizes are dropped: every write would
    /// invalidate `launcherFrame` readers even when nothing moved.
    func updateLauncherSize(_ size: CGSize) {
        guard launcherPillSize != size else { return }
        launcherPillSize = size
    }

    /// Vertical drag only: x stays centered, y is clamped so the whole pill stays in the safe area.
    func moveLauncher(toCenterY y: CGFloat) {
        guard let clamped = clampedLauncherCenterY(y) else { return }
        if launcherCenterY != clamped { launcherCenterY = clamped }
    }

    /// Range a dragged pill's center may take. The lowest center is the docked one, derived from
    /// `chromeBottom` like the docked frame, so there's one bottom edge either way (`safeBounds`
    /// would differ when the bottom inset is under 12). nil before the first layout, when the
    /// area is smaller than the pill and there's nothing to clamp to.
    private func clampedLauncherCenterY(_ y: CGFloat) -> CGFloat? {
        let half = Self.launcherHeight / 2
        let top = safeBounds.minY + half
        let bottom = chromeBottom - Self.launcherBottomGap - half
        guard bottom >= top else { return nil }
        return min(max(y, top), bottom)
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

    /// Captures the app as it looks right now. Back on a screen that already has pins, that screen's
    /// freeze-frame comes back instead, so its pins show again exactly where they were drawn.
    /// Otherwise it's a new screen; screens with no pins are dropped, so opening and closing
    /// annotate mode doesn't pile up empty ones.
    private func freezeScreen() {
        guard let image = Snapshotter.captureApp(excluding: window) else {
            frozenImage = nil
            return
        }
        let thumbnail = Snapshotter.grayThumbnail(of: image)
        let pinned = Set(annotations.map(\.screen))
        screens = screens.filter { pinned.contains($0.key) }
        let candidates = screens.values.compactMap { screen in screen.thumbnail.map { (index: screen.index, pixels: $0) } }
        if let thumbnail, let index = ScreenMatch.match(thumbnail, among: candidates), let revisited = screens[index] {
            currentScreen = index
            frozenImage = revisited.image
            return
        }
        let index = (screens.keys.max() ?? 0) + 1
        screens[index] = CapturedScreen(index: index, capturedAt: Date(), image: image, thumbnail: thumbnail)
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

    /// Commits a draft with content, drops an empty one (`saveDraft` decides). Called before any
    /// new interaction.
    private func finishDraft() {
        cancelPendingTap()
        guard draft != nil else { return }
        saveDraft()
    }

    private func clearDraft() {
        cancelPendingTap()
        draft = nil
        selection = nil
    }

    private func cancelPendingTap() {
        pendingTap?.cancel()
        pendingTap = nil
    }

    /// Bounds of every point in `strokes`, screen points; a zero-size rect at a lone point.
    private func strokeBounds(_ strokes: [Stroke]) -> CGRect {
        let points = strokes.flatMap(\.points)
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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

    /// The comment keyboard: `keyboardTop` keeps the card above it, and live scans wait until it's
    /// fully gone (`isKeyboardShown` holds until didHide), because an app may re-lay out for any
    /// keyboard while the overlay keeps showing the frozen image.
    private func observeKeyboard() {
        guard keyboardObservers.isEmpty else { return }
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                MainActor.assumeIsolated { self?.keyboardFrameWillChange(to: end) }
            },
            center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isKeyboardShown = false }
            }
        ]
    }

    /// Only marks the keyboard as up for scan gating; where it sits comes from the layout guide
    /// (`updateKeyboardGuide`), because notifications can end on a stale frame.
    private func keyboardFrameWillChange(to screenFrame: CGRect?) {
        guard let screenFrame, let window else { return }
        let frame = window.convert(screenFrame, from: window.screen.coordinateSpace)
        // Off screen or zero height: hidden, undocked or floating
        guard frame.height >= 1, frame.minY < bounds.maxY else { return }
        isKeyboardShown = true
    }

    /// The keyboard's top edge from OverlayHostingController's keyboard layout guide, which sits on the
    /// safe-area bottom when there's no keyboard. Notifications alone left the card 27pt low after the
    /// photo picker: the suggestion bar can appear without a frame-change notification.
    func updateKeyboardGuide(top: CGFloat) {
        let restingTop = bounds.maxY - safeInsets.bottom
        let newTop: CGFloat? = top < restingTop - 1 ? top : nil
        if keyboardTop != newTop { keyboardTop = newTop }
    }

    private func stopObservingKeyboard() {
        for observer in keyboardObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        keyboardObservers = []
        isKeyboardShown = false
    }

    private func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        attachmentImages[id] = nil
        for position in annotations.indices {
            annotations[position].index = position + 1
        }
    }

    /// How long status.json is polled after a Send (the existing cap). Past it the agent is
    /// presumed gone, and a stuck non-final stage is cleared so the pill shows pending pins again.
    nonisolated static let deliveryTrackingLimit: TimeInterval = 3600

    /// Polls status.json written by the receiving agent; the launcher pill narrates each stage.
    private func trackDelivery(id: String, in output: URL) {
        deliveryTask?.cancel()
        deliveryTask = Task { [weak self] in
            let started = Date()
            // Deduped on the mapped stage, not the state: repeated `working` notes carry new messages
            var lastStage: DeliveryStage?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let elapsed = Date().timeIntervalSince(started)
                // Checked for every status, so an agent that died mid-work doesn't pin the pill forever
                if elapsed > Self.deliveryTrackingLimit {
                    if self.delivery?.isFinal == false { self.delivery = nil }
                    return
                }
                guard let status = SessionInbox.readStatus(id: id, in: output) else {
                    // Nobody picked it up: say so briefly, then go back to idle. Polling goes on,
                    // because a watcher started late still claims the bundle.
                    if elapsed > self.options.unclaimedAfter, case .sent = self.delivery {
                        self.delivery = .unclaimed
                        self.clearDelivery(ifStill: .unclaimed, after: LauncherStatus.unclaimedHold)
                    }
                    continue
                }
                let stage = Self.stage(for: status)
                guard stage != lastStage else { continue }
                lastStage = stage
                // A status that lands while "not picked up" is still showing replaces it
                self.deliveryHold?.cancel()
                self.deliveryHold = nil
                self.delivery = stage
                if stage.isFinal {
                    try? await Task.sleep(for: .seconds(LauncherStatus.finalHold))
                    // Cancelled means a newer Send owns the pill; leave it alone
                    if !Task.isCancelled, self.delivery == stage { self.delivery = nil }
                    return
                }
            }
        }
    }

    /// Seconds after an agent's final status during which a fresh launch still shows it: an agent
    /// that rebuilds and reinstalls the app reports "done" around the relaunch.
    nonisolated static let resumeFinalWindow: TimeInterval = 60

    /// Picks the newest Send's narration back up after a relaunch, since an agent that reinstalls the
    /// app restarts it mid-delivery. Skipped when that Send is over an hour old or long finished.
    private func resumeDelivery() {
        let output = outputDirectory()
        Task { [weak self] in
            let resumable = await Task.detached(priority: .utility) { () -> String? in
                guard let id = SessionInbox.sessionIDs(in: output).last,
                      let session = try? SessionInbox.loadSession(id: id, in: output),
                      Date().timeIntervalSince(session.createdAt) < Self.deliveryTrackingLimit else { return nil }
                guard let status = SessionInbox.readStatus(id: id, in: output), status.isFinal else { return id }
                return Date().timeIntervalSince(status.updatedAt) < Self.resumeFinalWindow ? id : nil
            }.value
            guard let self, let resumable, self.deliveryTask == nil, self.delivery == nil else { return }
            self.trackDelivery(id: resumable, in: output)
        }
    }

    private static func stage(for status: SessionStatus) -> DeliveryStage {
        switch status.state {
        case .delivered: .delivered
        case .received: .received
        case .working: .working(message: status.message)
        case .done: .done(message: status.message)
        case .failed: .failed(message: status.message)
        }
    }

    /// Returns the launcher to idle after `seconds`, unless the stage changed meanwhile. Runs beside
    /// the poll loop rather than inside it, so tracking keeps going during the hold.
    private func clearDelivery(ifStill stage: DeliveryStage, after seconds: Double) {
        deliveryHold?.cancel()
        deliveryHold = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.delivery == stage else { return }
            self.delivery = nil
        }
    }

    // MARK: Presence

    /// Reads `agent.json` every `AgentPresenceFile.interval` while the app is in the foreground. On a
    /// device it also rewrites `app.json`, which tells the Mac this build is open (so it polls
    /// quickly) and which checkout it came from. Two tiny files, off the main thread.
    private func startPresence() {
        guard presenceTask == nil else { return }
        let output = outputDirectory()
        let beacon = projectRoot == nil
            ? AppBeacon(bundleID: Bundle.main.bundleIdentifier, installFile: callerFile)
            : nil
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                let presence = await Task.detached(priority: .utility) { () -> AgentPresence? in
                    if let beacon, let data = try? AnnotationSession.encoder.encode(beacon) {
                        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                        try? data.write(to: output.appendingPathComponent(AgentPresenceFile.appFile), options: .atomic)
                    }
                    return AgentPresenceFile.read(in: output)
                }.value
                guard let self, !Task.isCancelled else { return }
                if self.agent != presence { self.agent = presence }
                try? await Task.sleep(for: .seconds(AgentPresenceFile.interval))
            }
        }
    }

    private func stopPresence() {
        presenceTask?.cancel()
        presenceTask = nil
    }

    /// Presence pauses in the background: nobody sees the dot, and on a device a stale `app.json`
    /// is what tells the Mac to poll slowly.
    private func observeLifecycle() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopPresence() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.startPresence() }
            }
        ]
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
