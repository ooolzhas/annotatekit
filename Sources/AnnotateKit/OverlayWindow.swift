// The overlay lives in its own UIWindow above the app, so it works for SwiftUI and UIKit apps alike
// and never touches the app's view hierarchy.
// Idle: the window only accepts touches on the launcher; everything else falls through to the app.
// Active: it takes every touch and becomes key so Return / Esc / ↑↓ / ⌘Z arrive as key commands.
// OverlayInstaller attaches the window once a scene is active (`install` may run before that).

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI
import UIKit

@MainActor
final class OverlayInstaller {
    static let shared = OverlayInstaller()

    let controller = AnnotateController()
    private var window: OverlayWindow?
    private var observer: NSObjectProtocol?
    private var isInstalled = false

    func install(options: AnnotateOptions, callerFile: String) {
        guard !isInstalled else { return }
        isInstalled = true
        controller.configure(options: options, callerFile: callerFile)
        if options.enablesAccessibilityTree {
            AccessibilityBootstrap.enable()
        }
        observer = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachIfPossible() }
        }
        // `install` often runs in App.init, before UIApplication has a scene; retry on the next turn
        Task { @MainActor in self.attachIfPossible() }
    }

    private func attachIfPossible() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) else { return }

        let window = OverlayWindow(windowScene: scene, controller: controller)
        window.isHidden = false
        self.window = window
        controller.window = window

        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        if ProcessInfo.processInfo.environment[controller.options.launchEnvironmentKey] == "1" {
            controller.start()
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
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        controller.updateLayout(bounds: view.bounds, safeInsets: view.safeAreaInsets)
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
    @objc private func send() { controller.send(keepAnnotating: false) }

    // MARK: Status bar — defer to the app so the overlay window doesn't restyle it

    private var appTopController: UIViewController? {
        var top = ElementScanner.appWindows(excluding: view.window).first?.rootViewController
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
