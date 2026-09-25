import Foundation
import SwiftData

/// A thread as stored on disk: an ordered list of columns plus a title.
/// Resolved threads keep their columns so Moments can show what was found.
@Model
final class ThreadRecord {
    @Attribute(.unique) var id: UUID
    var customTitle: String?
    /// Last computed title, so lists don't need live pages.
    var title: String
    var createdAt: Date
    var lastActiveAt: Date
    var focusedIndex: Int
    var isResolved: Bool
    var outcome: String?
    var resolvedAt: Date?
    /// Developer mode chosen for this thread; `nil` is automatic.
    var developerMode: Bool?
    @Relationship(deleteRule: .cascade, inverse: \ColumnRecord.thread)
    var columns: [ColumnRecord] = []

    init(id: UUID, title: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        lastActiveAt = createdAt
        focusedIndex = 0
        isResolved = false
    }

    /// SwiftData relationships are unordered; `order` restores the trail's sequence.
    var orderedColumns: [ColumnRecord] {
        columns.sorted { $0.order < $1.order }
    }
}

@Model
final class ColumnRecord {
    var order: Int
    var url: URL
    var title: String
    /// Share of the stage width, when the user resized the column.
    var widthFraction: Double?
    var thread: ThreadRecord?

    init(order: Int, url: URL, title: String, widthFraction: Double?) {
        self.order = order
        self.url = url
        self.title = title
        self.widthFraction = widthFraction
    }
}
