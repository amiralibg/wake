import Foundation
import Observation
import SwiftData

/// Moments on disk (in the same SwiftData store as threads), shared by every window.
@MainActor
@Observable
final class MomentStore {
    static let shared = MomentStore()

    /// Bumps on every change, so views re-read.
    private(set) var version = 0

    @ObservationIgnored private var context: ModelContext { ThreadStore.shared.container.mainContext }

    private init() {}

    /// Newest first. Archived ones only when asked for.
    func moments(includingArchived: Bool = false) -> [MomentRecord] {
        _ = version
        let descriptor = FetchDescriptor<MomentRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? []
        return includingArchived ? all : all.filter { !$0.isArchived }
    }

    func moment(id: UUID) -> MomentRecord? {
        var descriptor = FetchDescriptor<MomentRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func save(url: URL, state: MomentPageState, threadID: UUID?, resurface: ResurfaceChoice) -> MomentRecord {
        let moment = MomentRecord(url: url, title: state.title)
        moment.selectedText = state.selection
        moment.selectionPrefix = state.selectionPrefix
        moment.scrollY = state.scrollY
        moment.scrollFraction = state.scrollFraction
        moment.contentText = state.text
        moment.contentHash = MomentDiff.hash(state.text)
        moment.resurfaceAt = resurface.date(from: .now)
        moment.threadID = threadID
        moment.lastCheckedAt = .now
        context.insert(moment)
        commit()
        return moment
    }

    func update(_ moment: MomentRecord, _ change: (MomentRecord) -> Void) {
        change(moment)
        commit()
    }

    /// Opened: it's fresh again, and what's on screen now becomes the new baseline.
    func markOpened(_ moment: MomentRecord) {
        moment.lastOpenedAt = .now
        moment.openCount += 1
        commit()
    }

    func rebaseline(_ moment: MomentRecord, text: String) {
        guard !text.isEmpty else { return }
        moment.contentText = String(text.prefix(MomentDiff.maxTextLength))
        moment.contentHash = MomentDiff.hash(text)
        moment.changedAt = nil
        moment.changeSummary = nil
        moment.lastCheckedAt = .now
        commit()
    }

    func delete(_ moment: MomentRecord) {
        ThumbnailStore.moments.remove(moment.id)
        context.delete(moment)
        commit()
    }

    /// Moments nobody opened for `MomentRules.archiveAfter` go to the archive.
    func archiveStale(now: Date = .now) {
        let stale = moments().filter { MomentRules.shouldArchive($0, now: now) }
        guard !stale.isEmpty else { return }
        stale.forEach { $0.isArchived = true }
        commit()
    }

    private func commit() {
        try? context.save()
        version += 1
    }
}
