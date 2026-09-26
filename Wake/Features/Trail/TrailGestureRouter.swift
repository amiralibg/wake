import AppKit
import SwiftUI
import WebKit

/// Sits behind the trail and watches trackpad scroll gestures in its window.
/// Each gesture is routed once, at its start:
/// - mostly vertical → the page, untouched;
/// - horizontal over glass or a card header → the trail;
/// - horizontal over a page → we ask the page (async JS) whether anything under the
///   pointer can scroll that way. Events are held for those few milliseconds, then
///   replayed to the page or applied to the trail.
///
/// Limitation: pages that pan horizontally in their own JS wheel handlers (maps,
/// canvas editors) without CSS overflow look "not scrollable" to the probe, so the
/// trail takes those swipes.
///
/// Mouse wheels have no gestures: plain scrolling always goes to the page, and
/// ⇧-scroll steps through the columns one notch at a time. That takes ⇧-scroll's
/// usual horizontal scrolling away from pages (wide tables, code); Settings ▸ General
/// turns it off.
struct TrailGestureRouter: NSViewRepresentable {
    let trail: TrailModel
    let isEnabled: Bool
    var onPageScroll: () -> Void = {}

    func makeNSView(context: Context) -> RouterView {
        RouterView(trail: trail)
    }

    func updateNSView(_ view: RouterView, context: Context) {
        view.trail = trail
        view.isEnabled = isEnabled
        view.onPageScroll = onPageScroll
    }

    final class RouterView: NSView {
        var trail: TrailModel
        var isEnabled = true
        var onPageScroll: () -> Void = {}

        private enum Route { case undecided, probing, trail, page }

        private var monitor: Any?
        private var route: Route?
        private var gestureID = 0
        private var held: [NSEvent] = []
        private var travel = CGSize.zero
        private var samples: [(time: TimeInterval, dx: CGFloat)] = []
        private var wheelTravel: CGFloat = 0
        private var lastWheelTime: TimeInterval = 0
        private var lastStepTime: TimeInterval = 0

        init(trail: TrailModel) {
            self.trail = trail
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let swallow = MainActor.assumeIsolated { self?.shouldSwallow(event) ?? false }
                return swallow ? nil : event
            }
        }

        // MARK: Routing

        private func shouldSwallow(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }

            if !event.momentumPhase.isEmpty {
                // Momentum after a trail swipe is ours; the snap already happened.
                if route == .trail {
                    if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { route = nil }
                    return true
                }
                return false
            }

            // Mouse wheels have no phase.
            guard !event.phase.isEmpty else { return routeWheel(event) }

            if event.phase.contains(.began) {
                guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else {
                    route = nil
                    return false
                }
                beginGesture()
            }

            switch route {
            case .page:
                if isEnabled, abs(event.scrollingDeltaY) > 1 { onPageScroll() }
                return false
            case nil:
                return false
            case .probing:
                held.append(event)
                return true
            case .trail:
                applyToTrail(event)
                return true
            case .undecided:
                held.append(event)
                travel.width += event.scrollingDeltaX
                travel.height += event.scrollingDeltaY
                if hypot(travel.width, travel.height) < 5, !isFinal(event) { return true }
                decide(for: event)
                return true
            }
        }

        private func beginGesture() {
            gestureID += 1
            route = .undecided
            held = []
            travel = .zero
            samples = []
        }

        private func decide(for event: NSEvent) {
            guard abs(travel.width) > abs(travel.height) * 1.2 else {
                releaseToPage()
                return
            }
            guard let page = page(under: event) else {
                takeForTrail()
                return
            }
            route = .probing
            let id = gestureID
            let point = page.webView.convert(event.locationInWindow, from: nil)
            let y = page.webView.isFlipped ? point.y : page.webView.bounds.height - point.y
            let direction = travel.width < 0 ? 1 : -1
            Task { @MainActor [weak self] in
                let pageWantsIt = await page.canScrollHorizontally(at: CGPoint(x: point.x, y: y), direction: direction)
                guard let self, id == self.gestureID, self.route == .probing else { return }
                pageWantsIt ? self.releaseToPage() : self.takeForTrail()
            }
        }

        private func releaseToPage() {
            route = .page
            let events = held
            held = []
            // Local monitors run in NSApplication.sendEvent, so replaying through the
            // window reaches the view under the pointer without looping back here.
            events.forEach { window?.sendEvent($0) }
        }

        private func takeForTrail() {
            route = .trail
            let events = held
            held = []
            events.forEach(applyToTrail)
        }

        private func applyToTrail(_ event: NSEvent) {
            let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 12
            trail.scroll(by: dx)
            samples.append((event.timestamp, dx))
            samples.removeAll { event.timestamp - $0.time > 0.08 }
            if isFinal(event) {
                trail.endScroll(velocity: velocity)
            }
        }

        // MARK: Mouse wheel

        /// ⇧-scroll over the trail moves between columns; anything else is the page's.
        private func routeWheel(_ event: NSEvent) -> Bool {
            guard isEnabled, BrowsingSettings.shared.shiftScrollMovesColumns,
                  event.modifierFlags.contains(.shift),
                  bounds.contains(convert(event.locationInWindow, from: nil)),
                  !isOverOtherWebView(event)
            else { return false }
            stepTrail(with: event)
            return true
        }

        /// A notch is one column, like pressing ⌘] or ⌘[.
        private func stepTrail(with event: NSEvent) {
            // ⇧ usually turns the wheel horizontal, but some mouse drivers leave it vertical.
            let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            if event.timestamp - lastWheelTime > 0.3 { wheelTravel = 0 }
            lastWheelTime = event.timestamp
            wheelTravel += delta
            // Notched wheels report lines; smooth-scrolling ones report points.
            let notch: CGFloat = event.hasPreciseScrollingDeltas ? 30 : 1
            // Free-spinning wheels send bursts; a steady pace keeps the trail from flying past.
            guard abs(wheelTravel) >= notch, event.timestamp - lastStepTime > 0.09 else { return }
            if wheelTravel < 0 { trail.focusNext() } else { trail.focusPrevious() }
            wheelTravel = 0
            lastStepTime = event.timestamp
        }

        /// A pinned app's page floats over the trail; its scrolling stays its own.
        private func isOverOtherWebView(_ event: NSEvent) -> Bool {
            guard let contentView = window?.contentView,
                  let hit = contentView.hitTest(event.locationInWindow) else { return false }
            var view: NSView? = hit
            while let current = view, !(current is WKWebView) { view = current.superview }
            guard let webView = view else { return false }
            return !trail.columns.contains { $0.webView === webView }
        }

        private var velocity: CGFloat {
            guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
            return samples.reduce(0) { $0 + $1.dx } / CGFloat(last.time - first.time)
        }

        private func isFinal(_ event: NSEvent) -> Bool {
            event.phase.contains(.ended) || event.phase.contains(.cancelled)
        }

        private func page(under event: NSEvent) -> BrowserPage? {
            trail.columns.first { page in
                let view = page.webView
                return view.window === window && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            }
        }
    }
}
