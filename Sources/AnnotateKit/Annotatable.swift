// `.annotatable()` — optional exact source mapping. While annotate mode is on, each tagged view
// reports its screen frame and its `#filePath`/`#line` to an in-process registry; a pin on (or
// inside) that view then carries the file and line. While it's off, tagged views do no geometry
// work at all (one observed Bool), and outside DEBUG the modifier returns `self`.
// Public: View.annotatable(_:file:line:)

#if canImport(SwiftUI)
import SwiftUI
#endif
#if DEBUG && canImport(UIKit)
import AnnotateCore
import Observation
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
/// Live `.annotatable()` registrations. Only `isCollecting` is observed (it switches frame
/// tracking on in every tagged view); the registrations themselves are read on tap.
@MainActor
@Observable
final class AnnotatableRegistry {
    static let shared = AnnotatableRegistry()

    private(set) var isCollecting = false
    @ObservationIgnored private var views: [UUID: RegisteredView] = [:]

    func setCollecting(_ collecting: Bool) {
        guard collecting != isCollecting else { return }
        isCollecting = collecting
        if !collecting { views.removeAll() }
    }

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
            if AnnotatableRegistry.shared.isCollecting {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { register(proxy.frame(in: .global)) }
                        .onChange(of: proxy.frame(in: .global)) { _, frame in register(frame) }
                        .onDisappear { AnnotatableRegistry.shared.remove(token) }
                }
            }
        }
    }

    private func register(_ frame: CGRect) {
        AnnotatableRegistry.shared.update(token, view: RegisteredView(name: name, frame: frame, file: file, line: line))
    }
}
#endif
