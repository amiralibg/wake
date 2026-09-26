import AppKit
import CryptoKit
import SwiftUI

struct Favicon: View {
    let url: URL?
    let host: String
    var size: CGFloat = 12

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? url.flatMap(FaviconCache.shared.cached) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                MonogramIcon(host: host)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size / 4, style: .continuous))
        .task(id: url) {
            guard let url else { return }
            image = await FaviconCache.shared.image(for: url)
        }
    }
}

/// Favicons decoded once and shared by every row that shows them.
///
/// AsyncImage keeps nothing: each palette row, Deck card and trail chip that appears
/// fetched and decoded its icon again. Here each URL is fetched once (concurrent
/// requests share the same task), kept in memory and on disk (so icons are there
/// at once after a relaunch), and a missing icon isn't asked for again for a while.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()

    private let images = NSCache<NSURL, NSImage>()
    /// When each icon last failed to load.
    private var missing: [URL: Date] = [:]
    private var loading: [URL: Task<NSImage?, Never>] = [:]
    private let folder: URL
    private static let retryAfter: TimeInterval = 10 * 60

    private init() {
        images.countLimit = 500
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Favicons", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Memory is tight: forget decoded icons (they're still on disk).
    func purge() {
        images.removeAllObjects()
    }

    func cached(_ url: URL) -> NSImage? {
        images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let image = cached(url) { return image }
        if let failed = missing[url], Date.now.timeIntervalSince(failed) < Self.retryAfter { return nil }
        if let task = loading[url] { return await task.value }
        let file = folder.appending(path: Self.fileName(for: url))
        let task = Task<NSImage?, Never> {
            if let data = await Self.read(file), let image = NSImage(data: data) { return image }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = NSImage(data: data)
            else { return nil }
            Task.detached(priority: .utility) { try? data.write(to: file, options: .atomic) }
            return image
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image {
            images.setObject(image, forKey: url as NSURL)
            missing[url] = nil
        } else {
            missing[url] = .now
        }
        return image
    }

    private nonisolated static func read(_ file: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) { try? Data(contentsOf: file) }.value
    }

    /// A stable, filesystem-safe name for an icon URL.
    private static func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// Stable coloured square with the site's first letter, used until a favicon loads.
struct MonogramIcon: View {
    let host: String

    var body: some View {
        let letter = host.first.map { String($0).uppercased() } ?? "•"
        Rectangle()
            .fill(color)
            .overlay {
                Text(letter)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }

    private var color: Color { Self.color(for: host) }

    static func color(for host: String) -> Color {
        let hue = Double(host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.72)
    }
}
