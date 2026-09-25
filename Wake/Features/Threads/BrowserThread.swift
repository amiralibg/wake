import Foundation
import Observation

/// A live thread: its trail of pages plus a title. Restored from a ThreadRecord
/// lazily, so pages only load once the thread is shown.
@MainActor
@Observable
final class BrowserThread: Identifiable {
    struct ColumnSnapshot {
        let url: URL
        let title: String
        let widthFraction: CGFloat?
    }

    let id: UUID
    let createdAt: Date
    var customTitle: String?
    var lastActiveAt: Date
    /// Developer mode for the whole thread; `nil` is automatic (on for localhost).
    var developerMode: Bool? {
        didSet { trail.developerModeOverride = developerMode }
    }
    let trail = TrailModel()

    @ObservationIgnored private var pendingColumns: [ColumnSnapshot]
    @ObservationIgnored private var pendingFocus: Int

    init(id: UUID = UUID(), customTitle: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.customTitle = customTitle
        self.createdAt = createdAt
        lastActiveAt = createdAt
        pendingColumns = []
        pendingFocus = 0
    }

    init(record: ThreadRecord) {
        id = record.id
        customTitle = record.customTitle
        developerMode = record.developerMode
        createdAt = record.createdAt
        lastActiveAt = record.lastActiveAt
        pendingColumns = record.orderedColumns.map {
            ColumnSnapshot(url: $0.url, title: $0.title, widthFraction: $0.widthFraction.map { CGFloat($0) })
        }
        pendingFocus = record.focusedIndex
    }

    var title: String {
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespaces).isEmpty { return customTitle }
        return trail.columns.first?.displayTitle ?? pendingColumns.first?.title ?? "New thread"
    }

    var pageCount: Int { max(trail.columns.count, pendingColumns.count) }

    /// Creates the pages. Call after the owner has hooked `trail` up.
    func restoreIfNeeded() {
        trail.developerModeOverride = developerMode
        guard !pendingColumns.isEmpty else { return }
        trail.restore(pendingColumns, focusedIndex: pendingFocus)
        pendingColumns = []
    }

    /// What to persist. A thread that was never shown still has its columns pending.
    var snapshot: (columns: [ColumnSnapshot], focusedIndex: Int) {
        guard pendingColumns.isEmpty else { return (pendingColumns, pendingFocus) }
        let columns = trail.columns.filter { !$0.isEphemeral }.compactMap { page in
            (page.url ?? page.requestedURL).map { ColumnSnapshot(url: $0, title: page.displayTitle, widthFraction: trail.widthFraction(of: page)) }
        }
        return (columns, min(trail.focusedIndex, max(columns.count - 1, 0)))
    }
}
