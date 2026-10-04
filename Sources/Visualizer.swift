import AppKit
import SwiftUI

/// Four pill bars that pulse while music plays. The motion is pure Core
/// Animation (committed once, then run by the render server), so the app
/// itself does no per-frame work. Capped at 30fps to go easy on the GPU.
struct Visualizer: NSViewRepresentable {
    var playing: Bool
    var color: NSColor

    func makeNSView(context: Context) -> VisualizerView { VisualizerView() }

    func updateNSView(_ view: VisualizerView, context: Context) {
        view.setColor(color)
        view.setPlaying(playing)
    }
}

final class VisualizerView: NSView {
    private static let barWidth: CGFloat = 3
    // Closed loops (first == last) of heights relative to the view height.
    private static let patterns: [[CGFloat]] = [
        [0.35, 0.9, 0.5, 1.0, 0.45, 0.75, 0.35],
        [0.6, 0.3, 1.0, 0.55, 0.85, 0.4, 0.6],
        [0.45, 1.0, 0.65, 0.3, 0.9, 0.55, 0.45],
        [0.8, 0.45, 0.7, 1.0, 0.35, 0.6, 0.8],
    ]
    private static let durations: [CFTimeInterval] = [1.7, 1.45, 1.9, 1.6]

    private let bars: [CALayer] = VisualizerView.patterns.map { _ in CALayer() }
    private var playing = false
    private var color: NSColor?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bars.forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let w = Self.barWidth
        let gap = (bounds.width - w * CGFloat(bars.count)) / CGFloat(bars.count - 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.cornerRadius = w / 2
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: bounds.midY)
            bar.bounds.size = CGSize(width: w, height: w)
        }
        CATransaction.commit()
        if playing { startPulsing() }
    }

    func setColor(_ newColor: NSColor) {
        guard newColor != color else { return }
        let animated = color != nil
        color = newColor
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.4 : 0)
        CATransaction.setDisableActions(!animated)
        bars.forEach { $0.backgroundColor = newColor.cgColor }
        CATransaction.commit()
    }

    func setPlaying(_ newValue: Bool) {
        guard newValue != playing else { return }
        playing = newValue
        newValue ? startPulsing() : settle()
    }

    private func startPulsing() {
        let h = bounds.height
        guard h > 0 else { return }
        for (i, bar) in bars.enumerated() where bar.animation(forKey: "pulse") == nil {
            bar.removeAnimation(forKey: "settle")
            let a = CAKeyframeAnimation(keyPath: "bounds.size.height")
            a.values = Self.patterns[i].map { max($0 * h, Self.barWidth) }
            a.duration = Self.durations[i]
            a.calculationMode = .cubic
            a.repeatCount = .infinity
            a.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            bar.add(a, forKey: "pulse")
        }
    }

    /// Eases every bar from wherever it is down to a resting dot.
    private func settle() {
        for bar in bars {
            let current = bar.presentation()?.bounds.height ?? Self.barWidth
            bar.removeAnimation(forKey: "pulse")
            let a = CABasicAnimation(keyPath: "bounds.size.height")
            a.fromValue = current
            a.toValue = Self.barWidth
            a.duration = 0.35
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bar.add(a, forKey: "settle")
        }
    }
}
