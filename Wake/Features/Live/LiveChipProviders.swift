import Foundation

/// Turns a page's live state into a chip. Providers are small and independent;
/// adding a new kind of chip means adding one here and, if it needs the page's
/// help, a reporter in `LiveScripts`.
@MainActor
protocol LiveChipProvider {
    func chip(for page: BrowserPage) -> LiveChip?
}

@MainActor
enum LiveChips {
    /// In priority order: the first chip is the one a Deck card shows.
    static let providers: [any LiveChipProvider] = [
        HTTPStatusChip(), CIStatusChip(), ConsoleErrorsChip(), PriceChip(), UnreadChip(), MediaChip(), ChangedChip(),
    ]

    static func chips(for page: BrowserPage) -> [LiveChip] {
        providers.compactMap { $0.chip(for: page) }
    }

    /// The most important chip across several pages (a thread).
    static func top(of pages: [BrowserPage]) -> LiveChip? {
        pages.compactMap { chips(for: $0).first }.min { rank($0) < rank($1) }
    }

    /// Same order as `providers`.
    private static func rank(_ chip: LiveChip) -> Int {
        [LiveChip.Kind.status, .ci, .errors, .price, .unread, .media, .changed].firstIndex(of: chip.kind) ?? .max
    }
}

/// "404", "500": the page came back with an error.
struct HTTPStatusChip: LiveChipProvider {
    func chip(for page: BrowserPage) -> LiveChip? {
        guard let status = page.live.httpStatus, status >= 400 else { return nil }
        return LiveChip(kind: .status, text: "\(status)", symbol: "exclamationmark.triangle.fill", tone: status >= 500 ? .bad : .warning)
    }
}

/// CI on GitHub pull request pages.
struct CIStatusChip: LiveChipProvider {
    func chip(for page: BrowserPage) -> LiveChip? {
        switch page.live.ci {
        case .passed: LiveChip(kind: .ci, text: "CI passed", symbol: "checkmark.circle.fill", tone: .good)
        case .failed: LiveChip(kind: .ci, text: "CI failed", symbol: "xmark.circle.fill", tone: .bad)
        case .pending: LiveChip(kind: .ci, text: "CI running", symbol: "circle.dotted", tone: .warning)
        case nil: nil
        }
    }
}

/// Console errors, in developer mode.
struct ConsoleErrorsChip: LiveChipProvider {
    func chip(for page: BrowserPage) -> LiveChip? {
        let count = page.devtools.errorCount
        guard page.isDeveloperMode, count > 0 else { return nil }
        return LiveChip(kind: .errors, text: "\(count) error\(count == 1 ? "" : "s")", symbol: "exclamationmark.octagon.fill", tone: .bad)
    }
}

/// A product's price, compared with the first time you saw it.
struct PriceChip: LiveChipProvider {
    func chip(for page: BrowserPage) -> LiveChip? {
        guard let price = page.live.price, let url = page.url else { return nil }
        let first = PriceWatch.shared.firstPrice(for: url) ?? price.amount
        let text = PriceWatch.format(price)
        if price.amount < first - 0.005 {
            return LiveChip(kind: .price, text: "\(text) ↓", symbol: "arrow.down", tone: .good)
        }
        if price.amount > first + 0.005 {
            return LiveChip(kind: .price, text: "\(text) ↑", symbol: "arrow.up", tone: .bad)
        }
        return LiveChip(kind: .price, text: text, symbol: "tag", tone: .neutral)
    }
}

/// "(3) Inbox": the unread count web apps put in their title.
struct UnreadChip: LiveChipProvider {
    func chip(for page: BrowserPage) -> LiveChip? {
        guard let count = PinnedApp.badge(in: page.title) else { return nil }
        return LiveChip(kind: .unread, text: "\(count) unread", symbol: "envelope.badge", tone: .accent)
    }
}

/// Playing audio or video: time and progress.
struct MediaChip: LiveChipProvider {
    func chip(for page: BrowserPage) -> LiveChip? {
        guard let media = page.live.media, media.isPlaying || media.current > 0 else { return nil }
        let text = media.duration.isFinite && media.duration > 0
            ? "\(Self.time(media.current)) / \(Self.time(media.duration))"
            : (media.isPlaying ? "Live" : "Paused")
        return LiveChip(
            kind: .media,
            text: text,
            symbol: media.isPlaying ? "speaker.wave.2.fill" : "pause.fill",
            tone: media.isPlaying ? .accent : .neutral,
            progress: media.duration.isFinite && media.duration > 0 ? min(1, media.current / media.duration) : nil
        )
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(seconds.isFinite ? seconds : 0)
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

/// The page's content changed while you were in another column.
struct ChangedChip: LiveChipProvider {
    func chip(for page: BrowserPage) -> LiveChip? {
        page.live.contentChanged ? LiveChip(kind: .changed, text: "Updated", symbol: "arrow.triangle.2.circlepath", tone: .accent) : nil
    }
}
