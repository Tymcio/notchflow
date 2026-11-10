import AppKit
import QuartzCore
import SwiftUI

/// Looping indicators driven by Core Animation, so they run in the render server instead of
/// re-evaluating SwiftUI views every frame (a SwiftUI `repeatForever` can tick for hours in
/// the idle notch). Both fall back to a static look when Reduce Motion is on.
enum ReduceMotion {
    static var isEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Base view that re-applies its animation when Reduce Motion or the window changes.
class LayerAnimatedView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    override func layout() {
        super.layout()
        layoutLayers()
        updateAnimation()
    }

    @objc private func displayOptionsChanged() {
        updateAnimation()
    }

    /// Animations only run while on screen and allowed.
    var shouldAnimate: Bool {
        window != nil && !ReduceMotion.isEnabled
    }

    func layoutLayers() {}
    func updateAnimation() {}
}

// MARK: - Pulse halo

/// A soft circle that breathes between two diameters (finished-timer glow).
struct PulseHaloView: NSViewRepresentable {
    let color: Color
    let minDiameter: CGFloat
    let maxDiameter: CGFloat
    let duration: Double
    var isAnimating = true

    func makeNSView(context: Context) -> PulseHaloLayerView {
        PulseHaloLayerView()
    }

    func updateNSView(_ view: PulseHaloLayerView, context: Context) {
        view.configure(
            color: NSColor(color),
            minDiameter: minDiameter,
            maxDiameter: maxDiameter,
            duration: duration,
            isAnimating: isAnimating
        )
    }
}

final class PulseHaloLayerView: LayerAnimatedView {
    private let halo = CALayer()
    private var minDiameter: CGFloat = 16
    private var maxDiameter: CGFloat = 24
    private var duration: Double = 0.7
    private var isAnimating = true
    private static let animationKey = "pulse"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.addSublayer(halo)
    }

    func configure(color: NSColor, minDiameter: CGFloat, maxDiameter: CGFloat, duration: Double, isAnimating: Bool) {
        let changed = minDiameter != self.minDiameter || maxDiameter != self.maxDiameter
            || duration != self.duration || isAnimating != self.isAnimating
        halo.backgroundColor = color.cgColor
        self.minDiameter = minDiameter
        self.maxDiameter = maxDiameter
        self.duration = duration
        self.isAnimating = isAnimating
        if changed {
            halo.removeAnimation(forKey: Self.animationKey)
            needsLayout = true
        }
    }

    override func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.bounds = CGRect(x: 0, y: 0, width: maxDiameter, height: maxDiameter)
        halo.cornerRadius = maxDiameter / 2
        halo.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func updateAnimation() {
        let restingScale = (minDiameter + maxDiameter) / 2 / max(maxDiameter, 1)
        guard isAnimating, shouldAnimate else {
            halo.removeAnimation(forKey: Self.animationKey)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            halo.transform = CATransform3DMakeScale(restingScale, restingScale, 1)
            CATransaction.commit()
            return
        }
        guard halo.animation(forKey: Self.animationKey) == nil else { return }

        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = minDiameter / max(maxDiameter, 1)
        animation.toValue = 1
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        halo.add(animation, forKey: Self.animationKey)
    }
}

// MARK: - Typing dots

/// Three dots bouncing in sequence ("agent is working").
struct TypingDotsView: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> TypingDotsLayerView {
        TypingDotsLayerView()
    }

    func updateNSView(_ view: TypingDotsLayerView, context: Context) {
        view.dotColor = NSColor(color)
    }
}

final class TypingDotsLayerView: LayerAnimatedView {
    static let dotSize: CGFloat = 5
    static let spacing: CGFloat = 3.5
    static var intrinsicWidth: CGFloat { dotSize * 3 + spacing * 2 }

    var dotColor = NSColor.white {
        didSet { dots.forEach { $0.backgroundColor = dotColor.cgColor } }
    }

    private var dots: [CALayer] = []
    private static let animationKey = "typing"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        dots = (0..<3).map { _ in
            let dot = CALayer()
            dot.cornerRadius = Self.dotSize / 2
            dot.backgroundColor = dotColor.cgColor
            layer?.addSublayer(dot)
            return dot
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.intrinsicWidth, height: Self.dotSize + 6)
    }

    override func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var x = (bounds.width - Self.intrinsicWidth) / 2 + Self.dotSize / 2
        for dot in dots {
            dot.bounds = CGRect(x: 0, y: 0, width: Self.dotSize, height: Self.dotSize)
            dot.position = CGPoint(x: x, y: bounds.midY)
            x += Self.dotSize + Self.spacing
        }
        CATransaction.commit()
    }

    override func updateAnimation() {
        guard shouldAnimate else {
            for (index, dot) in dots.enumerated() {
                dot.removeAnimation(forKey: Self.animationKey)
                dot.opacity = [0.4, 0.7, 1][index]
                dot.transform = CATransform3DIdentity
            }
            return
        }

        let now = CACurrentMediaTime()
        for (index, dot) in dots.enumerated() where dot.animation(forKey: Self.animationKey) == nil {
            dot.opacity = 1
            let bounce = CABasicAnimation(keyPath: "transform.translation.y")
            bounce.fromValue = 1.6
            bounce.toValue = -2.8
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.35
            fade.toValue = 1

            let group = CAAnimationGroup()
            group.animations = [bounce, fade]
            group.duration = 0.38
            group.autoreverses = true
            group.repeatCount = .infinity
            group.beginTime = now + Double(index) * 0.13
            group.fillMode = .backwards
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.isRemovedOnCompletion = false
            dot.add(group, forKey: Self.animationKey)
        }
    }
}
