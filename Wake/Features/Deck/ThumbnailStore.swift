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
    static let shared = ThumbnailStore(folder: "Thumbnails", width: 480)
    static let moments = ThumbnailStore(folder: "Moments", width: 720)

    /// Bumps when any thumbnail changes, so cards redraw.
    private(set) var version = 0

    @ObservationIgnored private var cache: [UUID: NSImage] = [:]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let width: CGFloat

    private init(folder: String, width: CGFloat) {
        self.width = width
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appending(path: folder, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `id` is a thread's (Deck) or a moment's.
    func image(for id: UUID) -> NSImage? {
        _ = version
        if let image = cache[id] { return image }
        guard let image = NSImage(contentsOf: fileURL(for: id)) else { return nil }
        cache[id] = image
        return image
    }

    func capture(_ page: BrowserPage, for id: UUID) {
        guard page.webView.window != nil, page.webView.bounds.width > 0 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(width))
        page.webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            MainActor.assumeIsolated {
                guard let self, let image else { return }
                self.cache[id] = image
                self.version += 1
                self.write(image, to: self.fileURL(for: id))
            }
        }
    }

    func remove(_ id: UUID) {
        cache[id] = nil
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).jpg")
    }

    private func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        else { return }
        Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
    }
}
