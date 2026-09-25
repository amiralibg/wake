import Foundation
import SwiftData

/// A pinned web app as stored on disk.
@Model
final class PinnedAppRecord {
    @Attribute(.unique) var id: UUID
    var url: URL
    var title: String
    var order: Int

    init(id: UUID = UUID(), url: URL, title: String, order: Int) {
        self.id = id
        self.url = url
        self.title = title
        self.order = order
    }
}
