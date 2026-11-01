import AppKit
import SwiftUI

/// A tooltip that floats above the whole window instead of living inside the view that shows it.
///
/// It is drawn in a borderless, click-through child window, so no card, scroll view or the
/// AppKit process table can clip or cover it, and it never takes part in the hovered view's layout.
@MainActor
final class FloatingTooltip {
    static let shared = FloatingTooltip()

    private var panel: NSPanel?
    private var host: NSHostingView<AnyView>?
    private weak var owner: TooltipAnchor?

    /// Shows `content` beside `x` (in the anchor view's coordinates), top-aligned with the anchor,
    /// flipping to the left and clamping so it stays inside the window.
    func show(_ content: some View, atX x: CGFloat, from anchor: TooltipAnchor) {
        guard let view = anchor.view, let window = view.window else { return hide(from: anchor) }
        let panel = panel ?? makePanel()
        let host = host!
        host.rootView = AnyView(content.fixedSize())
        let size = host.fittingSize

        // Anchor view is flipped, so (x, 0) is the top edge at the hover position.
        let top = window.convertPoint(toScreen: view.convert(CGPoint(x: x, y: 0), to: nil))
        let bounds = window.frame
        let gap: CGFloat = 10
        var originX = top.x + gap
        if originX + size.width > bounds.maxX { originX = top.x - gap - size.width }
        originX = max(min(originX, bounds.maxX - size.width), bounds.minX)
        let originY = max(top.y - size.height, bounds.minY)

        panel.appearance = window.effectiveAppearance
        panel.setFrame(CGRect(x: originX, y: originY, width: size.width, height: size.height), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
        owner = anchor
    }

    /// Hides the tooltip if `anchor` is the view currently showing it (so a chart that just lost
    /// the hover can't hide the tooltip a neighbouring chart just showed).
    func hide(from anchor: TooltipAnchor) {
        guard owner === anchor || owner == nil, let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        owner = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true   // hovering over the tooltip keeps hovering the chart below
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        self.host = host
        return panel
    }
}

/// Reference to the AppKit view behind a SwiftUI view, used to place a `FloatingTooltip`.
@MainActor
final class TooltipAnchor {
    fileprivate(set) weak var view: NSView?
}

/// Place as a `.background` of the hovered view; it has the same frame and records itself in `anchor`.
struct TooltipAnchorView: NSViewRepresentable {
    let anchor: TooltipAnchor

    func makeNSView(context: Context) -> NSView {
        let view = FlippedView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
