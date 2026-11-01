// The overlay lives in its own UIWindow above the app, so it works for SwiftUI and UIKit apps alike
// and never touches the app's view hierarchy.
// Idle: the window only accepts touches on the launcher; everything else falls through to the app.
// Active: it takes every touch and becomes key so Return / Esc / ↑↓ / ⌘Z arrive as key commands.
// OverlayInstaller attaches the window once a scene is active (`install` may run before that); a
// launch-time start then waits for the app's first settled screen.
// With the launcher hidden, no window exists until annotate mode first starts.

#if DEBUG && canImport(UIKit)
#if canImport(AnnotateCore) // the CocoaPods build compiles AnnotateCore into this module
import AnnotateCore
#endif
import SwiftUI
import UIKit

@MainActor
final class OverlayInstaller {
    static let shared = OverlayInstaller()

    let controller = AnnotateController()
    private var window: OverlayWindow?
    private var observer: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private var isInstalled = false

    func install(options: AnnotateOptions, callerFile: String) {
        guard !isInstalled else { return }
        isInstalled = true
        controller.configure(options: options, callerFile: callerFile)
        observeActivation()
        // A window outlives a scene the system discards and replaces (seen on a device after a launch
        // while it was locked): the pill then lived on a dead scene and never showed. Re-attach.
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let scene = notification.object as? UIScene
            MainActor.assumeIsolated { self?.detach(ifOn: scene) }
        }
        // `install` often runs in App.init, before UIApplication has a scene; retry on the next turn
        Task { @MainActor in self.attachIfPossible() }
    }

    private func observeActivation() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachIfPossible() }
        }
    }

    private func detach(ifOn scene: UIScene?) {
        guard let window, scene == nil || window.windowScene == nil || window.windowScene === scene else { return }
        window.isHidden = true
        self.window = nil
        controller.window = nil
        observeActivation()
        attachIfPossible()
    }

    /// Called by `Annotate.start()`: a hidden launcher means the window may not exist yet.
    func ensureAttached() {
        attachIfPossible(force: true)
    }

    private func attachIfPossible(force: Bool = false) {
        guard window == nil else { return }
        let startsActive = ProcessInfo.processInfo.environment[controller.options.launchEnvironmentKey] == "1"
        guard force || startsActive || controller.isActive || controller.options.showsLauncher else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) else { return }

        let window = OverlayWindow(windowScene: scene, controller: controller)
        window.isHidden = false
        self.window = window
        controller.window = window
        // `Annotate.start()` may have run before the window existed; finish activating now
        if controller.isActive {
            window.activate()
        }

        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        if startsActive {
            controller.startWhenSettled()
        }
    }
}

final class OverlayWindow: UIWindow {
    private let controller: AnnotateController
    private let host: OverlayHostingController
    private weak var previousKeyWindow: UIWindow?

    init(windowScene: UIWindowScene, controller: AnnotateController) {
        self.controller = controller
        self.host = OverlayHostingController(controller: controller)
        super.init(windowScene: windowScene)
        windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        backgroundColor = .clear
        rootViewController = host
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard controller.isActive || controller.launcherHitFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    func activate() {
        previousKeyWindow = windowScene?.windows.first { $0.isKeyWindow && $0 !== self }
        makeKey()
        host.becomeFirstResponder()
    }

    func deactivate() {
        host.resignFirstResponder()
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
    }
}

final class OverlayHostingController: UIHostingController<OverlayRoot> {
    private let controller: AnnotateController

    init(controller: AnnotateController) {
        self.controller = controller
        super.init(rootView: OverlayRoot(controller: controller))
        view.backgroundColor = .clear
        // No keyboard avoidance: it slid the whole overlay, frozen image and pins included, up by
        // ~140 pt under the comment keyboard, so taps landed on what was really lower on screen.
        // The card and toolbar move above the keyboard themselves (`keyboardTop`).
        safeAreaRegions = .container
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 1pt hidden view pinned to the keyboard layout guide: its position is where the keyboard's top
    /// really is, suggestion bar included, which keyboard notifications don't always report.
    private let keyboardProbe = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboardProbe.isHidden = true
        keyboardProbe.isUserInteractionEnabled = false
        keyboardProbe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardProbe)
        NSLayoutConstraint.activate([
            keyboardProbe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardProbe.widthAnchor.constraint(equalToConstant: 1),
            keyboardProbe.heightAnchor.constraint(equalToConstant: 1),
            keyboardProbe.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        controller.updateLayout(bounds: view.bounds, safeInsets: view.safeAreaInsets)
        controller.updateKeyboardGuide(top: keyboardProbe.frame.maxY)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        controller.updateLayout(bounds: view.bounds, safeInsets: view.safeAreaInsets)
    }

    // MARK: Keyboard

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard controller.isActive else { return [] }
        let commands = [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(expandSelection)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(narrowSelection)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape)),
            UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(undo)),
            UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(redo)),
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(send))
        ]
        // Arrow keys and ⌘Z would otherwise go to a focused text field first
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    @objc private func expandSelection() { controller.adjustSelection(expand: true) }
    @objc private func narrowSelection() { controller.adjustSelection(expand: false) }
    @objc private func escape() { controller.escape() }
    @objc private func undo() { controller.undo() }
    @objc private func redo() { controller.redo() }
    @objc private func send() { controller.send(keepAnnotating: true) }

    // MARK: Status bar — defer to the app so the overlay window doesn't restyle it

    private var appTopController: UIViewController? {
        // Skip ourselves explicitly: before `view.window` is set the overlay isn't excluded,
        // and asking our own preferredStatusBarStyle would recurse forever
        var top = ElementScanner.appWindows(excluding: view.window)
            .first { $0.rootViewController !== self }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        appTopController?.preferredStatusBarStyle ?? .default
    }

    override var prefersStatusBarHidden: Bool {
        appTopController?.prefersStatusBarHidden ?? false
    }
}
#endif
