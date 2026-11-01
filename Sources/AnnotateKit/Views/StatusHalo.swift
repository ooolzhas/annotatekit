// The status dot's breathing wave (Figma 9378:5495 "Pulsing Wave"), drawn by Core Animation. As a
// SwiftUI `phaseAnimator` it re-rendered the view graph every frame for as long as the launcher
// pill showed, so a DEBUG build with the pill up spent ~5% of a core doing nothing (AGENTS.md: idle
// cost). Layer animations run in the render server instead. A layer's blur can't be animated with
// public API, so the wave crossfades from a sharp circle to the same circle blurred once with Core
// Image while it swells; the solid dot drawn over its center hides the crossfade's midpoint.

#if DEBUG && canImport(UIKit)
import CoreImage
import SwiftUI
import UIKit

struct StatusHalo: UIViewRepresentable {
    let color: Color
    let size: CGFloat
    let opacity: Double
    let restScale: CGFloat
    let halfPeriod: Double
    let blur: CGFloat
    let animates: Bool

    func makeUIView(context: Context) -> HaloView {
        HaloView()
    }

    func updateUIView(_ view: HaloView, context: Context) {
        view.configure(
            HaloView.Style(color: UIColor(color), size: size, opacity: opacity, restScale: restScale,
                           halfPeriod: halfPeriod, blur: blur, animates: animates)
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HaloView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class HaloView: UIView {
    struct Style: Equatable {
        var color: UIColor
        var size: CGFloat
        var opacity: Double
        var restScale: CGFloat
        var halfPeriod: Double
        var blur: CGFloat
        var animates: Bool
    }

    private let wave = CALayer()
    private let sharp = CAShapeLayer()
    private let soft = CALayer()
    private var style: Style?
    private var foregroundObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        // The blurred circle spreads past the wave's bounds, as SwiftUI's blur did
        clipsToBounds = false
        wave.addSublayer(soft)
        wave.addSublayer(sharp)
        layer.addSublayer(wave)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) { (view: HaloView, _) in
            view.redraw()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ new: Style) {
        guard new != style else { return }
        style = new
        redraw()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wave.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Infinite layer animations are dropped when the app goes to the background. Observed only
        // while in a window: a view always leaves its window before it's freed, so no deinit work
        if window != nil, foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.startBreathing() }
            }
        } else if window == nil, let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
        startBreathing()
    }

    private func redraw() {
        guard let style else { return }
        let color = style.color.resolvedColor(with: traitCollection)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wave.bounds = CGRect(x: 0, y: 0, width: style.size, height: style.size)
        wave.opacity = Float(style.opacity)
        sharp.frame = wave.bounds
        sharp.path = UIBezierPath(ovalIn: wave.bounds).cgPath
        sharp.fillColor = color.cgColor
        let spread = ceil(style.blur * 3)
        soft.frame = wave.bounds.insetBy(dx: -spread, dy: -spread)
        soft.contentsScale = scale
        soft.contents = Self.blurredCircle(color: color, diameter: style.size, blur: style.blur, spread: spread, scale: scale)
        CATransaction.commit()
        startBreathing()
    }

    /// Rest frame (the dot's size, sharp) swelling to full size and blurred, and back, forever. Reduce
    /// Motion holds Figma's still frame: full size and sharp.
    private func startBreathing() {
        guard let style else { return }
        wave.removeAllAnimations()
        sharp.removeAllAnimations()
        soft.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard style.animates, window != nil else {
            wave.transform = CATransform3DIdentity
            sharp.opacity = 1
            soft.opacity = 0
            CATransaction.commit()
            return
        }
        wave.transform = CATransform3DMakeScale(style.restScale, style.restScale, 1)
        sharp.opacity = 1
        soft.opacity = 0
        CATransaction.commit()
        let begin = CACurrentMediaTime()
        wave.add(Self.breath("transform.scale", from: style.restScale, to: 1, halfPeriod: style.halfPeriod, begin: begin), forKey: "breath")
        sharp.add(Self.crossfade(from: 1, to: 0, halfPeriod: style.halfPeriod, begin: begin), forKey: "breath")
        soft.add(Self.crossfade(from: 0, to: 1, halfPeriod: style.halfPeriod, begin: begin), forKey: "breath")
    }

    /// Done within the first `crossfadeEnd` of the swell, while the wave is still mostly under the
    /// solid dot: a sharp circle fading out at a larger size read as a hard ring the blur never had.
    private static let crossfadeEnd: NSNumber = 0.3

    private static func crossfade(from: Float, to: Float, halfPeriod: Double, begin: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [from, to, to]
        animation.keyTimes = [0, crossfadeEnd, 1]
        animation.duration = halfPeriod
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.beginTime = begin
        animation.isRemovedOnCompletion = false
        return animation
    }

    private static func breath(_ keyPath: String, from: CGFloat, to: CGFloat, halfPeriod: Double, begin: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = halfPeriod
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.beginTime = begin
        // SwiftUI's easeInOut, which the phaseAnimator used
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        return animation
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// The wave's circle with SwiftUI's `.blur(radius:)` applied, drawn once per color and scale.
    private static func blurredCircle(color: UIColor, diameter: CGFloat, blur: CGFloat, spread: CGFloat, scale: CGFloat) -> CGImage? {
        let side = diameter + spread * 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let circle = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: spread, y: spread, width: diameter, height: diameter)).fill()
        }
        guard let input = circle.cgImage.map({ CIImage(cgImage: $0) }) else { return nil }
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: Double(blur * scale)).cropped(to: input.extent)
        return ciContext.createCGImage(blurred, from: input.extent)
    }
}
#endif
