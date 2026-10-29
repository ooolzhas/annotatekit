// Pixels for the session bundle. `Snapshotter` (main actor) captures the app's windows, overlay
// excluded, plus the tiny gray samples a launch-time start waits on. `BundleRenderer` is
// nonisolated and runs off the main thread on Send: the 1x rescale (pixel = point, so session
// coordinates index straight into it), per-pin crops (frame plus any strokes reaching outside it),
// the annotated screen with numbered markers, and PNG encoding. Every renderer uses the standard
// 8-bit sRGB range — the default on wide-color screens is 16-bit extended range, twice the memory
// and much slower to encode, for no visible gain in UI screenshots.
// Also the shared sketch geometry (CGPath) and the design tokens (`AnnotateStyle`): the live
// overlay's white-on-dim look from the Figma redesign, and the blue/red the bundle PNGs keep.
// Stroke geometry and width are shared, so what the user drew is exactly what the agent sees.

#if DEBUG && canImport(UIKit)
import AnnotateCore
import SwiftUI
import UIKit

enum AnnotateStyle {
    // Computed rather than stored: no global-state isolation questions for the Canvas renderer.
    // The live overlay is white-on-dim (Figma PVX9n74hzo5BWauvymG141, group 9257:13754): the
    // screen is dimmed, so white markers read on any app. The bundle PNGs are not dimmed, so they
    // keep blue boxes and red strokes for contrast on any app.
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

    /// Live overlay markers (strokes, element boxes, spots) and badge fill: white on the dimmed screen. Figma 9257:13562 stroke=white, 9257:13564 border-white
    static var marker: Color { .white }
    /// Badge number. Figma 9257:13567 text-black
    static var badgeText: Color { .black }
    /// Fill of the primary actions (↑, Send). Accents/Blue #0088FF. Figma 9257:13480, 9257:13560
    static var action: Color { Color(uiColor: .systemBlue) }
    /// Dim over the frozen screen. Figma 9257:13385 bg-[rgba(0,0,0,0.5)]
    static let dimOpacity: Double = 0.5
    /// Corner radius the glow follows. Figma 9257:13385 rounded-[62px]; 2pt tighter on the owner's
    /// request so the glow sits snug in the screen's corners.
    static let screenCornerRadius: CGFloat = 60
    /// Glow spread: inset shadow 0 0 62px. Figma 9257:13385
    static let glowBlur: CGFloat = 62
    /// Element box: border-2, rounded-[8px]. Figma 9257:13564
    static let elementBoxLineWidth: CGFloat = 2
    static let elementBoxRadius: CGFloat = 8
    /// How far the box sits outside the element; Figma's hand-drawn boxes sit 1–7pt out (9257:13564/13565), so 2 is an estimate.
    static let elementBoxOutset: CGFloat = 2
    /// Number badge: 24pt circle. Figma 9257:13566 size-[24px]
    static let badgeSize: CGFloat = 24

    /// Per-axis offset from a spot's center to its badge's center (badge sits diagonally).
    /// No Figma row for spots; derived so the badge touches the ring without overlapping it:
    /// (ring radius 9 + badge radius 12, half of `badgeSize`) / √2 ≈ 14.85, rounded up to 15.
    /// Shared by the live overlay and the bundle PNG markers.
    static let spotBadgeOffset: CGFloat = 15
    /// Half of `badgeSize` (Figma 9257:13566); the PNG markers use it too, so both match.
    static let pinRadius: CGFloat = 12
    /// Uniform 4pt pen, live and in the PNGs (user requirement; Figma SVG stroke-width 4, 9257:13562).
    static let sketchLineWidth: CGFloat = 4
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
    /// The app's windows composited bottom-up, without the overlay, at `scale` (default: the
    /// screen's). The context must not be opaque: `drawHierarchy` paints a transparent window as
    /// solid black into an opaque one, and almost every app has a clear window above its content
    /// (UIKit's `UITextEffectsWindow` once any text input has been used, toast windows), which
    /// blacked out the whole capture.
    static func captureApp(excluding overlay: UIWindow?, scale: CGFloat? = nil) -> UIImage? {
        let windows = Array(ElementScanner.appWindows(excluding: overlay).reversed())
        guard let screen = overlay?.windowScene?.screen ?? windows.first?.screen else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: screen.bounds, format: BundleRenderer.format(scale: scale ?? screen.scale))
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(screen.bounds)
            for window in windows {
                let frame = window.convert(window.bounds, to: screen.coordinateSpace)
                window.drawHierarchy(in: frame, afterScreenUpdates: false)
            }
        }
    }

    /// The app as roughly `width` gray pixels across, for "has the screen changed" checks.
    static func grayThumbnail(excluding overlay: UIWindow?, width: Int = 40) -> [UInt8]? {
        let pointWidth = overlay?.windowScene?.screen.bounds.width ?? 0
        guard pointWidth > 0,
              let image = captureApp(excluding: overlay, scale: CGFloat(width) / pointWidth) else { return nil }
        return grayThumbnail(of: image, width: width)
    }

    /// `image` drawn `width` gray pixels across (height to aspect), for "is this the same screen" checks.
    static func grayThumbnail(of image: UIImage, width: Int = 40) -> [UInt8]? {
        guard let cgImage = image.cgImage, cgImage.width > 0 else { return nil }
        let pixelWidth = width
        let pixelHeight = max(1, Int((Double(cgImage.height) * Double(width) / Double(cgImage.width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                bytesPerRow: pixelWidth, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        return drawn ? pixels : nil
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
    /// Covers the pin's frame and every stroke on it: drawings can reach outside the frame.
    static func crop(_ annotation: Annotation, from image: UIImage, padding: CGFloat) -> UIImage? {
        var subject = annotation.frame.cgRect
        if let strokes = strokeBounds(annotation.sketchInScreenPoints) {
            subject = subject.union(strokes)
        }
        let area = subject.padded(by: padding).clipped(to: CGRect(origin: .zero, size: image.size))
        guard area.width >= 1, area.height >= 1 else { return nil }
        return UIGraphicsImageRenderer(size: area.size, format: format(scale: image.scale, opaque: true)).image { context in
            image.draw(at: CGPoint(x: -area.minX, y: -area.minY))
            drawMarkup(for: annotation, offset: area.origin, in: context.cgContext, numbered: false, bounds: CGRect(origin: .zero, size: area.size))
        }
    }

    /// Bounding box of every point in `strokes` (screen points); nil when there are none, so a pin
    /// without a sketch crops exactly as before.
    private static func strokeBounds(_ strokes: [Stroke]) -> CGRect? {
        let points = strokes.flatMap(\.points)
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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
