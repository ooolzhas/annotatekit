#if DEBUG && canImport(UIKit)
import UIKit

/// Finds the scroll view the user would scroll: the one under the middle of the screen in the
/// topmost app window, so a sheet's list wins over the page behind it.
@MainActor
enum ScrollProbe {
    static func mainScrollView(excluding overlay: UIWindow?) -> UIScrollView? {
        for window in ElementScanner.appWindows(excluding: overlay) {
            let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            guard let hit = window.hitTest(center, with: nil) else { continue }
            var view: UIView? = hit
            while let current = view {
                if let scrollView = current as? UIScrollView, scrolls(scrollView) { return scrollView }
                view = current.superview
            }
        }
        return nil
    }

    /// Text views scroll their text, not the page; skip them and anything with nowhere to go.
    private static func scrolls(_ scrollView: UIScrollView) -> Bool {
        guard !(scrollView is UITextView), scrollView.isScrollEnabled else { return false }
        let size = scrollView.contentSize, frame = scrollView.bounds.size
        return size.height > frame.height + 1 || size.width > frame.width + 1
    }
}
#endif
