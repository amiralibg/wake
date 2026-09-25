import AppKit
import SwiftUI
import WebKit

/// Hosts a page's WKWebView. Rounding is done on the AppKit layer because SwiftUI's
/// clipShape does not reliably clip layer-hosted AppKit views like WKWebView.
struct PageWebView: NSViewRepresentable {
    let page: BrowserPage
    let cornerRadius: CGFloat
    /// The pointer entered or left the page's top-right corner.
    var onCornerHover: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> WebContainer {
        WebContainer()
    }

    func updateNSView(_ container: WebContainer, context: Context) {
        container.host(page.webView)
        container.cornerRadius = cornerRadius
        container.onCornerHover = onCornerHover
    }

    final class WebContainer: NSView {
        var cornerRadius: CGFloat = 0 {
            didSet { layer?.cornerRadius = cornerRadius }
        }
        var onCornerHover: (Bool) -> Void = { _ in }

        /// A tracking area rather than a SwiftUI hover zone: it notices the pointer
        /// without taking clicks away from whatever the page has in that corner.
        private var tracking: NSTrackingArea?
        private var isInCorner = false
        private let cornerSize = CGSize(width: 72, height: 52)

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            tracking = area
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let point = convert(event.locationInWindow, from: nil)
            let top = isFlipped ? point.y : bounds.height - point.y
            setCorner(point.x > bounds.width - cornerSize.width && top < cornerSize.height)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            setCorner(false)
        }

        private func setCorner(_ inside: Bool) {
            guard inside != isInCorner else { return }
            isInCorner = inside
            onCornerHover(inside)
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            layer?.cornerCurve = .continuous
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func host(_ webView: WKWebView) {
            guard webView.superview !== self else { return }
            subviews.forEach { $0.removeFromSuperview() }
            webView.frame = bounds
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }
    }
}
