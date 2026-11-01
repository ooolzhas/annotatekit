// The overlay's moving color, the edge glow's rings and the frost's blobs, as Core Animation layers.
// They used to be SwiftUI views redrawn by a TimelineView at 30 fps for as long as annotate mode was
// open: every frame re-rendered full-screen gradients on the main thread (~6.6% of a core on the
// Simulator with nothing happening). Here each motion is one repeating animation the render server
// plays, so the app does no per-frame work. The look and motion are the old views' own: the same
// stops, periods, phases and sizes. Reduce Motion adds no animations and holds the time-zero pose.

#if DEBUG && canImport(UIKit)
import UIKit

/// One stop of a fluid gradient: the palette color at `opacity`, at `location` (0...1).
struct FluidStop {
    let opacity: CGFloat
    let location: CGFloat
}

/// Conic gradient rings, each masked to a soft band along the screen's rounded edge
/// (`EdgeBandMask`) and turning about the screen's center.
final class FluidRingsView: UIView {
    struct Ring {
        let stops: [FluidStop]
        /// Seconds per turn.
        let period: Double
        let clockwise: Bool
        /// How far the band reaches in from the edge.
        let band: CGFloat
    }

    var color: UIColor = .clear {
        didSet { if color != oldValue { applyColors() } }
    }
    var animates = false {
        didSet { if animates != oldValue { applyMotion() } }
    }

    private let rings: [Ring]
    private let containers: [CALayer]
    private let gradients: [CAGradientLayer]
    private let masks: [CALayer]
    private static let turnKey = "turn"

    init(rings: [Ring]) {
        self.rings = rings
        containers = rings.map { _ in CALayer() }
        gradients = rings.map { _ in CAGradientLayer() }
        masks = rings.map { _ in CALayer() }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        for index in rings.indices {
            let gradient = gradients[index]
            gradient.type = .conic
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            containers[index].addSublayer(gradient)
            containers[index].mask = masks[index]
            layer.addSublayer(containers[index])
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FluidRingsView, _) in
            view.applyColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // A square as wide as the screen's diagonal, so the ring still covers every corner while it turns
        let side = hypot(bounds.width, bounds.height)
        for index in rings.indices {
            containers[index].frame = bounds
            masks[index].frame = bounds
            masks[index].contents = EdgeBandMask.image(size: bounds.size, width: rings[index].band)
            gradients[index].bounds = CGRect(x: 0, y: 0, width: side, height: side)
            gradients[index].position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyColors()
        applyMotion()
    }

    private func applyColors() {
        let resolved = color.resolvedColor(with: traitCollection)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (ring, gradient) in zip(rings, gradients) {
            gradient.colors = ring.stops.map { resolved.withAlphaComponent($0.opacity).cgColor }
            gradient.locations = ring.stops.map { NSNumber(value: Double($0.location)) }
        }
        CATransaction.commit()
    }

    private func applyMotion() {
        for (ring, gradient) in zip(rings, gradients) {
            guard animates, window != nil else {
                gradient.removeAnimation(forKey: Self.turnKey)
                continue
            }
            guard gradient.animation(forKey: Self.turnKey) == nil else { continue }
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = (ring.clockwise ? 1 : -1) * 2 * Double.pi
            turn.duration = ring.period
            turn.repeatCount = .infinity
            turn.timingFunction = CAMediaTimingFunction(name: .linear)
            // Kept across backgrounding, which otherwise strips finite-looking animations
            turn.isRemovedOnCompletion = false
            gradient.add(turn, forKey: Self.turnKey)
        }
    }
}

/// An even wash plus elliptical blobs that sway sideways on a sine, all fading to clear toward the top.
final class FluidFrostView: UIView {
    struct Blob {
        /// Rest center, as fractions of the frost's size.
        let x: CGFloat, y: CGFloat
        /// Size, as fractions of the frost's size.
        let width: CGFloat, height: CGFloat
        /// How far it sways either side, as a fraction of the frost's width.
        let sway: CGFloat
        /// Seconds per sway.
        let period: Double
        /// Where on its sine it starts, in radians.
        let phase: Double
        let opacity: CGFloat
    }

    var color: UIColor = .clear {
        didSet { if color != oldValue { applyColors() } }
    }
    var animates = false {
        didSet { if animates != oldValue { applyMotion() } }
    }

    private let blobs: [Blob]
    private let washOpacity: CGFloat
    private let wash = CAGradientLayer()
    private let blobLayers: [CAGradientLayer]
    private let fade = CAGradientLayer()
    /// The width the sway keyframes were made for; they are absolute positions.
    private var swayWidth: CGFloat = 0
    private static let swayKey = "sway"
    /// Keyframes per sway; linear between them reads as a smooth sine at these sizes.
    private static let swaySamples = 48

    init(blobs: [Blob], washOpacity: CGFloat, fadeEnd: CGFloat) {
        self.blobs = blobs
        self.washOpacity = washOpacity
        blobLayers = blobs.map { _ in CAGradientLayer() }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        wash.startPoint = CGPoint(x: 0.5, y: 0)
        wash.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(wash)
        for blob in blobLayers {
            blob.type = .radial
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            layer.addSublayer(blob)
        }
        fade.colors = [UIColor.clear.cgColor, UIColor.white.cgColor]
        fade.locations = [0, NSNumber(value: Double(fadeEnd))]
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        layer.mask = fade
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FluidFrostView, _) in
            view.applyColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = bounds
        fade.frame = bounds
        for (blob, blobLayer) in zip(blobs, blobLayers) {
            blobLayer.bounds = CGRect(x: 0, y: 0, width: size.width * blob.width, height: size.height * blob.height)
            blobLayer.position = CGPoint(x: Self.swayX(blob, at: 0, width: size.width), y: size.height * blob.y)
        }
        CATransaction.commit()
        if size.width != swayWidth {
            swayWidth = size.width
            blobLayers.forEach { $0.removeAnimation(forKey: Self.swayKey) }
            applyMotion()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyColors()
        applyMotion()
    }

    /// The blob's center x at `fraction` of its sway (0 is time zero, where Reduce Motion holds it).
    private static func swayX(_ blob: Blob, at fraction: Double, width: CGFloat) -> CGFloat {
        width * (blob.x + blob.sway * CGFloat(sin(fraction * 2 * .pi + blob.phase)))
    }

    private func applyColors() {
        let resolved = color.resolvedColor(with: traitCollection)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.colors = [resolved.withAlphaComponent(0).cgColor, resolved.withAlphaComponent(washOpacity).cgColor]
        for (blob, blobLayer) in zip(blobs, blobLayers) {
            blobLayer.colors = [resolved.withAlphaComponent(blob.opacity).cgColor, resolved.withAlphaComponent(0).cgColor]
        }
        CATransaction.commit()
    }

    private func applyMotion() {
        for (blob, blobLayer) in zip(blobs, blobLayers) {
            guard animates, window != nil, swayWidth > 0 else {
                blobLayer.removeAnimation(forKey: Self.swayKey)
                continue
            }
            guard blobLayer.animation(forKey: Self.swayKey) == nil else { continue }
            let sway = CAKeyframeAnimation(keyPath: "position.x")
            sway.values = (0...Self.swaySamples).map {
                Self.swayX(blob, at: Double($0) / Double(Self.swaySamples), width: swayWidth)
            }
            sway.duration = blob.period
            sway.repeatCount = .infinity
            sway.isRemovedOnCompletion = false
            blobLayer.add(sway, forKey: Self.swayKey)
        }
    }
}
#endif
