// `.annotatable()` — opt-in source mapping. Each tagged view reports its screen frame and its
// `#filePath`/`#line` to an in-process registry; a pin on (or inside) that view then carries the
// file and line, so the agent edits the right place instead of grepping for on-screen text.
// Outside DEBUG the modifier returns `self` and costs nothing.
// Public: View.annotatable(_:file:line:)

#if canImport(SwiftUI)
import SwiftUI
#endif
#if DEBUG && canImport(UIKit)
import AnnotateCore
import UIKit
#endif

#if canImport(SwiftUI)
extension View {
    /// Tags this view for annotation source mapping.
    /// - Parameter name: shown on pins and in the prompt; defaults to the file name.
    public func annotatable(_ name: String? = nil, file: String = #filePath, line: Int = #line) -> some View {
        #if DEBUG && canImport(UIKit)
        modifier(AnnotatableModifier(name: name, file: file, line: line))
        #else
        self
        #endif
    }
}
#endif

#if DEBUG && canImport(UIKit)
/// Live `.annotatable()` registrations. Plain class, not observable: the overlay reads it on tap.
@MainActor
final class AnnotatableRegistry {
    static let shared = AnnotatableRegistry()

    private var views: [UUID: RegisteredView] = [:]

    func update(_ token: UUID, view: RegisteredView) {
        views[token] = view
    }

    func remove(_ token: UUID) {
        views[token] = nil
    }

    /// Registrations that are at least partly on screen.
    func visible(in bounds: CGRect) -> [RegisteredView] {
        views.values.filter { $0.frame.clipped(to: bounds).area > 0 }
    }
}

private struct AnnotatableModifier: ViewModifier {
    let name: String?
    let file: String
    let line: Int
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { register(proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in register(frame) }
                    .onDisappear { AnnotatableRegistry.shared.remove(token) }
            }
        }
    }

    private func register(_ frame: CGRect) {
        AnnotatableRegistry.shared.update(token, view: RegisteredView(name: name, frame: frame, file: file, line: line))
    }
}
#endif
