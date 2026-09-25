import AppKit
import SwiftUI

/// Window edges the pointer can reach.
enum WindowEdge: Hashable {
    case top, bottom, left
}

extension View {
    /// Calls `action` when the pointer arrives within `threshold` points of one of
    /// `edges` in this window.
    ///
    /// Limitation: a SwiftUI hover strip at the very edge doesn't work, because macOS
    /// keeps the outer few points of a window for its resize cursor and those moves
    /// never reach the content. So this watches mouse-moved events for the whole window
    /// instead; it never takes clicks away from what's under the pointer.
    func onWindowEdgeHover(_ edges: Set<WindowEdge>, threshold: CGFloat = 14, perform action: @escaping (WindowEdge) -> Void) -> some View {
        background(WindowEdgeMonitor(edges: edges, threshold: threshold, action: action))
    }
}

private struct WindowEdgeMonitor: NSViewRepresentable {
    let edges: Set<WindowEdge>
    let threshold: CGFloat
    let action: (WindowEdge) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.edges = edges
        view.threshold = threshold
        view.action = action
    }

    final class MonitorView: NSView {
        var edges: Set<WindowEdge> = []
        var threshold: CGFloat = 14
        var action: (WindowEdge) -> Void = { _ in }

        private var monitor: Any?
        private var current: WindowEdge?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard let window else { return }
            window.acceptsMouseMovedEvents = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return event
            }
        }

        private func handle(_ event: NSEvent) {
            guard let window, event.window === window, let content = window.contentView else { return }
            let point = content.convert(event.locationInWindow, from: nil)
            let height = content.bounds.height
            let y = content.isFlipped ? height - point.y : point.y
            let edge: WindowEdge? = if edges.contains(.bottom), y >= 0, y < threshold {
                .bottom
            } else if edges.contains(.top), height - y >= 0, height - y < threshold {
                .top
            } else if edges.contains(.left), point.x >= 0, point.x < threshold {
                .left
            } else {
                nil
            }
            guard edge != current else { return }
            current = edge
            if let edge { action(edge) }
        }
    }
}
