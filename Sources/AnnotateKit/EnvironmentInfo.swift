// App and device context recorded on every session: which build, which simulator, and the
// appearance settings that change layout (screen size, color scheme, Dynamic Type).

#if DEBUG && canImport(UIKit)
import AnnotateCore
import UIKit

extension AppInfo {
    static var current: AppInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppInfo(
            bundleID: Bundle.main.bundleIdentifier,
            name: (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String,
            version: info["CFBundleShortVersionString"] as? String,
            build: info["CFBundleVersion"] as? String
        )
    }
}

extension DeviceInfo {
    /// - Parameter window: an app window, so the app's own appearance overrides are reflected.
    @MainActor
    static func current(window: UIWindow?) -> DeviceInfo {
        let environment = ProcessInfo.processInfo.environment
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        let traits = window?.traitCollection ?? UITraitCollection.current
        let screen = window?.windowScene?.screen
        return DeviceInfo(
            model: environment["SIMULATOR_DEVICE_NAME"] ?? hardwareIdentifier(),
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            isSimulator: isSimulator,
            screen: AnnotationSize(screen?.bounds.size ?? window?.bounds.size ?? .zero),
            scale: Double(screen?.scale ?? traits.displayScale),
            colorScheme: traits.userInterfaceStyle == .dark ? "dark" : "light",
            contentSize: ContentSizeName.short(traits.preferredContentSizeCategory.rawValue),
            orientation: orientationName(window?.windowScene?.interfaceOrientation)
        )
    }

    private static func hardwareIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func orientationName(_ orientation: UIInterfaceOrientation?) -> String {
        switch orientation {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        default: "unknown"
        }
    }
}
#endif
