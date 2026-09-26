import AppKit
import Foundation
import SwiftData

/// SwiftData persistence for threads and visits, shared by every window.
/// Also tracks which window shows which thread, so one thread is never live in
/// two windows (their saves would overwrite each other).
@MainActor
final class ThreadStore {
    static let shared = ThreadStore()

    let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var owners: [UUID: WeakOwner] = [:]
    private var pendingSaves: [UUID: Task<Void, Never>] = [:]
    private var pendingThreads: [UUID: WeakThread] = [:]
    private var terminationObserver: NSObjectProtocol?

    private init() {
        let models: [any PersistentModel.Type] = [ThreadRecord.self, ColumnRecord.self, VisitRecord.self, SearchRecord.self, PinnedAppRecord.self, MomentRecord.self]
        let schema = Schema(models)
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // A store we can't open (e.g. an incompatible schema during development)
            // shouldn't stop the browser from starting; this session just won't persist.
            NSLog("Wake: couldn't open the thread store (\(error)); using an in-memory store.")
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ThreadStore.shared.flushPendingSaves() }
        }
    }

    /// Writes debounced saves immediately (the app is quitting).
    func flushPendingSaves() {
        let threads = pendingThreads.values.compactMap(\.value)
        threads.forEach(save)
    }

    // MARK: Threads

    func unresolvedThreads() -> [ThreadRecord] {
        let descriptor = FetchDescriptor<ThreadRecord>(
            predicate: #Predicate { !$0.isResolved },
            sortBy: [SortDescriptor(\.lastActiveAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Resolved threads, most recently resolved first (shown in Moments).
    func resolvedThreads() -> [ThreadRecord] {
        let descriptor = FetchDescriptor<ThreadRecord>(
            predicate: #Predicate { $0.isResolved },
            sortBy: [SortDescriptor(\.lastActiveAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Brings a resolved thread back into the Deck.
    func unresolve(threadID: UUID) {
        guard let record = record(for: threadID) else { return }
        record.isResolved = false
        record.lastActiveAt = .now
        try? context.save()
    }

    func record(for id: UUID) -> ThreadRecord? {
        var descriptor = FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Coalesces bursts of changes (a page load fires several) into one write.
    func scheduleSave(_ thread: BrowserThread) {
        pendingThreads[thread.id] = WeakThread(value: thread)
        pendingSaves[thread.id]?.cancel()
        pendingSaves[thread.id] = Task { [weak thread] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let thread else { return }
            self.save(thread)
        }
    }

    func save(_ thread: BrowserThread) {
        pendingSaves[thread.id]?.cancel()
        pendingSaves[thread.id] = nil
        pendingThreads[thread.id] = nil
        let (columns, focusedIndex) = thread.snapshot
        let existing = record(for: thread.id)
        // Empty threads aren't worth keeping.
        guard !columns.isEmpty || thread.customTitle != nil else {
            if let existing, !existing.isResolved { context.delete(existing) }
            try? context.save()
            return
        }
        let record = existing ?? {
            let record = ThreadRecord(id: thread.id, title: thread.title, createdAt: thread.createdAt)
            context.insert(record)
            return record
        }()
        record.customTitle = thread.customTitle
        record.developerMode = thread.developerMode
        record.title = thread.title
        record.lastActiveAt = thread.lastActiveAt
        record.focusedIndex = focusedIndex
        record.columns.forEach(context.delete)
        record.columns = columns.enumerated().map { index, column in
            ColumnRecord(order: index, url: column.url, title: column.title, widthFraction: column.widthFraction.map(Double.init))
        }
        try? context.save()
    }

    func resolve(_ thread: BrowserThread, outcome: String) {
        save(thread)
        guard let record = record(for: thread.id) else { return }
        record.isResolved = true
        record.outcome = outcome
        record.resolvedAt = .now
        try? context.save()
    }

    /// Marks a thread as just used (reviving it from below the waterline).
    func touch(threadID: UUID) {
        record(for: threadID)?.lastActiveAt = .now
        try? context.save()
    }

    func delete(threadID: UUID) {
        pendingSaves[threadID]?.cancel()
        pendingSaves[threadID] = nil
        if let record = record(for: threadID) { context.delete(record) }
        try? context.save()
    }

    // MARK: Which window shows which thread

    func claim(_ threadID: UUID, for owner: BrowserModel) {
        owners[threadID] = WeakOwner(value: owner)
    }

    func release(_ threadID: UUID) {
        owners[threadID] = nil
    }

    func owner(of threadID: UUID) -> BrowserModel? {
        owners[threadID]?.value
    }

    private struct WeakOwner {
        weak var value: BrowserModel?
    }

    private struct WeakThread {
        weak var value: BrowserThread?
    }

    // MARK: Pinned apps

    func pinnedApps() -> [PinnedAppRecord] {
        let descriptor = FetchDescriptor<PinnedAppRecord>(sortBy: [SortDescriptor(\.order)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func pinApp(url: URL, title: String) -> PinnedAppRecord {
        let record = PinnedAppRecord(url: url, title: title, order: (pinnedApps().last?.order ?? -1) + 1)
        context.insert(record)
        try? context.save()
        return record
    }

    func unpinApp(id: UUID) {
        pinnedApps().filter { $0.id == id }.forEach(context.delete)
        try? context.save()
    }
}
