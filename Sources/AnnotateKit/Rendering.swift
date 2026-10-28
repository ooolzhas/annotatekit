// Pixels for the session bundle. `Snapshotter` (main actor) captures the app's windows, overlay
// excluded. `BundleRenderer` is nonisolated and runs off the main thread on Send: the 1x rescale
// (pixel = point, so session coordinates index straight into it), per-pin crops, the annotated
// screen with numbered markers, and PNG encoding. Every renderer uses the standard 8-bit sRGB
// range — the default on wide-color screens is 16-bit extended range, twice the memory and much
// slower to encode, for no visible gain in UI screenshots.
// Also the shared sketch geometry (CGPath) and colors used by both the live overlay and the PNGs,
// so what the user drew is exactly what the agent sees.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI
import UIKit

enum AnnotateStyle {
    // Computed rather than stored: no global-state isolation questions for the Canvas renderer.
    // Three blues: `accent` for strokes and outlines, `accentFill` under white text (pins, chips,
    // Send — deep enough for 4.5:1 at 11 pt), `accentText` for blue text and glyphs on materials.
    static var accentUI: UIColor { UIColor(red: 0.16, green: 0.49, blue: 0.96, alpha: 1) }
    static var accentFillUI: UIColor { UIColor(red: 0.10, green: 0.40, blue: 0.86, alpha: 1) }
    static var sketchUI: UIColor { UIColor(red: 0.94, green: 0.23, blue: 0.21, alpha: 1) }
    static var sketchFillUI: UIColor { UIColor(red: 0.83, green: 0.18, blue: 0.16, alpha: 1) }
    static var accent: Color { Color(uiColor: accentUI) }
    static var accentFill: Color { Color(uiColor: accentFillUI) }
    static var accentText: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.47, green: 0.69, blue: 1.0, alpha: 1)
                : UIColor(red: 0.10, green: 0.40, blue: 0.86, alpha: 1)
        })
    }
    static var sketch: Color { Color(uiColor: sketchUI) }
    static var sketchFill: Color { Color(uiColor: sketchFillUI) }
    /// Gap between a spot's crosshair and its numbered badge.
    static let spotBadgeOffset: CGFloat = 14
    static let pinRadius: CGFloat = 11
    static let sketchLineWidth: CGFloat = 2.5
}

enum SketchPath {
    /// Path for one stroke; `offset` moves region-local points into the target space.
    static func path(for stroke: Stroke, offset: CGPoint = .zero) -> CGPath {
        let points = stroke.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        let path = CGMutablePath()
        guard let first = points.first, let last = points.last else { return path }
        switch stroke.tool {
        case .pen:
            path.move(to: first)
            guard points.count > 1 else {
                path.addLine(to: first)
                return path
            }
            // Quadratic segments through midpoints smooth out touch sampling
            for index in 1..<points.count {
                let previous = points[index - 1], current = points[index]
                let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: mid, control: previous)
            }
            path.addLine(to: last)
        case .rectangle:
            path.addRect(CGRect.spanning(first, last))
        case .ellipse:
            path.addEllipse(in: CGRect.spanning(first, last))
        case .arrow:
            path.move(to: first)
            path.addLine(to: last)
            let (a, b) = OverlayPlacement.arrowHead(from: first, to: last)
            path.move(to: a)
            path.addLine(to: last)
            path.addLine(to: b)
        }
        return path
    }
}

@MainActor
enum Snapshotter {
    /// The app's windows composited bottom-up at screen scale, without the overlay.
    static func captureApp(excluding overlay: UIWindow?) -> UIImage? {
        let windows = Array(ElementScanner.appWindows(excluding: overlay).reversed())
        guard let screen = overlay?.windowScene?.screen ?? windows.first?.screen else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: screen.bounds, format: BundleRenderer.format(scale: screen.scale, opaque: true))
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(screen.bounds)
            for window in windows {
                let frame = window.convert(window.bounds, to: screen.coordinateSpace)
                window.drawHierarchy(in: frame, afterScreenUpdates: false)
            }
        }
    }
}

/// Thread-safe rendering for the bundle (UIGraphicsImageRenderer and UIImage are safe off-main).
enum BundleRenderer {
    static func format(scale: CGFloat, opaque: Bool = false) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = opaque
        format.preferredRange = .standard
        return format
    }

    /// Same pixels at `scale` pixels per point; at 1 the image size in pixels equals points.
    static func rescaled(_ image: UIImage, to scale: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: image.size, format: format(scale: scale, opaque: true)).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Native-resolution crop around one pin with `padding` points of context, markup drawn in.
    static func crop(_ annotation: Annotation, from image: UIImage, padding: CGFloat) -> UIImage? {
        let area = annotation.frame.cgRect.padded(by: padding).clipped(to: CGRect(origin: .zero, size: image.size))
        guard area.width >= 1, area.height >= 1 else { return nil }
        return UIGraphicsImageRenderer(size: area.size, format: format(scale: image.scale, opaque: true)).image { context in
            image.draw(at: CGPoint(x: -area.minX, y: -area.minY))
            drawMarkup(for: annotation, offset: area.origin, in: context.cgContext, numbered: false, bounds: CGRect(origin: .zero, size: area.size))
        }
    }

    /// Screen image with every pin's outline (or spot marker), sketch and number.
    static func annotatedScreenshot(_ image: UIImage, annotations: [Annotation]) -> UIImage {
        let bounds = CGRect(origin: .zero, size: image.size)
        return UIGraphicsImageRenderer(size: image.size, format: format(scale: image.scale, opaque: true)).image { context in
            image.draw(at: .zero)
            for annotation in annotations {
                drawMarkup(for: annotation, offset: .zero, in: context.cgContext, numbered: true, bounds: bounds)
            }
        }
    }

    /// Draws one pin's markup; `offset` is subtracted from its screen coordinates (crop origin).
    private static func drawMarkup(for annotation: Annotation, offset: CGPoint, in cg: CGContext, numbered: Bool, bounds: CGRect) {
        cg.saveGState()
        defer { cg.restoreGState() }

        let frame = annotation.frame.cgRect.offsetBy(dx: -offset.x, dy: -offset.y)
        let anchor = CGPoint(x: annotation.anchor.x - offset.x, y: annotation.anchor.y - offset.y)
        cg.setStrokeColor(AnnotateStyle.accentUI.cgColor)
        cg.setLineWidth(2)

        switch annotation.kind {
        case .element:
            cg.stroke(frame.insetBy(dx: -1, dy: -1))
        case .region:
            cg.setLineDash(phase: 0, lengths: [6, 4])
            cg.stroke(frame.insetBy(dx: -1, dy: -1))
            cg.setLineDash(phase: 0, lengths: [])
        case .sketch:
            // The drawing speaks for itself; no box around it
            break
        case .point:
            // Crosshair ring: the exact spot matters more than any box
            let ring = CGRect(x: anchor.x - 9, y: anchor.y - 9, width: 18, height: 18)
            cg.strokeEllipse(in: ring)
            cg.setFillColor(AnnotateStyle.accentUI.cgColor)
            cg.fillEllipse(in: CGRect(x: anchor.x - 2, y: anchor.y - 2, width: 4, height: 4))
        }

        if let sketch = annotation.sketch {
            cg.setStrokeColor(AnnotateStyle.sketchUI.cgColor)
            cg.setLineWidth(AnnotateStyle.sketchLineWidth)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in sketch.strokes {
                cg.addPath(SketchPath.path(for: stroke, offset: frame.origin))
                cg.strokePath()
            }
        }

        guard numbered else { return }
        let radius = AnnotateStyle.pinRadius
        let offset = AnnotateStyle.spotBadgeOffset
        let pinFrame = annotation.kind == .point ? CGRect(x: anchor.x + offset, y: anchor.y - offset, width: 0, height: 0) : frame
        let center = OverlayPlacement.pinCenter(for: pinFrame, radius: radius, in: bounds)
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        cg.setFillColor(AnnotateStyle.accentFillUI.cgColor)
        cg.fillEllipse(in: circle)
        cg.setStrokeColor(UIColor.white.cgColor)
        cg.setLineWidth(1.5)
        cg.strokeEllipse(in: circle)

        let text = "\(annotation.index)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }
}
#endif
