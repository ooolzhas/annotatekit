// Renders a session as a paste-ready prompt (prompt.md and the clipboard on Send).
// Kept terse: one numbered item per pin with the element, its source location, and the request.
// Frames, accessibility details and sketch vectors stay in session.json, which the prompt points to.

import Foundation

public enum PromptRenderer {
    /// - Parameter sessionPath: absolute session directory when known, so the agent can open the
    ///   PNGs directly; otherwise the prompt refers to paths relative to it.
    public static func render(_ session: AnnotationSession, sessionPath: String?) -> String {
        let base = sessionPath.map { $0.hasSuffix("/") ? $0 : $0 + "/" } ?? ""
        var lines: [String] = []

        let count = session.annotations.count
        lines.append("I annotated the running app (\(count) \(count == 1 ? "annotation" : "annotations")). Please make these UI changes.")
        lines.append("")
        lines.append("Session: \(sessionPath ?? session.id)")
        lines.append("Screen: \(screenLine(session))")
        if let annotated = session.annotatedScreenshot {
            lines.append("Screenshot with numbered pins: \(base)\(annotated)")
        }
        lines.append("")

        for annotation in session.annotations.sorted(by: { $0.index < $1.index }) {
            lines.append(contentsOf: item(annotation, base: base))
        }

        lines.append("")
        lines.append("Full details (frames, accessibility info, sketch vectors): \(base)session.json")
        return lines.joined(separator: "\n") + "\n"
    }

    static func screenLine(_ session: AnnotationSession) -> String {
        let device = session.device
        let size = "\(Int(device.screen.width))×\(Int(device.screen.height)) pt @\(formatScale(device.scale))x"
        var parts = [device.model, "\(device.systemName) \(device.systemVersion)", size, device.colorScheme]
        parts.append("Dynamic Type \(device.contentSize)")
        if device.orientation != "portrait" { parts.append(device.orientation) }
        return parts.joined(separator: " · ")
    }

    static func item(_ annotation: Annotation, base: String) -> [String] {
        var lines: [String] = []
        let indent = "   "

        var heading = "\(annotation.index). "
        switch annotation.kind {
        case .element:
            heading += annotation.element?.displayName() ?? "Element"
        case .region:
            let f = annotation.frame
            heading += "Region \(Int(f.width))×\(Int(f.height)) at (\(Int(f.x)), \(Int(f.y)))"
        }
        if let source = annotation.source {
            heading += " — " + sourceDescription(source)
        } else if annotation.kind == .element {
            heading += " — no source mapping; search for its text or label"
        }
        lines.append(heading)

        if let edit = annotation.textEdit {
            lines.append("\(indent)Change the copy from \"\(edit.from)\" to \"\(edit.to)\"")
        }
        let comment = annotation.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty {
            for line in comment.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("\(indent)\(line)")
            }
        }
        if let sketch = annotation.sketch, !sketch.strokes.isEmpty {
            let tools = sketch.strokes.map(\.tool.rawValue).joined(separator: ", ")
            lines.append("\(indent)Sketch of the desired layout (\(tools))")
        }
        if let crop = annotation.crop {
            lines.append("\(indent)Crop: \(base)\(crop)")
        }
        return lines
    }

    static func sourceDescription(_ source: SourceLocation) -> String {
        let location = "\(source.file):\(source.line)"
        let name = source.name.map { "`\($0)`" }
        switch source.match {
        case .exact:
            return name.map { "\($0) at \(location)" } ?? location
        case .enclosing:
            return "inside \(name ?? "the view") at \(location)"
        }
    }

    static func formatScale(_ scale: Double) -> String {
        scale == scale.rounded() ? String(Int(scale)) : String(scale)
    }
}
