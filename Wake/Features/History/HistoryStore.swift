import Foundation
import Observation
import SwiftData

/// Pages you visited and things you searched for, in the same SwiftData store as
/// threads. Observable, so History updates as you browse.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    /// Bumped on every change; views read it to refresh their fetches.
    private(set) var version = 0

    @ObservationIgnored private var context: ModelContext { ThreadStore.shared.container.mainContext }

    /// Paging a results page (or reloading it) within this window counts as one search.
    private static let searchMergeWindow: TimeInterval = 30 * 60

    private init() {
        repairPlusEncodedQueries()
        Task { await fillMissingAddresses() }
    }

    /// Visits recorded before `VisitRecord.address` existed get one, a batch at a
    /// time so a big history doesn't hold up the window. Until then they're found by
    /// title only. Once they all have one, this is a single empty fetch per launch.
    private func fillMissingAddresses() async {
        var filledAny = false
        while true {
            var descriptor = FetchDescriptor<VisitRecord>(predicate: #Predicate { $0.address == "" })
            descriptor.fetchLimit = 2_000
            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else { break }
            var filled = 0
            for visit in batch {
                let address = VisitRecord.address(of: visit.url)
                if !address.isEmpty { visit.address = address; filled += 1 }
            }
            try? context.save()
            // Only addresses that really are empty are left: done.
            if filled == 0 { break }
            filledAny = true
            await Task.yield()
        }
        if filledAny { version += 1 }
    }

    /// Early builds stored "+"-encoded spaces literally ("kyoto+to+tokyo"). Once per
    /// install, re-derive those queries from their results URLs.
    private func repairPlusEncodedQueries() {
        let key = "history.repairedPlusQueries"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let broken = (try? context.fetch(FetchDescriptor<SearchRecord>(predicate: #Predicate { $0.query.contains("+") }))) ?? []
        guard !broken.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        var seen = Set(((try? context.fetch(FetchDescriptor<SearchRecord>())) ?? []).map { Self.key($0.query, $0.engine, $0.searchedAt) })
        for search in broken {
            guard let match = SearchQuery.match(search.url), match.query != search.query else { continue }
            // The repaired search may now duplicate the browser's own record of it.
            if seen.insert(Self.key(match.query, search.engine, search.searchedAt)).inserted {
                search.query = match.query
            } else {
                context.delete(search)
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: Recording

    func recordVisit(url: URL, title: String) {
        var descriptor = FetchDescriptor<VisitRecord>(predicate: #Predicate { $0.url == url })
        descriptor.fetchLimit = 1
        if let visit = try? context.fetch(descriptor).first {
            visit.title = title.isEmpty ? visit.title : title
            visit.visitedAt = .now
            visit.visitCount += 1
        } else {
            context.insert(VisitRecord(url: url, title: title))
        }
        let settings = BrowsingSettings.shared
        let custom = settings.searchEngine == .custom && SearchEngine.isValidTemplate(settings.customSearchTemplate) ? settings.customSearchTemplate : nil
        if let match = SearchQuery.match(url, customTemplate: custom) {
            recordSearch(match, url: url)
        }
        save()
    }

    private func recordSearch(_ match: SearchQuery.Match, url: URL, at date: Date = .now) {
        let query = match.query
        let since = date.addingTimeInterval(-Self.searchMergeWindow)
        var descriptor = FetchDescriptor<SearchRecord>(
            predicate: #Predicate { $0.query == query && $0.searchedAt > since },
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let recent = try? context.fetch(descriptor).first, recent.engine == match.engine {
            recent.searchedAt = date
        } else {
            context.insert(SearchRecord(query: query, engine: match.engine, url: url, searchedAt: date))
        }
    }

    // MARK: Reading

    func recentVisits(limit: Int = 50) -> [VisitRecord] {
        var descriptor = FetchDescriptor<VisitRecord>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Newest first; `text` matches title or address, across the whole history.
    func visits(matching text: String, limit: Int) -> [VisitRecord] {
        let text = text.trimmingCharacters(in: .whitespaces)
        var descriptor = FetchDescriptor<VisitRecord>(sortBy: [SortDescriptor(\.visitedAt, order: .reverse)])
        if !text.isEmpty {
            let needle = text.lowercased()
            descriptor.predicate = #Predicate {
                $0.title.localizedStandardContains(text) || $0.address.contains(needle)
            }
        }
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func searches(matching text: String, limit: Int) -> [SearchRecord] {
        let text = text.trimmingCharacters(in: .whitespaces)
        var descriptor = text.isEmpty
            ? FetchDescriptor<SearchRecord>(sortBy: [SortDescriptor(\.searchedAt, order: .reverse)])
            : FetchDescriptor<SearchRecord>(
                predicate: #Predicate { $0.query.localizedStandardContains(text) },
                sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
            )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Counted once per change, not on every redraw of History.
    var visitCount: Int {
        _ = version
        if let counts, counts.version == version { return counts.visits }
        return recount().visits
    }

    var searchCount: Int {
        _ = version
        if let counts, counts.version == version { return counts.searches }
        return recount().searches
    }

    @ObservationIgnored private var counts: (version: Int, visits: Int, searches: Int)?

    private func recount() -> (version: Int, visits: Int, searches: Int) {
        let fresh = (
            version: version,
            visits: (try? context.fetchCount(FetchDescriptor<VisitRecord>())) ?? 0,
            searches: (try? context.fetchCount(FetchDescriptor<SearchRecord>())) ?? 0
        )
        counts = fresh
        return fresh
    }

    // MARK: Removing

    func delete(_ visit: VisitRecord) {
        context.delete(visit)
        save()
    }

    func delete(_ search: SearchRecord) {
        context.delete(search)
        save()
    }

    /// Forgets visited pages (and the searches made on them), keeping threads and pins.
    func clearAll() {
        try? context.delete(model: VisitRecord.self)
        try? context.delete(model: SearchRecord.self)
        save()
    }

    func clearSearches() {
        try? context.delete(model: SearchRecord.self)
        save()
    }

    // MARK: Importing

    struct ImportedVisit: Sendable {
        let url: URL
        let title: String
        let lastVisit: Date
        let visitCount: Int
    }

    struct ImportedSearch: Sendable {
        let query: String
        let engine: String
        let url: URL
        let date: Date
    }

    /// Merges another browser's history: a page Wake already knows keeps the newer
    /// visit and the higher count. Yields between batches so the window stays responsive.
    /// Returns how many pages were new.
    func importVisits(_ visits: [ImportedVisit], source: String) async -> Int {
        var existing: [URL: VisitRecord] = [:]
        for visit in (try? context.fetch(FetchDescriptor<VisitRecord>())) ?? [] { existing[visit.url] = visit }
        var added = 0
        for (index, visit) in visits.enumerated() {
            if let known = existing[visit.url] {
                if visit.lastVisit > known.visitedAt {
                    known.visitedAt = visit.lastVisit
                    if known.title.isEmpty { known.title = visit.title }
                }
                known.visitCount = max(known.visitCount, visit.visitCount)
            } else {
                let record = VisitRecord(url: visit.url, title: visit.title, visitedAt: visit.lastVisit,
                                         visitCount: max(1, visit.visitCount), source: source)
                context.insert(record)
                existing[visit.url] = record
                added += 1
            }
            if index % 1_000 == 999 {
                try? context.save()
                await Task.yield()
            }
        }
        save()
        return added
    }

    /// Adds searches not already recorded (same words, engine and minute).
    func importSearches(_ searches: [ImportedSearch], source: String) async -> Int {
        var seen = Set<String>()
        for search in (try? context.fetch(FetchDescriptor<SearchRecord>())) ?? [] {
            seen.insert(Self.key(search.query, search.engine, search.searchedAt))
        }
        var added = 0
        for (index, search) in searches.enumerated() {
            guard seen.insert(Self.key(search.query, search.engine, search.date)).inserted else { continue }
            context.insert(SearchRecord(query: search.query, engine: search.engine, url: search.url, searchedAt: search.date, source: source))
            added += 1
            if index % 1_000 == 999 {
                try? context.save()
                await Task.yield()
            }
        }
        save()
        return added
    }

    private static func key(_ query: String, _ engine: String, _ date: Date) -> String {
        "\(query.lowercased())|\(engine)|\(Int(date.timeIntervalSince1970 / 60))"
    }

    private func save() {
        try? context.save()
        version += 1
    }
}
