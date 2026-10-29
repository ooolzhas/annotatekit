// Bottom chrome the idle launcher pill keeps clear of, read from the app's own UIKit views: visible
// tab bars, toolbars, text inputs and controls that sit outside any scroll view (content scrolls
// under the pill and would make it chase the scroll; chrome stays put), the extra bottom safe area a
// container reserves for its bars, and views marked `.annotateAvoid()` (SwiftUI-drawn bars aren't
// UIKit views, so the app tags them).
// Runs on the main thread every few seconds while the launcher idles, so it walks views only: the
// accessibility tree stays off until annotate mode. Frames come back in the overlay's coordinates.

#if DEBUG && canImport(UIKit)
import UIKit

@MainActor
enum LauncherObstacles {
    /// Extra bottom safe area below which a container's reserve isn't treated as a bar: anything
    /// smaller is a rounding difference, not chrome.
    private static let minimumReserve: CGFloat = 20

    /// Frames of the app's bottom chrome that reach into `band`, in `overlay`'s coordinates.
    static func scan(band: CGRect, overlay: UIWindow) -> [CGRect] {
        // `.global` frames are app-window points, and the overlay covers the same screen from the same origin
        var found = AvoidRegistry.shared.frames
        // Normal-level windows only: keyboards and the app's own alert or toast windows aren't its chrome
        for window in ElementScanner.appWindows(excluding: overlay) where window.windowLevel == .normal {
            let top = topPresented(in: window)
            // A presented controller covers what's under it; without one, walk the whole window
            let root: UIView = (top === window.rootViewController ? nil : top?.viewIfLoaded) ?? window
            collect(in: root, overlay: overlay, into: &found)
            if let reserve = reservedBottom(of: top, in: window, overlay: overlay) {
                found.append(reserve)
            }
        }
        return found.filter { $0.intersects(band) }
    }

    private static func collect(in view: UIView, overlay: UIWindow, into found: inout [CGRect]) {
        guard !view.isHidden, view.alpha > 0.01 else { return }
        if isChrome(view) {
            // A tab bar's buttons are part of it; one frame covers them
            found.append(view.convert(view.bounds, to: overlay))
            return
        }
        if view is UIScrollView { return }
        for subview in view.subviews {
            collect(in: subview, overlay: overlay, into: &found)
        }
    }

    private static func isChrome(_ view: UIView) -> Bool {
        switch view {
        case is UITabBar, is UIToolbar: true
        // Checked before the scroll-view cutoff: a text view is a scroll view, and a composer is one
        case let textView as UITextView: textView.isEditable
        // Text fields, buttons, switches, sliders
        case is UIControl: true
        default: false
        }
    }

    private static func topPresented(in window: UIWindow) -> UIViewController? {
        var top = window.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// The bottom safe area the visible content controller has beyond the window's: what a tab bar
    /// or toolbar controller (or an app's `additionalSafeAreaInsets` for its own bar) holds back.
    private static func reservedBottom(of controller: UIViewController?, in window: UIWindow, overlay: UIWindow) -> CGRect? {
        guard let controller, let view = visibleContent(of: controller).viewIfLoaded, view.window === window else {
            return nil
        }
        let reserve = view.safeAreaInsets.bottom - window.safeAreaInsets.bottom
        guard reserve >= minimumReserve else { return nil }
        let frame = view.convert(view.bounds, to: overlay)
        return CGRect(x: frame.minX, y: frame.maxY - view.safeAreaInsets.bottom, width: frame.width, height: reserve)
    }

    private static func visibleContent(of controller: UIViewController) -> UIViewController {
        if let tabs = controller as? UITabBarController, let selected = tabs.selectedViewController {
            return visibleContent(of: selected)
        }
        if let navigation = controller as? UINavigationController, let top = navigation.topViewController {
            return visibleContent(of: top)
        }
        return controller
    }
}
#endif
