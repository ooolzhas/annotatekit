// Turns on the in-process accessibility tree, the same switch XCUITest and KIF flip.
// SwiftUI builds `accessibilityElements` for Text/Button/Image only when an accessibility client is
// active; without this, taps on un-annotated SwiftUI content only find the hosting view.
// Resolved with dlsym at runtime and compiled only in DEBUG, so no private symbol is linked.

#if DEBUG && canImport(UIKit)
import Darwin
import Foundation

@MainActor
enum AccessibilityBootstrap {
    private static var didEnable = false

    static func enable() {
        guard !didEnable else { return }
        didEnable = true

        var paths = ["/usr/lib/libAccessibility.dylib"]
        if let simulatorRoot = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] {
            paths.insert(simulatorRoot + "/usr/lib/libAccessibility.dylib", at: 0)
        }

        typealias SetEnabled = @convention(c) (Int32) -> Void
        for path in paths {
            guard let handle = dlopen(path, RTLD_NOW),
                  let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else { continue }
            unsafeBitCast(symbol, to: SetEnabled.self)(1)
            return
        }
    }
}
#endif
