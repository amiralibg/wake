import AppKit
import Observation
import WebKit

/// Snapshots of each thread's focused page, for Deck cards (and of saved moments,
/// in `moments`). Kept in memory and as small JPEGs on disk so cards still have a
/// picture after a relaunch.
///
/// Limitation: WKWebView can only snapshot a view that is in a window, so a thread's
/// picture is refreshed while it's on screen (after loads, and when the Deck opens).
@MainActor
@Observable
final class ThumbnailStore {
    static let shared = ThumbnailStore(folder: "Thumbnails", width: 480, memoryLimit: 48 << 20)
    static let moments = ThumbnailStore(folder: "Moments", width: 720, memoryLimit: 48 << 20)

    /// Bumps when any thumbnail changes, so cards redraw.
    private(set) var version = 0

    /// Decoded pictures, bounded by their pixel bytes (a 480 pt snapshot on a Retina
    /// display is ~1.8 MB). Anything evicted is read back from its JPEG on demand.
    @ObservationIgnored private let cache = NSCache<NSUUID, NSImage>()
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let width: CGFloat

    private init(folder: String, width: CGFloat, memoryLimit: Int) {
        self.width = width
        cache.totalCostLimit = memoryLimit
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appending(path: folder, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `id` is a thread's (Deck) or a moment's.
    func image(for id: UUID) -> NSImage? {
        _ = version
        if let image = cache.object(forKey: id as NSUUID) { return image }
        guard let image = NSImage(contentsOf: fileURL(for: id)) else { return nil }
        store(image, for: id)
        return image
    }

    /// Memory is tight: drop every decoded picture (they're all on disk).
    func purge() {
        cache.removeAllObjects()
    }

    private func store(_ image: NSImage, for id: UUID) {
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh }
            ?? Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: id as NSUUID, cost: pixels * 4)
    }

    func capture(_ page: BrowserPage, for id: UUID) {
        guard page.webView.window != nil, page.webView.bounds.width > 0 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(width))
        page.webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            MainActor.assumeIsolated {
                guard let self, let image else { return }
                self.store(image, for: id)
                self.version += 1
                self.write(image, to: self.fileURL(for: id))
            }
        }
    }

    func remove(_ id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).jpg")
    }

    /// JPEG encoding takes tens of milliseconds for a Retina snapshot, so it runs off
    /// the main thread (going through TIFF, as before, also copied every pixel twice).
    private func write(_ image: NSImage, to url: URL) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        Task.detached(priority: .utility) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
