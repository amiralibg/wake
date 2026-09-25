import AppKit
import SwiftUI

extension View {
    /// Runs `action` when Esc is pressed in this window while `isActive`.
    ///
    /// Needed because a focused WKWebView consumes Esc itself, so SwiftUI's
    /// `.cancelAction` shortcuts and `onKeyPress` never see it.
    func onEscapeKey(isActive: Bool, perform action: @escaping () -> Void) -> some View {
        background(EscapeKeyMonitor(isActive: isActive, action: action))
    }
}

private struct EscapeKeyMonitor: NSViewRepresentable {
    let isActive: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.action = action
        view.isActive = isActive
    }

    final class MonitorView: NSView {
        var action: () -> Void = {}
        var isActive = false { didSet { updateMonitor() } }
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        private func updateMonitor() {
            let shouldMonitor = isActive && window != nil
            if shouldMonitor, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
                    return handled ? nil : event
                }
            } else if !shouldMonitor, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window, event.keyCode == 53 else { return false }
            action()
            return true
        }
    }
}
