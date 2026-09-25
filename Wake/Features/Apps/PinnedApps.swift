import Foundation
import Observation
import WebKit

/// A pinned web app, live in this window. Its page loads once and never closes.
@MainActor
@Observable
final class PinnedApp: Identifiable {
    let id: UUID
    let url: URL
    let page: BrowserPage

    init(record: PinnedAppRecord) {
        id = record.id
        url = record.url
        page = BrowserPage()
        page.load(record.url)
    }

    var title: String {
        page.title.isEmpty ? (url.host() ?? url.absoluteString) : page.title
    }

    var host: String {
        let host = url.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Unread count from the page title, the convention most web apps follow:
    /// "(3) Inbox – Gmail", "Inbox (12)", "(99+) Chat".
    var badge: Int? {
        Self.badge(in: page.title)
    }

    static func badge(in title: String) -> Int? {
        guard let match = title.firstMatch(of: #/\((\d{1,4})\+?\)/#), let count = Int(match.1), count > 0 else { return nil }
        return count
    }
}

/// The window's pinned apps and which one is showing.
@MainActor
@Observable
final class PinnedAppsModel {
    private(set) var apps: [PinnedApp] = []
    private(set) var activeID: PinnedApp.ID?

    /// Hooks each app page into the browser (links open in the trail, and so on).
    @ObservationIgnored var configurePage: (BrowserPage) -> Void = { _ in }
    @ObservationIgnored private let store = ThreadStore.shared

    var active: PinnedApp? { apps.first { $0.id == activeID } }

    /// Loads every pinned app. Called once per window.
    func load() {
        apps = store.pinnedApps().map(PinnedApp.init(record:))
        apps.forEach { configurePage($0.page) }
    }

    func isPinned(_ url: URL?) -> Bool {
        guard let host = url?.host() else { return false }
        return apps.contains { $0.url.host() == host }
    }

    func pin(url: URL, title: String) {
        guard !isPinned(url) else { return }
        let app = PinnedApp(record: store.pinApp(url: url, title: title))
        configurePage(app.page)
        apps.append(app)
    }

    func unpin(_ app: PinnedApp) {
        if activeID == app.id { activeID = nil }
        app.page.webView.stopLoading()
        apps.removeAll { $0.id == app.id }
        store.unpinApp(id: app.id)
    }

    /// Clicking an app shows it; clicking the showing app puts it away.
    func toggle(_ app: PinnedApp) {
        activeID = activeID == app.id ? nil : app.id
    }

    func toggle(index: Int) {
        guard apps.indices.contains(index) else { return }
        toggle(apps[index])
    }

    func dismiss() {
        activeID = nil
    }
}
