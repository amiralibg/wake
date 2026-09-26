import AppKit
import Foundation
import Observation
import SwiftUI

/// Per-window browser state: the active thread and its trail, the palette,
/// settings, and Zen mode. Threads are shared across windows through ThreadStore.
@MainActor
@Observable
final class BrowserModel {
    private(set) var thread: BrowserThread
    let palette = PaletteModel()
    let apps = PinnedAppsModel()
    /// In Zen, whether the app capsule has slid in from the left edge.
    var isCapsuleRevealed = false
    @ObservationIgnored private var capsuleConcealTask: Task<Void, Never>?
    private(set) var isPaletteOpen = false
    private(set) var isSettingsOpen = false
    var settingsSection: SettingsSection = .appearance
    var isZen: Bool = UserDefaults.standard.bool(forKey: "window.zen") {
        didSet {
            UserDefaults.standard.set(isZen, forKey: "window.zen")
            isChromeRevealed = false
            // A reveal belongs to the mode it happened in; carried over, the capsule
            // would sit in Zen uninvited (or slide down into place when leaving it).
            concealCapsule(animated: false)
        }
    }
    /// In Zen mode, whether the toolbar is currently slid in.
    var isChromeRevealed = false
    /// Bumps whenever thread records change, so lists re-read the store.
    private(set) var threadListVersion = 0

    // Deck
    private(set) var isDeckOpen = false
    var deckArrangement: DeckArrangement = .heat
    /// The Deck stays out of the way until the pointer reaches the bottom edge,
    /// then peeks up as an island.
    private(set) var isDeckPeeking = false

    // Moments
    var isMomentsOpen = false
    var momentsShelf: MomentShelf = .everything
    var momentsQuery = ""
    var momentsLayout: MomentsLayout = .grid
    /// The moment just saved, while its note island is up.
    var savedMoment: MomentRecord?
    /// The "Import from Another Browser" sheet.
    var isImportingBrowserData = false

    @ObservationIgnored private let store = ThreadStore.shared
    @ObservationIgnored private let thumbnails = ThumbnailStore.shared
    /// Threads switched away from stay alive (media keeps playing) up to this many.
    @ObservationIgnored private var backgroundThreads: [BrowserThread] = []
    @ObservationIgnored private let maxBackgroundThreads = 4
    /// A thread left alone this long in the background is discarded: its web views go,
    /// its columns and scroll positions stay, and it reloads when you come back.
    /// Measured: ~280 MB for a thread of four ordinary pages.
    private static let discardAfter: Duration = .seconds(10 * 60)
    @ObservationIgnored private var discardTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var peekHideTask: Task<Void, Never>?
    /// The window this model drives, so menu commands can find it without relying
    /// on SwiftUI focus (which can be missing while a web view is first responder).
    @ObservationIgnored weak var window: NSWindow?

    @ObservationIgnored private static var all: [WeakModel] = []
    private struct WeakModel { weak var value: BrowserModel? }

    /// The browser in the key window (or main window, while a sheet or panel is key).
    static var active: BrowserModel? {
        all.removeAll { $0.value == nil }
        let models = all.compactMap(\.value)
        if let key = models.first(where: { $0.window != nil && $0.window === NSApp.keyWindow }) { return key }
        if let main = models.first(where: { $0.window != nil && $0.window === NSApp.mainWindow }) { return main }
        // The app isn't active (a menu driven from outside): the front-most browser window.
        for window in NSApp.orderedWindows {
            if let model = models.first(where: { $0.window === window }) { return model }
        }
        return nil
    }

    init() {
        let store = ThreadStore.shared
        let resumable = BrowsingSettings.shared.restoresLastThread
            ? store.unresolvedThreads().first { store.owner(of: $0.id) == nil }
            : nil
        thread = resumable.map(BrowserThread.init(record:)) ?? BrowserThread()
        palette.recents = { [weak self] in self?.recents ?? [] }
        activate(thread)
        apps.configurePage = { [weak self] page in
            // A pinned app is a place you return to; what you open from it joins the trail.
            page.onOpenLink = { url, background in self?.openFromApp(url, background: background) }
            page.onOpenPopup = { configuration in
                guard let self else { return nil }
                self.apps.dismiss()
                return self.trail.openPopup(configuration: configuration, from: nil)
            }
        }
        apps.load()
        Self.all.append(WeakModel(value: self))
    }

    var trail: TrailModel { thread.trail }
    var page: BrowserPage? { trail.focused }

    var recents: [RecentPage] {
        HistoryStore.shared.recentVisits().map { RecentPage(url: $0.url, title: $0.title, visitedAt: $0.visitedAt) }
    }

    /// ⌘W closes the innermost thing: an overlay, the showing app, then the focused
    /// column. Only a window with nothing left in it closes.
    func closeCommand() {
        if savedMoment != nil {
            finishSavingMoment()
        } else if isMomentsOpen {
            hideMoments()
        } else if isSettingsOpen {
            hideSettings()
        } else if isPaletteOpen || isDeckOpen {
            hidePalette()
        } else if apps.active != nil {
            withAnimation(.chrome) { apps.dismiss() }
            refocusPage()
        } else if page != nil {
            trail.closeFocused()
        } else {
            window?.performClose(nil)
        }
    }

    func copyPageURL() {
        guard let url = webPage?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// Called when the window closes: stop claiming threads and save them.
    func windowWillClose() {
        for live in [thread] + backgroundThreads {
            store.save(live)
            store.release(live.id)
        }
    }

    // MARK: Palette and Deck

    /// ⌘K, ⌘T and + open the Deck with its search field; ⌘L and the address bar
    /// open the plain palette, which loads into the current column.
    func showPalette(target: PaletteModel.Target = .newColumn) {
        if target == .newColumn || trail.columns.isEmpty {
            openDeck()
        } else {
            isSettingsOpen = false
            isDeckOpen = false
            isMomentsOpen = false
            palette.reset()
            palette.target = .currentColumn
            palette.showsRecentsWhenEmpty = true
            isPaletteOpen = true
            if isZen { isChromeRevealed = false }
        }
    }

    func hidePalette() {
        isPaletteOpen = false
        isDeckOpen = false
        refocusPage()
    }

    func togglePalette() {
        isPaletteOpen || isDeckOpen ? hidePalette() : showPalette()
    }

    func openDeck() {
        apps.dismiss()
        isMomentsOpen = false
        captureThumbnail()
        isSettingsOpen = false
        isPaletteOpen = false
        palette.reset()
        palette.target = .newColumn
        palette.showsRecentsWhenEmpty = false
        isDeckPeeking = false
        isDeckOpen = true
        if isZen { isChromeRevealed = false }
    }

    func choose(_ item: PaletteItem) {
        switch item {
        case .open(let url): open(url)
        case .result(let result): open(result.url)
        case .recent(let recent): open(recent.url)
        // With palette results, a suggestion refines them in place; without, it searches.
        case .suggestion(let text):
            if SearchKeyStore.hasBraveAPIKey { palette.query = text } else { open(BrowsingSettings.shared.searchURL(for: text)) }
        case .searchOnWeb(let query): open(BrowsingSettings.shared.searchURL(for: query))
        }
    }

    private func open(_ url: URL) {
        let target = palette.target
        hidePalette()
        if target == .currentColumn, let page {
            page.load(url)
        } else {
            trail.open(url)
        }
    }

    func refocusPage() {
        if let page { page.webView.window?.makeFirstResponder(page.webView) }
    }

    /// Cards for the Deck, from saved threads plus what live pages report.
    func deckItems(settings: DeckSettings, now: Date) -> [DeckItem] {
        _ = threadListVersion
        var live: [UUID: DeckBuilder.Live] = [:]
        for thread in [thread] + backgroundThreads {
            let pages = thread.trail.columns
            live[thread.id] = DeckBuilder.Live(
                pageCount: thread.pageCount,
                isPlaying: pages.contains(where: \.isPlayingMedia),
                hasUnsaved: pages.contains(where: \.hasUnsavedInput),
                title: thread.title,
                host: pages.first?.host ?? "",
                chip: LiveChips.top(of: pages.filter { !$0.isDevTools })
            )
        }
        let builder = DeckBuilder(
            records: store.unresolvedThreads(),
            live: live,
            activeID: thread.id,
            sinkAfter: settings.sinkAfter.interval,
            keepActiveAfloat: settings.keepActiveAfloat,
            now: now
        )
        return builder.items(deckArrangement)
    }

    func selectDeckItem(_ item: DeckItem) {
        isDeckPeeking = false
        if item.threadID == thread.id {
            isDeckOpen ? hidePalette() : openDeck()
            return
        }
        hidePalette()
        switchToThread(id: item.threadID)
    }

    /// Dragging a sunk card up: it's warm again.
    func revive(threadID: UUID) {
        store.touch(threadID: threadID)
        threadListVersion += 1
    }

    /// "Let them go": closes every thread below the waterline.
    func letGo(threadIDs: [UUID]) {
        for id in threadIDs where id != thread.id && !backgroundThreads.contains(where: { $0.id == id }) {
            guard store.owner(of: id) == nil else { continue }
            store.delete(threadID: id)
            thumbnails.remove(id)
        }
        threadListVersion += 1
    }

    /// In Zen, the pointer reached the top edge: float the toolbar in.
    func revealZenChrome() {
        guard isZen, !isChromeRevealed else { return }
        withAnimation(.chrome) { isChromeRevealed = true }
    }

    /// The pointer reached the bottom edge: bring the Deck island up.
    func peekDeck() {
        peekHideTask?.cancel()
        guard !isDeckOpen, !isSettingsOpen, !isPaletteOpen, !isDeckPeeking else { return }
        captureThumbnail()
        withAnimation(.deck) { isDeckPeeking = true }
        // If the pointer never moves onto the island, it goes away on its own.
        endDeckPeek(after: .seconds(1.2))
    }

    /// The pointer is on the island: keep it up.
    func holdDeckPeek() {
        peekHideTask?.cancel()
    }

    /// The pointer left the island: let it sink back after a moment.
    func endDeckPeek(after delay: Duration = .milliseconds(450)) {
        peekHideTask?.cancel()
        peekHideTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            withAnimation(.deck) { isDeckPeeking = false }
        }
    }

    /// Scrolling a page means reading: put the island away.
    func noteReadingScroll() {
        if isDeckPeeking { endDeckPeek(after: .zero) }
    }

    private func captureThumbnail() {
        if let page { thumbnails.capture(page, for: thread.id) }
    }

    // MARK: Settings

    func showSettings(_ section: SettingsSection? = nil) {
        isMomentsOpen = false
        isPaletteOpen = false
        isDeckOpen = false
        apps.dismiss()
        if let section { settingsSection = section }
        isSettingsOpen = true
    }

    func hideSettings() {
        isSettingsOpen = false
        refocusPage()
    }

    /// Esc: close whichever overlay is up.
    func dismissOverlays() {
        if let page = webPage, page.isPickingPopOut {
            page.setPickingPopOut(false)
        } else if savedMoment != nil {
            finishSavingMoment()
        } else if isMomentsOpen {
            hideMoments()
        } else if isSettingsOpen {
            hideSettings()
        } else if isPaletteOpen || isDeckOpen {
            hidePalette()
        } else if apps.active != nil {
            withAnimation(.chrome) { apps.dismiss() }
            refocusPage()
        }
    }

    var hasOverlay: Bool {
        isSettingsOpen || isPaletteOpen || isDeckOpen || apps.active != nil || isMomentsOpen || savedMoment != nil
            || webPage?.isPickingPopOut == true
    }

    // MARK: Pinned apps

    var showsAppCapsule: Bool {
        !capsuleFloats || isCapsuleRevealed
    }

    /// In Zen, or when set to hide at the edge, the capsule floats over the pages
    /// on demand instead of keeping a strip of its own.
    var capsuleFloats: Bool {
        isZen || BrowsingSettings.shared.capsuleHidesAtEdge
    }


    var devServers: [DevServer] {
        DeveloperSettings.shared.scansPorts ? DevServerScanner.shared.servers : []
    }

    func toggleApp(_ app: PinnedApp) {
        isPaletteOpen = false
        isDeckOpen = false
        isSettingsOpen = false
        withAnimation(.chrome) { apps.toggle(app) }
        if let active = apps.active {
            active.page.webView.window?.makeFirstResponder(active.page.webView)
        } else {
            refocusPage()
        }
    }

    func toggleApp(index: Int) {
        guard apps.apps.indices.contains(index) else { return }
        toggleApp(apps.apps[index])
    }

    func pin(_ page: BrowserPage) {
        guard let url = page.url else { return }
        withAnimation(.chrome) { apps.pin(url: url, title: page.displayTitle) }
    }

    func unpin(_ app: PinnedApp) {
        withAnimation(.chrome) { apps.unpin(app) }
    }

    /// The pointer reached the left edge: slide the floating app capsule in. It slides
    /// back out once the pointer leaves it, or if the pointer never goes onto it.
    func revealCapsule() {
        guard capsuleFloats, !isCapsuleRevealed else { return }
        withAnimation(.chrome) { isCapsuleRevealed = true }
        scheduleCapsuleConceal()
    }

    func concealCapsule(animated: Bool = true) {
        capsuleConcealTask?.cancel()
        guard isCapsuleRevealed else { return }
        if animated {
            withAnimation(.chrome) { isCapsuleRevealed = false }
        } else {
            isCapsuleRevealed = false
        }
    }

    /// The pointer is on the capsule (true) or left it (false).
    func capsuleHovered(_ inside: Bool) {
        if inside { capsuleConcealTask?.cancel() } else { concealCapsule() }
    }

    private func scheduleCapsuleConceal() {
        capsuleConcealTask?.cancel()
        capsuleConcealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.concealCapsule()
        }
    }

    // MARK: Developer

    /// The web page developer actions apply to (not a DevTools column).
    var webPage: BrowserPage? {
        page.flatMap { $0.isDevTools ? $0.inspectedPage : $0 }
    }

    func toggleDevTools() {
        guard let webPage else { return }
        trail.toggleDevTools(for: webPage)
    }

    /// Opens DevTools beside the page (if closed) on `tab`.
    func showDevTools(_ tab: DevToolsSession.Tab) {
        guard let webPage else { return }
        webPage.inspector.tab = tab
        if trail.devTools(for: webPage) == nil { trail.toggleDevTools(for: webPage) }
    }

    /// DevTools on Elements with the in-page picker running.
    func inspectElement() {
        guard let webPage else { return }
        showDevTools(.elements)
        webPage.inspector.setPicking(true)
    }

    func showWebInspector() {
        guard let webPage else { return }
        WebInspector.toggle(for: webPage.webView)
    }

    /// Flips developer mode for the whole thread and reloads, so the hooks see the
    /// page from its first line.
    func toggleDeveloperMode() {
        thread.developerMode = !(webPage?.isDeveloperMode ?? false)
        store.scheduleSave(thread)
        webPage?.reload()
    }

    /// Back to automatic: on for localhost, off elsewhere.
    func resetDeveloperMode() {
        thread.developerMode = nil
        store.scheduleSave(thread)
        webPage?.reload()
    }

    func openResponsivePreview(_ device: DevicePreset) {
        guard let webPage = webPage.flatMap({ trail.previewSource(of: $0) ?? $0 }) else { return }
        trail.openResponsivePreview(of: webPage, device: device)
    }

    /// Pop Out: pick an element on the page to float it in its own live panel.
    func togglePopOutPicker() {
        guard let webPage, webPage.url != nil else { return }
        if webPage.isInspectingComponents { webPage.setInspectingComponents(false) }
        webPage.setPickingPopOut(!webPage.isPickingPopOut)
    }

    func toggleComponentInspector() {
        guard let webPage else { return }
        webPage.setInspectingComponents(!webPage.isInspectingComponents)
    }

    /// Same path and query on another environment of the page's project.
    func switchEnvironment(to environment: DevEnvironment) {
        guard let page = webPage, let url = page.url,
              let target = DevProjectStore.shared.project(for: url)?.url(url, in: environment) else { return }
        page.load(target)
    }

    /// Focuses a column already showing the server, or opens one.
    func openDevServer(_ server: DevServer) {
        if let existing = trail.columns.first(where: { BrowserPage.isLocal($0.url) && $0.url?.port == server.port }) {
            trail.focus(id: existing.id)
        } else {
            trail.open(server.url)
        }
    }

    private func openFromApp(_ url: URL, background: Bool) {
        if !background { withAnimation(.chrome) { apps.dismiss() } }
        trail.open(url, focus: !background)
    }

    // MARK: Threads

    var otherThreads: [ThreadRecord] {
        _ = threadListVersion
        return store.unresolvedThreads().filter { $0.id != thread.id }
    }

    func newThread() {
        switchTo(BrowserThread())
        showPalette()
    }

    /// Switches to a saved thread. If another window already shows it, that window
    /// comes forward instead, so one thread is never live twice.
    func switchToThread(id: UUID) {
        guard id != thread.id else { return }
        if let owner = store.owner(of: id), owner !== self {
            owner.trail.focused?.webView.window?.makeKeyAndOrderFront(nil)
            return
        }
        if let alive = backgroundThreads.first(where: { $0.id == id }) {
            switchTo(alive)
            return
        }
        guard let record = store.record(for: id) else { return }
        switchTo(BrowserThread(record: record))
    }

    func renameThread(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        thread.customTitle = trimmed.isEmpty ? nil : trimmed
        store.scheduleSave(thread)
        threadListVersion += 1
    }

    /// Records a one-line outcome, closes the thread's pages and moves on to the
    /// next thread. Resolved threads show up in Moments.
    func resolveThread(outcome: String) {
        store.resolve(thread, outcome: outcome.trimmingCharacters(in: .whitespaces))
        let resolved = thread
        let next = backgroundThreads.first
            ?? store.unresolvedThreads().first { $0.id != resolved.id && store.owner(of: $0.id) == nil }.map(BrowserThread.init(record:))
            ?? BrowserThread()
        switchTo(next, saveCurrent: false, keepAlive: false)
        if trail.columns.isEmpty { showPalette() }
    }

    /// Reopens a resolved thread from Moments, pages and all.
    func reopenResolvedThread(id: UUID) {
        store.unresolve(threadID: id)
        threadListVersion += 1
        switchToThread(id: id)
    }

    func deleteThread(id: UUID) {
        guard id != thread.id else { return }
        // A thread you've switched away from is still loaded (and claimed) here: let
        // it go first, or the delete silently did nothing.
        if let live = backgroundThreads.first(where: { $0.id == id }) {
            backgroundThreads.removeAll { $0 === live }
            discardTasks.removeValue(forKey: id)?.cancel()
            unload(live)
        }
        // Shown in another window: that window owns it.
        guard store.owner(of: id) == nil else { return }
        store.delete(threadID: id)
        thumbnails.remove(id)
        threadListVersion += 1
    }

    private func switchTo(_ next: BrowserThread, saveCurrent: Bool = true, keepAlive: Bool = true) {
        captureThumbnail()
        let previous = thread
        if saveCurrent { store.save(previous) }
        backgroundThreads.removeAll { $0 === next || $0 === previous }
        discardTasks.removeValue(forKey: next.id)?.cancel()
        if keepAlive, previous.isLoaded {
            backgroundThreads.insert(previous, at: 0)
            scheduleDiscard(previous)
        } else {
            unload(previous)
        }
        // Past the limit, unload the least recent loaded thread that isn't playing
        // anything. (Discarded threads hold no web views and don't count.)
        while backgroundThreads.filter(\.isLoaded).count > maxBackgroundThreads,
              let victim = backgroundThreads.last(where: { $0.isLoaded && !$0.trail.columns.contains(where: \.isPlayingMedia) })
                ?? backgroundThreads.last(where: \.isLoaded) {
            backgroundThreads.removeAll { $0 === victim }
            discardTasks.removeValue(forKey: victim.id)?.cancel()
            store.save(victim)
            unload(victim)
        }
        withAnimation(.trail) {
            thread = next
        }
        activate(next)
        threadListVersion += 1
    }

    private func scheduleDiscard(_ thread: BrowserThread) {
        discardTasks[thread.id]?.cancel()
        discardTasks[thread.id] = Task { [weak self, weak thread] in
            try? await Task.sleep(for: Self.discardAfter)
            guard !Task.isCancelled, let self, let thread else { return }
            await self.discard(thread)
        }
    }

    /// Frees a background thread's web views unless it's playing something or has a
    /// form you've typed into; then it's tried again later.
    private func discard(_ thread: BrowserThread) async {
        discardTasks[thread.id] = nil
        guard thread !== self.thread, backgroundThreads.contains(where: { $0 === thread }), thread.isLoaded else { return }
        if thread.trail.columns.contains(where: { $0.isPlayingMedia || $0.hasUnsavedInput }) {
            scheduleDiscard(thread)
            return
        }
        store.save(thread)
        await thread.discard { [weak self, weak thread] in
            guard let self, let thread else { return false }
            return thread !== self.thread
        }
    }

    /// Memory is critically short: discard every background thread that can go.
    static func discardBackgroundThreads() {
        all.removeAll { $0.value == nil }
        for model in all.compactMap(\.value) {
            for thread in model.backgroundThreads where thread.isLoaded {
                Task { await model.discard(thread) }
            }
        }
    }

    private func unload(_ thread: BrowserThread) {
        store.release(thread.id)
        thread.trail.closeAll()
    }

    private func activate(_ thread: BrowserThread) {
        thread.lastActiveAt = .now
        store.claim(thread.id, for: self)
        let trail = thread.trail
        trail.didCreatePage = { [weak self] page in
            page.onDidFinish = { page in self?.remember(page) }
        }
        trail.onChange = { [weak self, weak thread] in
            guard let self, let thread else { return }
            // Pages in a thread you've left keep changing their URL and title (single-
            // page apps do constantly). That's worth saving, but it isn't you using the
            // thread: counted as activity, it made a background thread look like the
            // one to resume at launch, and kept it hot in the Deck.
            if thread === self.thread { thread.lastActiveAt = .now }
            self.store.scheduleSave(thread)
        }
        thread.restoreIfNeeded()
    }

    private func remember(_ page: BrowserPage) {
        if page === self.page { captureThumbnail() }
        if page.isRestoring {
            page.isRestoring = false
            return
        }
        guard let url = page.url, url.scheme?.hasPrefix("http") == true else { return }
        HistoryStore.shared.recordVisit(url: url, title: page.title)
    }
}
