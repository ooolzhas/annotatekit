// Renders a session as the message the agent receives (prompt.md, and what gets delivered on Send).
// Leads with how to read coordinates, then one block per screen with its images, then one item
// per pin: what it's on, where exactly (frame, anchor, percentages), the request, and grep hints.
// Full frames, the visible-text outline and sketch vectors stay in session.json.

import Foundation

public enum PromptRenderer {
    /// - Parameters:
    ///   - sessionPath: absolute session directory, so image paths can be opened directly.
    ///   - completion: appended as the last paragraph, e.g. how to report back when done.
    public static func render(_ session: AnnotationSession, sessionPath: String?, completion: String? = nil) -> String {
        let base = sessionPath.map { $0.hasSuffix("/") ? $0 : $0 + "/" } ?? ""
        var lines: [String] = []

        let pins = session.annotations.count
        let screens = session.screens.filter { !session.annotations(on: $0).isEmpty }
        lines.append(
            "UI annotations from the running app: \(pins) \(plural(pins, "pin")) on \(screens.count) \(plural(screens.count, "screen")). "
                + "Please make these changes in the code."
        )
        lines.append("")
        lines.append("Session: \(sessionPath ?? session.id)")
        lines.append("Device: \(deviceLine(session))")
        lines.append(
            "Coordinates are iOS points, origin top-left. Screen images are 1x, so pixel = point. "
                + "Open the annotated image first: each pin is a numbered blue marker there. Crops show detail."
        )

        for screen in screens {
            lines.append("")
            var images: [String] = []
            if let annotated = screen.annotatedImage { images.append("annotated \(base)\(annotated)") }
            if let image = screen.image { images.append("clean \(base)\(image)") }
            if let hiRes = screen.hiResImage { images.append("hi-res \(base)\(hiRes)") }
            let size = "\(Int(screen.size.width))×\(Int(screen.size.height)) pt"
            lines.append("Screen \(screen.index) (\(size))" + (images.isEmpty ? "" : " — " + images.joined(separator: " · ")))
            for annotation in session.annotations(on: screen) {
                lines.append("")
                lines.append(contentsOf: item(annotation, screenSize: screen.size, base: base))
            }
        }

        lines.append("")
        lines.append("Full detail (all frames, visible text per screen, sketch vectors): \(base)session.json")
        if let completion, !completion.isEmpty {
            lines.append("")
            lines.append(completion)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func item(_ annotation: Annotation, screenSize: AnnotationSize, base: String) -> [String] {
        var lines: [String] = []
        let indent = "   "
        let f = annotation.frame

        let subject: String
        switch annotation.kind {
        case .element: subject = annotation.element?.displayName() ?? "Element"
        case .point: subject = "Spot"
        case .region: subject = "Region"
        case .sketch: subject = "Sketch" + (annotation.element.map { " over \($0.displayName())" } ?? "")
        }
        let box = "(\(num(f.x)), \(num(f.y)), \(num(f.width))×\(num(f.height)))"
        let anchor = annotation.anchor
        let across = percent(anchor.x, of: screenSize.width), down = percent(anchor.y, of: screenSize.height)
        let verb = annotation.kind == .region || annotation.kind == .sketch ? "center" : "tapped"
        lines.append("\(annotation.index). \(subject) at \(box) — \(verb) (\(num(anchor.x)), \(num(anchor.y))), \(across) across, \(down) down")

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
            let what = annotation.kind == .sketch ? "Drawn on the screen" : "Sketch of the desired layout drawn"
            lines.append("\(indent)\(what) in red (\(tools)); see the crop")
        }
        if !annotation.nearbyText.isEmpty {
            lines.append("\(indent)Nearby text: " + annotation.nearbyText.map { "\"\($0)\"" }.joined(separator: ", "))
        }
        if let source = annotation.source {
            lines.append("\(indent)Source: \(sourceDescription(source))")
        }
        if let crop = annotation.crop {
            lines.append("\(indent)Crop: \(base)\(crop)")
        }
        return lines
    }

    static func deviceLine(_ session: AnnotationSession) -> String {
        let device = session.device
        let size = "\(Int(device.screen.width))×\(Int(device.screen.height)) pt @\(num(device.scale))x"
        var parts = [device.model, "\(device.systemName) \(device.systemVersion)", size, device.colorScheme]
        parts.append("Dynamic Type \(device.contentSize)")
        if device.orientation != "portrait" { parts.append(device.orientation) }
        return parts.joined(separator: " · ")
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

    /// Whole numbers without ".0", one decimal otherwise.
    static func num(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    static func percent(_ value: Double, of total: Double) -> String {
        guard total > 0 else { return "?" }
        return "\(Int((value / total * 100).rounded()))%"
    }

    static func plural(_ count: Int, _ word: String) -> String {
        count == 1 ? word : word + "s"
    }
}
