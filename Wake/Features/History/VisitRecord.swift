import Foundation
import SwiftData

/// One entry per URL, bumped on each visit. Feeds "Recent" in the palette.
@Model
final class VisitRecord {
    @Attribute(.unique) var url: URL
    var title: String
    var visitedAt: Date
    var visitCount: Int

    init(url: URL, title: String, visitedAt: Date = .now) {
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
        visitCount = 1
    }
}
