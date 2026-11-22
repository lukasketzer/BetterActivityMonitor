import AppKit
import SwiftUI

/// A progress ring (track plus a round-capped arc from 12 o'clock, clockwise) whose changes animate in
/// Core Animation. A SwiftUI `.animation` on a trimmed `Circle` re-ran the whole window's view graph and layout
/// on every display frame (0.6 s per sample at 120 Hz), which cost about a quarter of a core per ring on the
/// Overview, even with the window closed. Here the render server interpolates `strokeEnd` and the app only
/// does work when the value changes.
struct RingGauge: NSViewRepresentable {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat
    var trackOpacity: Double = 0.16
    var animationDuration: Double = 0.6

    func makeNSView(context: Context) -> RingLayerView { RingLayerView() }

    func updateNSView(_ view: RingLayerView, context: Context) {
        let resolved = color.resolve(in: context.environment)
        view.update(fraction: min(max(fraction, 0.004), 1),
                    color: resolved.cgColor,
                    trackColor: resolved.cgColor.copy(alpha: CGFloat(Double(resolved.opacity) * trackOpacity)) ?? resolved.cgColor,
                    lineWidth: lineWidth,
                    animated: !context.transaction.disablesAnimations && animationDuration > 0,
                    duration: animationDuration)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RingLayerView, context: Context) -> CGSize? {
        // Fills whatever square it is offered, like the Circle shapes it replaces.
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 10, height: 10))
    }
}

final class RingLayerView: NSView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private var lineWidth: CGFloat = 1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        for shape in [track, arc] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull(), "strokeColor": NSNull(),
                             "lineWidth": NSNull()]
            layer?.addSublayer(shape)
        }
        arc.strokeEnd = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks go to the SwiftUI button around it

    override func layout() {
        super.layout()
        updatePaths()
    }

    func update(fraction: Double, color: CGColor, trackColor: CGColor, lineWidth: CGFloat, animated: Bool, duration: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.strokeColor = trackColor
        arc.strokeColor = color
        if lineWidth != self.lineWidth {
            self.lineWidth = lineWidth
            track.lineWidth = lineWidth
            arc.lineWidth = lineWidth
            updatePaths()
        }
        CATransaction.commit()

        let target = CGFloat(fraction)
        guard target != arc.strokeEnd else { return }
        // Start from what is on screen, so a new value mid-animation continues smoothly.
        let from = arc.presentation()?.strokeEnd ?? arc.strokeEnd
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.strokeEnd = target
        CATransaction.commit()
        guard animated, window != nil else { return }
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = from
        animation.toValue = target
        animation.duration = duration
        // Close to SwiftUI's .smooth spring: fast start, no overshoot.
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.8, 0.3, 1)
        arc.add(animation, forKey: "strokeEnd")
    }

    private func updatePaths() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        let rect = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        // Centred on the edge of the square, like `Circle().stroke`: half the line lies outside the frame.
        let radius = side / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let path = CGMutablePath()
        // Unflipped layer: π/2 is 12 o'clock; clockwise on screen is decreasing angle.
        path.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for shape in [track, arc] {
            shape.frame = bounds
            shape.path = path
        }
        CATransaction.commit()
    }
}
