import AppKit
import SwiftUI

/// Reaches the hosting NSWindow to make it transparent and to seat the traffic lights
/// vertically centred in the 56pt toolbar.
///
/// Limitation: AppKit has no public API for traffic-light placement. We resize the
/// titlebar container and move the standard buttons ourselves. AppKit lays them out
/// again on resizes, full-screen transitions and title changes, so we watch the
/// buttons' own frames and re-seat them whenever AppKit moves them.
struct WindowConfigurator: NSViewRepresentable {
    /// Zen mode hides the traffic lights until the toolbar is revealed.
    var trafficLightsHidden = false
    var onClose: () -> Void = {}
    /// Hands the hosting window to its owner once the view is in it.
    var onWindow: (NSWindow) -> Void = { _ in }

    func makeNSView(context: Context) -> ConfiguringView { ConfiguringView() }

    func updateNSView(_ view: ConfiguringView, context: Context) {
        view.onClose = onClose
        view.onWindow = onWindow
        if let window = view.window { onWindow(window) }
        view.setTrafficLightsHidden(trafficLightsHidden)
    }

    final class ConfiguringView: NSView {
        var onClose: () -> Void = {}
        var onWindow: (NSWindow) -> Void = { _ in }
        private var tokens: [NSObjectProtocol] = []
        private var trafficLightsHidden = false

        func setTrafficLightsHidden(_ hidden: Bool) {
            guard hidden != trafficLightsHidden else { return }
            trafficLightsHidden = hidden
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                for button in buttons.compactMap({ window?.standardWindowButton($0) }) {
                    button.animator().alphaValue = hidden ? 0 : 1
                }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { return }
            onWindow(window)
            configure(window)
            observe(window)
        }

        private func configure(_ window: NSWindow) {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: 760, height: 520)
            layoutTrafficLights(in: window)
        }

        private func observe(_ window: NSWindow) {
            let windowEvents: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification,
            ]
            tokens = windowEvents.map { observe($0, object: window) }
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose() }
            })

            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for button in buttons.compactMap(window.standardWindowButton) {
                button.postsFrameChangedNotifications = true
                tokens.append(observe(NSView.frameDidChangeNotification, object: button))
            }
        }

        private func observe(_ name: Notification.Name, object: AnyObject) -> NSObjectProtocol {
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setNeedsTrafficLightLayout() }
            }
        }

        /// Notifications arrive mid-way through AppKit's own titlebar layout, which may
        /// move another button afterwards. Re-seat once, on the next runloop turn.
        private func setNeedsTrafficLightLayout() {
            guard !isLayingOut, !isLayoutPending else { return }
            isLayoutPending = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isLayoutPending = false
                    if let window = self.window { self.layoutTrafficLights(in: window) }
                }
            }
        }

        private var isLayingOut = false
        private var isLayoutPending = false
        private var buttonSpacing: CGFloat?

        private func layoutTrafficLights(in window: NSWindow) {
            guard !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let mini = window.standardWindowButton(.miniaturizeButton),
                  let zoom = window.standardWindowButton(.zoomButton),
                  let titlebarView = close.superview,
                  let container = titlebarView.superview
            else { return }

            isLayingOut = true
            defer { isLayingOut = false }
            let height = Metrics.toolbarHeight
            container.frame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
            titlebarView.frame = container.bounds

            // Measured once from AppKit's own layout; later reads may catch it mid-relayout.
            let measured = mini.frame.minX - close.frame.minX
            if buttonSpacing == nil, measured > close.frame.width { buttonSpacing = measured }
            let spacing = buttonSpacing ?? close.frame.width + 7
            for (index, button) in [close, mini, zoom].enumerated() {
                button.setFrameOrigin(NSPoint(
                    x: Metrics.toolbarPadding + CGFloat(index) * spacing,
                    y: ((height - button.frame.height) / 2).rounded()
                ))
            }
        }
    }
}
