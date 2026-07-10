import AppKit
import QuartzCore
import SwiftUI

struct EqualizerView: View {
    let isAnimating: Bool
    let seed: Int
    var barColor: Color = .primary

    var body: some View {
        EqualizerBarsRepresentable(isAnimating: isAnimating, barColor: barColor)
            .frame(width: 28, height: 14)
    }
}

private struct EqualizerBarsRepresentable: NSViewRepresentable {
    let isAnimating: Bool
    let barColor: Color

    func makeNSView(context: Context) -> EqualizerBarsView {
        EqualizerBarsView()
    }

    func updateNSView(_ nsView: EqualizerBarsView, context: Context) {
        nsView.isAnimating = isAnimating
        nsView.barColor = NSColor(barColor)
    }
}

final class EqualizerBarsView: NSView {
    var isAnimating = true {
        didSet { updateAnimationState() }
    }

    var barColor = NSColor.white {
        didSet { barLayers.forEach { $0.backgroundColor = barColor.withAlphaComponent(0.9).cgColor } }
    }

    private let barCount = 4
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 14
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 3
    private var barLayers: [CALayer] = []

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setupBars()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layoutBars()
        updateAnimationState()
    }

    private func setupBars() {
        barLayers = (0..<barCount).map { _ in
            let bar = CALayer()
            bar.backgroundColor = barColor.withAlphaComponent(0.9).cgColor
            bar.cornerRadius = 1.5
            bar.anchorPoint = CGPoint(x: 0.5, y: 1)
            layer?.addSublayer(bar)
            return bar
        }
    }

    private func layoutBars() {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        var x = (bounds.width - totalWidth) / 2 + barWidth / 2
        let baseline = bounds.height - 1

        for bar in barLayers {
            let height = isAnimating ? minHeight : minHeight + 2
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: height)
            bar.position = CGPoint(x: x, y: baseline)
            x += barWidth + spacing
        }
    }

    private func updateAnimationState() {
        guard barLayers.count == barCount else { return }

        if isAnimating {
            for (index, bar) in barLayers.enumerated() {
                guard bar.animation(forKey: animationKey(index)) == nil else { continue }

                let animation = CABasicAnimation(keyPath: "bounds.size.height")
                animation.fromValue = minHeight
                animation.toValue = maxHeight
                animation.duration = 0.3 + Double(index) * 0.09
                animation.beginTime = CACurrentMediaTime() + Double(index) * 0.06
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.isRemovedOnCompletion = false

                bar.bounds.size.height = maxHeight
                bar.add(animation, forKey: animationKey(index))
            }
        } else {
            for (index, bar) in barLayers.enumerated() {
                bar.removeAnimation(forKey: animationKey(index))
                bar.bounds.size.height = minHeight + CGFloat(index + 1) * 1.2
            }
        }
    }

    private func animationKey(_ index: Int) -> String {
        "equalizer-\(index)"
    }
}
