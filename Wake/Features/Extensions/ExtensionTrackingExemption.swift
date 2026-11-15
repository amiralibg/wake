import Foundation
import WebKit

/// Keeps WebKit's Intelligent Tracking Prevention away from extensions' own origins.
///
/// Limitation (WebKit bug, seen on macOS 27): ITP treats each `webkit-extension://<id>`
/// origin like a website. One it has never seen a "user interaction" with gets its
/// website data removed again and again (`ObservedDomains.dataRecordsRemoved` in
/// `ResourceLoadStatistics/observations.db`), and that removal unregisters the
/// extension's background service worker. The extension still loads, but its popup
/// gets `undefined` back from `runtime.sendMessage`: Dark Reader stays on "Loading,
/// please wait", uBlock Origin shows blanks. Whether an origin was ever marked as
/// interacted with depends on what happened in its first session, so the failure
/// looked random per install.
///
/// There is no public API to exempt an origin, so this logs a user interaction for
/// each extension origin through WebKit's SPI `_logUserInteraction:completionHandler:`
/// on `WKWebsiteDataStore` (what WebKit's own tests use). If the SPI disappears, this
/// does nothing and the bug comes back; `responds(to:)` guards the call.
enum ExtensionTrackingExemption {
    @MainActor
    static func exempt(_ baseURL: URL, in store: WKWebsiteDataStore) {
        let selector = NSSelectorFromString("_logUserInteraction:completionHandler:")
        guard store.responds(to: selector) else { return }
        typealias Call = @convention(c) (AnyObject, Selector, NSURL, @escaping @convention(block) () -> Void) -> Void
        let call = unsafeBitCast(store.method(for: selector), to: Call.self)
        call(store, selector, baseURL as NSURL) {}
    }
}
