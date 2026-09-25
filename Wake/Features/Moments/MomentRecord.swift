import Foundation
import SwiftData

/// A saved moment: a page as it was when you saved it, with where you were in it,
/// what you'd selected, and why. Every property has a default so the store can add
/// fields later without a migration plan.
@Model
final class MomentRecord {
    @Attribute(.unique) var id: UUID = UUID()
    var url: URL = URL(string: "about:blank")!
    var title: String = ""
    var createdAt: Date = Date.now
    /// "Why": the user's own reason, optional.
    var note: String?
    /// The selection when saved, re-highlighted on restore.
    var selectedText: String?
    /// A little of the text just before the selection, to find the right occurrence.
    var selectionPrefix: String?
    var scrollY: Double = 0
    /// How far down the page (0…1), used when the page's height has changed.
    var scrollFraction: Double = 0
    /// SHA-256 of the page's visible text when saved (whitespace collapsed).
    var contentHash: String = ""
    /// The page's visible text when saved (capped), to describe what changed.
    var contentText: String = ""
    /// When to bring it back up; `nil` = only when you're on its site.
    var resurfaceAt: Date?
    var lastOpenedAt: Date?
    var openCount: Int = 0
    var lastCheckedAt: Date?
    /// Set by the background check when the page no longer matches what was saved.
    var changedAt: Date?
    var changeSummary: String?
    var isArchived: Bool = false
    /// The thread it was saved from.
    var threadID: UUID?

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    var host: String {
        let host = url.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Last time you had anything to do with it.
    var lastSeenAt: Date { lastOpenedAt ?? createdAt }
}
