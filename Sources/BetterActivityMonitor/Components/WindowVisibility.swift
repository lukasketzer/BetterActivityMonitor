import AppKit
import SwiftUI

extension View {
    /// Calls `action` with whether the hosting window is on screen at all (not closed, minimized, on another Space
    /// or fully covered), right away and whenever that changes.
    func onWindowVisibilityChange(_ action: @escaping (Bool) -> Void) -> some View {
        background(WindowVisibilityReader(action: action))
    }
}

/// SwiftUI keeps a closed or hidden window's view graph alive and keeps updating it: with the main window
/// closed the app still laid out the Overview every frame. Observing the window's occlusion state lets the
/// content stop while nobody can see it.
private struct WindowVisibilityReader: NSViewRepresentable {
    var action: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView() }

    func updateNSView(_ view: ReaderView, context: Context) { view.action = action }

    final class ReaderView: NSView {
        var action: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var reported: Bool?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            })
            // Closing orders the window out; the occlusion change can arrive later than this.
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.send(false) }
            })
            // While SwiftUI sets the window up it is not on screen yet; ask once it has been ordered in.
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        private func report() {
            guard let window else { return }
            send(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func send(_ visible: Bool) {
            guard visible != reported else { return }
            reported = visible
            action?(visible)
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
