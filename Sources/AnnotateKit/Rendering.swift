// Pixels for the session bundle: a capture of the app's windows (overlay excluded), markup for
// per-pin crops (element outlined or sketch burned in), and a full annotated screenshot with numbered
// pins. Also the shared sketch geometry (CGPath) and colors used by both the live overlay and
// the PNGs, so what the user drew is exactly what the agent sees.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI
import UIKit

enum AnnotateStyle {
    static let accentUI = UIColor(red: 0.16, green: 0.49, blue: 0.96, alpha: 1)
    static let sketchUI = UIColor(red: 0.94, green: 0.23, blue: 0.21, alpha: 1)
    static let accent = Color(uiColor: accentUI)
    static let sketch = Color(uiColor: sketchUI)
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
        let format = UIGraphicsImageRendererFormat()
        format.scale = screen.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: screen.bounds, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(screen.bounds)
            for window in windows {
                let frame = window.convert(window.bounds, to: screen.coordinateSpace)
                window.drawHierarchy(in: frame, afterScreenUpdates: false)
            }
        }
    }

    /// `annotation`'s outline or sketch drawn onto `image`; the frame must already be in image space.
    static func markup(_ annotation: Annotation, onto image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            drawMarkup(for: annotation, frame: annotation.frame.cgRect, in: context.cgContext, number: false)
        }
    }

    /// Full capture with every annotation's outline, sketch and numbered pin.
    static func annotatedScreenshot(_ image: UIImage, annotations: [Annotation]) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let bounds = CGRect(origin: .zero, size: image.size)
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            for annotation in annotations {
                drawMarkup(for: annotation, frame: annotation.frame.cgRect, in: context.cgContext, number: true, bounds: bounds)
            }
        }
    }

    private static func drawMarkup(for annotation: Annotation, frame: CGRect, in cg: CGContext, number: Bool, bounds: CGRect = .zero) {
        cg.saveGState()
        defer { cg.restoreGState() }

        cg.setStrokeColor(AnnotateStyle.accentUI.cgColor)
        cg.setLineWidth(2)
        if annotation.kind == .region {
            cg.setLineDash(phase: 0, lengths: [6, 4])
        }
        cg.stroke(frame.insetBy(dx: -1, dy: -1))
        cg.setLineDash(phase: 0, lengths: [])

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

        guard number else { return }
        let radius = AnnotateStyle.pinRadius
        let center = OverlayPlacement.pinCenter(for: frame, radius: radius, in: bounds)
        let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        cg.setFillColor(AnnotateStyle.accentUI.cgColor)
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
