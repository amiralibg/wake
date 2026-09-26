import Dispatch
import Foundation

/// Gives memory back when macOS says it's running short.
///
/// Wake drops its own caches (and, when it's critical, background threads' web
/// views); each WebContent process handles the same notification itself (WebKit
/// purges its caches and discards decoded images).
@MainActor
enum MemoryPressure {
    private static var source: DispatchSourceMemoryPressure?

    static func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak source] in
            let critical = source?.data.contains(.critical) ?? false
            MainActor.assumeIsolated { relieve(critical: critical) }
        }
        source.activate()
        self.source = source
    }

    /// Critical pressure also discards background threads (their web views are the
    /// bulk of Wake's memory); macOS would otherwise start killing WebContent
    /// processes itself.
    static func relieve(critical: Bool) {
        ThumbnailStore.shared.purge()
        ThumbnailStore.moments.purge()
        FaviconCache.shared.purge()
        if critical { BrowserModel.discardBackgroundThreads() }
    }
}
