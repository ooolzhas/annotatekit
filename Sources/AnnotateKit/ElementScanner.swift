// Finds every element under a tap in the app's own windows, the way a DOM inspector would.
// Occlusion: only the touch-receiving window is scanned, and within it only the hit view's
// ancestor chain (as containers), its subtree, and the accessibility children of both. That keeps
// views hidden behind a sheet out of the results. SwiftUI content arrives as accessibility nodes
// (see AccessibilityBootstrap); UIKit content arrives as UIViews. So does React Native's: its host
// views report the JSX component they render (`Text`, not `RCTParagraphComponentView`), and its
// root and navigation wrappers count as plumbing (see ReactNativeViews).
// `outline` lists every visible labeled element on the current screen (top presented controller,
// plus its presenter when a sheet doesn't cover it) for the session's grep hints; `outlineScan`
// also counts accessibility nodes, which tells the controller when SwiftUI's tree is built.
// All frames are screen points.

#if DEBUG && canImport(UIKit)
#if canImport(AnnotateCore) // the CocoaPods build compiles AnnotateCore into this module
import AnnotateCore
#endif
import UIKit

@MainActor
enum ElementScanner {
    static func candidates(at point: CGPoint, excluding overlay: UIWindow?) -> [ElementCandidate] {
        for window in appWindows(excluding: overlay) {
            let local = window.convert(point, from: window.screen.coordinateSpace)
            guard let hit = window.hitTest(local, with: nil) else { continue }
            let walker = Walker(point: point, screenSpace: window.screen.coordinateSpace)
            walker.walk(from: hit)
            return walker.results
        }
        return []
    }

    /// Labeled elements on the visible screen. Unfiltered; `ScreenOutline.normalized` cleans it up.
    static func outline(excluding overlay: UIWindow?, limit: Int = 600) -> [ScreenElement] {
        outlineScan(excluding: overlay, limit: limit).elements
    }

    /// `outline`, plus how many non-view accessibility nodes the walk passed. SwiftUI content
    /// exists only as such nodes, so zero means its tree hasn't been built (yet).
    static func outlineScan(excluding overlay: UIWindow?, limit: Int = 600) -> (elements: [ScreenElement], accessibilityNodes: Int) {
        guard let window = appWindows(excluding: overlay).first(where: { $0.windowLevel == .normal })
            ?? appWindows(excluding: overlay).first else { return ([], 0) }
        let space = window.screen.coordinateSpace

        var roots: [UIView] = []
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        if let topView = top?.view {
            roots.append(topView)
            // A partial sheet leaves its presenter visible around it
            let covered = topView.convert(topView.bounds, to: space)
            if !covered.encloses(window.bounds, tolerance: 1), let presenter = top?.presentingViewController?.view {
                roots.append(presenter)
            }
        } else {
            roots.append(window)
        }

        let collector = OutlineCollector(screenSpace: space, limit: limit)
        for root in roots {
            collector.visit(root, depth: 0)
        }
        return (collector.results, collector.accessibilityNodes)
    }

    /// Visible app windows, topmost first.
    static func appWindows(excluding overlay: UIWindow?) -> [UIWindow] {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = overlay?.windowScene
            ?? scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
        let windows = (scene?.windows ?? []).filter { $0 !== overlay && !$0.isHidden && $0.alpha > 0.01 }
        return windows.enumerated()
            .sorted { lhs, rhs in
                lhs.element.windowLevel == rhs.element.windowLevel
                    ? lhs.offset > rhs.offset
                    : lhs.element.windowLevel.rawValue > rhs.element.windowLevel.rawValue
            }
            .map(\.element)
    }
}

@MainActor
private final class OutlineCollector {
    let screenSpace: UICoordinateSpace
    let limit: Int
    private(set) var results: [ScreenElement] = []
    private(set) var accessibilityNodes = 0
    private var visited = Set<ObjectIdentifier>()
    private var budget: Int

    init(screenSpace: UICoordinateSpace, limit: Int) {
        self.screenSpace = screenSpace
        self.limit = limit
        // Visited-node cap: SwiftUI trees have many unlabeled nodes per labeled one
        self.budget = 8_000
    }

    func visit(_ view: UIView, depth: Int) {
        guard depth < 150, budget > 0, results.count < limit, !view.isHidden, view.alpha > 0.01,
              visited.insert(ObjectIdentifier(view)).inserted else { return }
        budget -= 1
        record(view, frame: view.convert(view.bounds, to: screenSpace), view: view)
        visitAccessibilityChildren(of: view, depth: depth + 1)
        for subview in view.subviews {
            visit(subview, depth: depth + 1)
        }
    }

    private func visitAccessibilityChildren(of object: NSObject, depth: Int) {
        guard depth < 150 else { return }
        for child in Walker.accessibilityChildren(of: object) {
            guard budget > 0, results.count < limit else { return }
            if let view = child as? UIView {
                visit(view, depth: depth + 1)
                continue
            }
            guard visited.insert(ObjectIdentifier(child)).inserted else { continue }
            budget -= 1
            accessibilityNodes += 1
            record(child, frame: child.accessibilityFrame, view: nil)
            visitAccessibilityChildren(of: child, depth: depth + 1)
        }
    }

    private func record(_ object: NSObject, frame: CGRect, view: UIView?) {
        guard frame.area > 0 else { return }
        var label = object.accessibilityLabel ?? ""
        if label.isEmpty, let text = (view as? UILabel)?.text { label = text }
        let role = Walker.role(traits: object.accessibilityTraits, view: view)
        // A toggle's value is its state ("1"), not text (see ElementInfo.textValue)
        if label.isEmpty, role != "toggle", let value = object.accessibilityValue, view == nil || object.isAccessibilityElement { label = value }
        guard !label.isEmpty else { return }
        results.append(ScreenElement(role: role, label: label, frame: AnnotationRect(frame)))
    }
}

@MainActor
private final class Walker {
    let point: CGPoint
    let screenSpace: UICoordinateSpace
    private(set) var results: [ElementCandidate] = []
    private var visited = Set<ObjectIdentifier>()
    private let maxDepth = 150

    init(point: CGPoint, screenSpace: UICoordinateSpace) {
        self.point = point
        self.screenSpace = screenSpace
    }

    func walk(from hit: UIView) {
        visitSubtree(hit, depth: 0)
        var ancestor = hit.superview
        while let view = ancestor {
            if visited.insert(ObjectIdentifier(view)).inserted {
                let frame = view.convert(view.bounds, to: screenSpace)
                addIfMeaningful(view, frame: frame)
                visitAccessibilityChildren(of: view, depth: 0)
            }
            ancestor = view.superview
        }
    }

    private func visitSubtree(_ view: UIView, depth: Int) {
        guard depth < maxDepth, !view.isHidden, view.alpha > 0.01,
              visited.insert(ObjectIdentifier(view)).inserted else { return }
        let frame = view.convert(view.bounds, to: screenSpace)
        let contains = frame.containsPoint(point)
        if contains {
            addIfMeaningful(view, frame: frame)
            visitAccessibilityChildren(of: view, depth: depth + 1)
        }
        // Unclipped views can host subviews outside their own bounds
        guard contains || !view.clipsToBounds else { return }
        for subview in view.subviews {
            visitSubtree(subview, depth: depth + 1)
        }
    }

    private func visitAccessibilityChildren(of object: NSObject, depth: Int) {
        guard depth < maxDepth else { return }
        for child in Self.accessibilityChildren(of: object) {
            if let view = child as? UIView {
                visitSubtree(view, depth: depth + 1)
                continue
            }
            guard visited.insert(ObjectIdentifier(child)).inserted else { continue }
            let frame = child.accessibilityFrame
            let contains = frame.containsPoint(point)
            if contains, child.isAccessibilityElement || child.accessibilityLabel?.isEmpty == false {
                results.append(ElementCandidate(frame: frame, info: Self.info(for: child, view: nil)))
            }
            // Containers sometimes report an empty frame; descend anyway
            if contains || frame.area == 0 {
                visitAccessibilityChildren(of: child, depth: depth + 1)
            }
        }
    }

    private func addIfMeaningful(_ view: UIView, frame: CGRect) {
        guard frame.containsPoint(point), Self.isMeaningful(view) else { return }
        results.append(ElementCandidate(frame: frame, info: Self.info(for: view, view: view)))
    }

    // MARK: - Description

    static func accessibilityChildren(of object: NSObject) -> [NSObject] {
        if let elements = object.accessibilityElements {
            return elements.compactMap { $0 as? NSObject }
        }
        let count = object.accessibilityElementCount()
        guard count != NSNotFound, count > 0, count < 10_000 else { return [] }
        return (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
    }

    /// Skips UIKit/SwiftUI/React Native plumbing views; keeps controls, text, images, cells, scroll
    /// views, view-controller roots and app-defined UIView subclasses.
    static func isMeaningful(_ view: UIView) -> Bool {
        if view.isAccessibilityElement || view is UIWindow { return true }
        switch view {
        case is UIControl, is UILabel, is UIImageView, is UITextView, is UIScrollView,
             is UITableViewCell, is UICollectionViewCell:
            return true
        default:
            break
        }
        let name = className(of: view)
        // Checked before the controller: RN's root view and each react-native-screens screen are
        // view-controller roots too
        if ReactNativeViews.isPlumbing(className: name) { return false }
        if let controller = view.next as? UIViewController {
            let controllerName = className(of: controller)
            return !controllerName.contains("Hosting") && !ReactNativeViews.isPlumbing(className: controllerName)
        }
        let plumbing = ["_", "UI", "SwiftUI", "CA", "NS"]
        return !plumbing.contains { name.hasPrefix($0) } && !name.contains("Hosting")
    }

    static func info(for object: NSObject, view: UIView?) -> ElementInfo {
        let traits = object.accessibilityTraits
        var typeName: String?
        if let view {
            if let controller = view.next as? UIViewController, !(view is UIWindow) {
                typeName = className(of: controller)
            } else {
                typeName = className(of: view)
            }
            // React Native host views go by their JSX name; a leaf component's UIKit backing view
            // (the UISwitch inside a Switch) by its parent's
            if let name = typeName, let component = ReactNativeViews.componentName(forClassName: name)
                ?? view.superview.flatMap({ ReactNativeViews.componentName(forChildOf: className(of: $0)) }) {
                typeName = component
            }
        }
        var label = object.accessibilityLabel
        if label?.isEmpty ?? true, let text = (view as? UILabel)?.text {
            label = text
        }
        return ElementInfo(
            role: role(traits: traits, view: view),
            typeName: typeName,
            label: label,
            value: object.accessibilityValue,
            identifier: identifier(of: object),
            traits: traitNames(traits)
        )
    }

    static func role(traits: UIAccessibilityTraits, view: UIView?) -> String {
        switch view {
        case is UIWindow: return "screen"
        case is UISwitch: return "toggle"
        case is UISlider: return "slider"
        case is UITextField, is UISearchBar: return "textField"
        case is UITextView: return "textView"
        case is UIButton: return "button"
        case is UILabel: return "text"
        case is UIImageView: return "image"
        case is UITableViewCell, is UICollectionViewCell: return "cell"
        case is UIScrollView: return "scrollView"
        default: break
        }
        let ordered: [(UIAccessibilityTraits, String)] = [
            (.toggleButton, "toggle"),
            (.button, "button"),
            (.link, "link"),
            (.searchField, "textField"),
            (.adjustable, "slider"),
            (.header, "header"),
            (.image, "image"),
            (.staticText, "text"),
            (.tabBar, "tabBar"),
            (.keyboardKey, "key")
        ]
        if let match = ordered.first(where: { traits.contains($0.0) }) {
            return match.1
        }
        return view == nil ? "element" : "view"
    }

    static func traitNames(_ traits: UIAccessibilityTraits) -> [String] {
        let names: [(UIAccessibilityTraits, String)] = [
            (.button, "button"), (.toggleButton, "toggleButton"), (.link, "link"), (.header, "header"),
            (.searchField, "searchField"), (.image, "image"), (.selected, "selected"),
            (.staticText, "staticText"), (.adjustable, "adjustable"), (.notEnabled, "notEnabled"),
            (.tabBar, "tabBar"), (.summaryElement, "summaryElement"), (.updatesFrequently, "updatesFrequently")
        ]
        return names.filter { traits.contains($0.0) }.map(\.1)
    }

    static func identifier(of object: NSObject) -> String? {
        if let identified = object as? UIAccessibilityIdentification,
           let id = identified.accessibilityIdentifier, !id.isEmpty {
            return id
        }
        let selector = NSSelectorFromString("accessibilityIdentifier")
        guard object.responds(to: selector),
              let id = object.perform(selector)?.takeUnretainedValue() as? String, !id.isEmpty else { return nil }
        return id
    }

    /// Class name without module prefix or generic arguments.
    static func className(of object: AnyObject) -> String {
        let full = String(describing: type(of: object))
        let base = full.split(separator: "<").first.map(String.init) ?? full
        return base.split(separator: ".").last.map(String.init) ?? base
    }
}
#endif
