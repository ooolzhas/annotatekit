// `.annotateAvoid()` — marks a view the idle launcher pill should keep clear of. AnnotateKit finds
// UIKit tab bars, toolbars, text inputs and controls on its own; a bar SwiftUI draws itself (a
// custom tab bar, a floating button, a composer in `safeAreaBar`) isn't a UIKit view, so the app
// tags it. Tagged views report their screen frame to a registry the launcher reads on each
// re-check; outside DEBUG the modifier returns `self`.
// Public: View.annotateAvoid()

#if canImport(SwiftUI)
import SwiftUI
#endif
#if DEBUG && canImport(UIKit)
import UIKit
#endif

#if canImport(SwiftUI)
extension View {
    /// Keeps the AnnotateKit launcher pill off this view while it idles: the pill lifts above it, or
    /// moves to a side, when the view sits where the pill docks.
    public func annotateAvoid() -> some View {
        #if DEBUG && canImport(UIKit)
        modifier(AnnotateAvoidModifier())
        #else
        self
        #endif
    }
}
#endif

#if DEBUG && canImport(UIKit)
/// Screen frames of the views tagged `.annotateAvoid()`, read on each launcher re-check.
@MainActor
final class AvoidRegistry {
    static let shared = AvoidRegistry()

    private var views: [UUID: CGRect] = [:]

    var frames: [CGRect] { Array(views.values) }

    func update(_ token: UUID, frame: CGRect) {
        views[token] = frame
    }

    func remove(_ token: UUID) {
        views[token] = nil
    }
}

private struct AnnotateAvoidModifier: ViewModifier {
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                AvoidRegistry.shared.update(token, frame: frame)
            }
            .onDisappear { AvoidRegistry.shared.remove(token) }
    }
}
#endif
