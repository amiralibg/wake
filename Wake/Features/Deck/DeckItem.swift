import Foundation

enum DeckArrangement: String, CaseIterable, Identifiable {
    case heat, thread, site

    var id: Self { self }

    var label: String {
        switch self {
        case .heat: "By heat"
        case .thread: "By thread"
        case .site: "By site"
        }
    }
}

/// One card in the Deck: a thread (or, arranged by site, all pages from one host).
struct DeckItem: Identifiable, Equatable {
    enum Chip: Equatable {
        case playing
        case unsaved
        /// A live chip from the thread's pages (media time, price, CI, unread…).
        case live(LiveChip)
    }

    let id: String
    /// The thread a click on this card switches to.
    let threadID: UUID
    let title: String
    let host: String
    let pageCount: Int
    let lastActiveAt: Date
    let isActive: Bool
    let chip: Chip?
    enum Afloat: Equatable { case playing, unsaved }

    /// Why the card never sinks while "keep afloat" is on: something's playing,
    /// or a form holds unsaved input.
    var afloat: Afloat?
    /// 1 = just touched, falling towards 0 as the card goes untouched.
    let heat: Double
    let isSunk: Bool

    var footnote: String {
        if isActive { return pageCount == 1 ? "You're here" : "\(pageCount) pages · you're here" }
        if afloat == .unsaved { return "Won't sink while unsaved" }
        if afloat == .playing { return "Playing · never sinks" }
        let age = lastActiveAt.formatted(.relative(presentation: .named))
        return pageCount > 1 ? "\(pageCount) pages · \(age)" : age
    }
}

/// Builds Deck items from saved threads plus live state (playing, unsaved).
struct DeckBuilder {
    struct Live {
        let pageCount: Int
        let isPlaying: Bool
        let hasUnsaved: Bool
        let title: String
        let host: String
        /// The most important live chip among the thread's pages.
        var chip: LiveChip?

        var afloat: DeckItem.Afloat? {
            hasUnsaved ? .unsaved : (isPlaying ? .playing : nil)
        }

        /// One chip per card. Errors (HTTP, CI, console) and price moves come first,
        /// then unsaved input (it keeps the card afloat), then the rest.
        var deckChip: DeckItem.Chip? {
            if let chip, [.status, .ci, .errors, .price].contains(chip.kind) { return .live(chip) }
            if hasUnsaved { return .unsaved }
            if let chip { return .live(chip) }
            return isPlaying ? .playing : nil
        }
    }

    let records: [ThreadRecord]
    let live: [UUID: Live]
    let activeID: UUID
    let sinkAfter: TimeInterval?
    let keepActiveAfloat: Bool
    let now: Date

    func items(_ arrangement: DeckArrangement) -> [DeckItem] {
        switch arrangement {
        case .heat, .thread: threadItems(heatDrivesHeight: arrangement == .heat)
        case .site: siteItems()
        }
    }

    private func threadItems(heatDrivesHeight: Bool) -> [DeckItem] {
        var items = records.map { record -> DeckItem in
            let live = live[record.id]
            return item(
                id: record.id.uuidString,
                threadID: record.id,
                title: live?.title ?? record.customTitle ?? record.title,
                host: live?.host ?? record.orderedColumns.first.flatMap { Self.host(of: $0.url) } ?? "",
                pageCount: live?.pageCount ?? record.columns.count,
                lastActiveAt: record.lastActiveAt,
                chip: live?.deckChip,
                afloat: live?.afloat,
                flatHeat: !heatDrivesHeight
            )
        }
        // The active thread may be brand new and not saved yet.
        if !records.contains(where: { $0.id == activeID }), let live = live[activeID] {
            items.append(item(id: activeID.uuidString, threadID: activeID, title: live.title, host: live.host,
                              pageCount: live.pageCount, lastActiveAt: now, chip: live.deckChip,
                              afloat: live.afloat, flatHeat: false))
        }
        return items
    }

    /// Every saved page grouped by host; a card opens the most recent thread with it.
    private func siteItems() -> [DeckItem] {
        var groups: [String: (count: Int, record: ThreadRecord)] = [:]
        for record in records {
            for column in record.columns {
                guard let host = Self.host(of: column.url) else { continue }
                let existing = groups[host]
                let newest = existing.map { $0.record.lastActiveAt > record.lastActiveAt ? $0.record : record } ?? record
                groups[host] = ((existing?.count ?? 0) + 1, newest)
            }
        }
        return groups.map { host, group in
            item(id: "site:\(host)", threadID: group.record.id, title: host, host: host,
                 pageCount: group.count, lastActiveAt: group.record.lastActiveAt, chip: nil, afloat: nil, flatHeat: false)
        }
    }

    private func item(
        id: String, threadID: UUID, title: String, host: String, pageCount: Int,
        lastActiveAt: Date, chip: DeckItem.Chip?, afloat: DeckItem.Afloat?, flatHeat: Bool
    ) -> DeckItem {
        let isActive = threadID == activeID
        let age = max(0, now.timeIntervalSince(lastActiveAt))
        // Half-life of a third of the sink delay: a card is at 1/8 height when it sinks.
        let halfLife = (sinkAfter ?? 9 * 86_400) / 3
        let heat = isActive ? 1 : (flatHeat ? 0.6 : pow(0.5, age / halfLife))
        let isSunk = !isActive && !(keepActiveAfloat && afloat != nil) && sinkAfter.map { age > $0 } == true
        return DeckItem(id: id, threadID: threadID, title: title, host: host, pageCount: pageCount,
                        lastActiveAt: lastActiveAt, isActive: isActive, chip: chip, afloat: afloat,
                        heat: heat, isSunk: isSunk)
    }

    static func host(of url: URL) -> String? {
        guard let host = url.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
