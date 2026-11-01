// App and device context recorded on every session: which build (and the checkout it was built
// from), which device, and the appearance settings that change layout (screen size, color scheme,
// Dynamic Type).

#if DEBUG && canImport(UIKit)
#if canImport(AnnotateCore) // the CocoaPods build compiles AnnotateCore into this module
import AnnotateCore
#endif
import UIKit

extension AppInfo {
    /// - Parameter installFile: the `Annotate.install()` call site, so the Mac can route a device's
    ///   Send to the checkout this build came from.
    static func current(installFile: String) -> AppInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppInfo(
            bundleID: Bundle.main.bundleIdentifier,
            name: (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String,
            version: info["CFBundleShortVersionString"] as? String,
            build: info["CFBundleVersion"] as? String,
            installFile: installFile,
            framework: detectedFramework()
        )
    }

    /// "expo", "react-native", or nil for a native app. A device can't read the Mac's package.json,
    /// so this asks the ObjC runtime which framework classes are linked into the app. Expo is
    /// checked first because every Expo app is also a React Native app.
    static func detectedFramework(isLoaded: (String) -> Bool = { NSClassFromString($0) != nil }) -> String? {
        if expoClasses.contains(where: isLoaded) { return "expo" }
        if reactNativeClasses.contains(where: isLoaded) { return "react-native" }
        return nil
    }

    /// ExpoModulesCore / expo, SDK 52-54:
    /// - `EXAppContext`: `@objc(EXAppContext)` on `AppContext`,
    ///   https://github.com/expo/expo/blob/sdk-54/packages/expo-modules-core/ios/Core/AppContext.swift
    ///   (same in sdk-52 and sdk-53)
    /// - `EXAppDelegateWrapper`: the AppDelegate base class,
    ///   https://github.com/expo/expo/blob/sdk-52/packages/expo-modules-core/ios/AppDelegates/EXAppDelegateWrapper.h
    ///   and, from SDK 53, https://github.com/expo/expo/blob/sdk-54/packages/expo/ios/AppDelegates/EXAppDelegateWrapper.h
    private static let expoClasses = ["EXAppContext", "EXAppDelegateWrapper"]

    /// React Native, old architecture and new (bridgeless):
    /// - `RCTBridge`: React-Core, still compiled in bridgeless builds,
    ///   https://github.com/facebook/react-native/blob/main/packages/react-native/React/Base/RCTBridge.h
    /// - `RCTHost`: the bridgeless runtime host (0.74+),
    ///   https://github.com/facebook/react-native/blob/main/packages/react-native/ReactCommon/react/runtime/platform/ios/ReactCommon/RCTHost.h
    /// - `RCTRootViewFactory` (0.74+) and `RCTReactNativeFactory` (0.78+, the Swift AppDelegate template),
    ///   https://github.com/facebook/react-native/tree/main/packages/react-native/Libraries/AppDelegate
    private static let reactNativeClasses = ["RCTBridge", "RCTHost", "RCTRootViewFactory", "RCTReactNativeFactory"]
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
