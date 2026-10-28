// Public entry point. Everything here exists in every configuration so call sites compile in
// Release, but only DEBUG builds on UIKit platforms install the overlay; elsewhere these are no-ops.
// Public: Annotate.install(_:file:), start(), stop(), toggle(), isActive; AnnotateOptions

import Foundation

public struct AnnotateOptions: Sendable {
    /// Floating button that enters annotate mode. Turn off if you trigger it yourself.
    public var showsLauncher: Bool
    /// Where session bundles go. Default: `<project root>/.annotate` in the Simulator (found from the
    /// `install` call site), the app's Documents folder on a device.
    public var outputDirectory: URL?
    /// Turns on the in-process accessibility tree so un-annotated SwiftUI text, buttons and images
    /// are selectable. This is what XCUITest does; switch it off if it interferes with your app.
    public var enablesAccessibilityTree: Bool
    /// Launch-environment key that starts the app in annotate mode when set to "1".
    public var launchEnvironmentKey: String
    /// Also put the prompt on the clipboard on Send. Off by default: the `annotate` CLI on the Mac
    /// delivers sessions to Claude Code; turn this on to paste into other tools.
    public var copiesPromptToClipboard: Bool
    /// Last paragraph of every prompt.
    public var completionNote: String?
    /// Seconds without any status.json before the overlay says nothing picked the session up.
    public var unclaimedAfter: Double

    public init(
        showsLauncher: Bool = true,
        outputDirectory: URL? = nil,
        enablesAccessibilityTree: Bool = true,
        launchEnvironmentKey: String = "ANNOTATE",
        copiesPromptToClipboard: Bool = false,
        completionNote: String? = "When you're done, finish with a one-line summary of what you changed.",
        unclaimedAfter: Double = 10
    ) {
        self.showsLauncher = showsLauncher
        self.outputDirectory = outputDirectory
        self.enablesAccessibilityTree = enablesAccessibilityTree
        self.launchEnvironmentKey = launchEnvironmentKey
        self.copiesPromptToClipboard = copiesPromptToClipboard
        self.completionNote = completionNote
        self.unclaimedAfter = unclaimedAfter
    }
}

@MainActor
public enum Annotate {
    /// Call once at launch, e.g. in your `App.init()`. Safe to call in Release (does nothing).
    /// - Parameter file: leave the default — the call site's path locates your project root.
    public static func install(_ options: AnnotateOptions = AnnotateOptions(), file: String = #filePath) {
        #if DEBUG && canImport(UIKit)
        OverlayInstaller.shared.install(options: options, callerFile: file)
        #endif
    }

    /// Enters annotate mode.
    public static func start() {
        #if DEBUG && canImport(UIKit)
        OverlayInstaller.shared.controller.start()
        #endif
    }

    /// Leaves annotate mode, keeping unsent annotations.
    public static func stop() {
        #if DEBUG && canImport(UIKit)
        OverlayInstaller.shared.controller.stop()
        #endif
    }

    public static func toggle() {
        isActive ? stop() : start()
    }

    public static var isActive: Bool {
        #if DEBUG && canImport(UIKit)
        OverlayInstaller.shared.controller.isActive
        #else
        false
        #endif
    }
}
