import Foundation
import SwiftUI

/// Sidebar entries of the Moments library.
enum MomentShelf: Hashable {
    case everything, relevant, resurfacing, changed, fading, archived
    case resolvedThread(UUID)

    static let smart: [MomentShelf] = [.everything, .relevant, .resurfacing, .changed, .fading]

    var title: String {
        switch self {
        case .everything: "Everything"
        case .relevant: "Relevant here"
        case .resurfacing: "Resurfacing today"
        case .changed: "Changed since saved"
        case .fading: "Fading"
        case .archived: "Archived"
        case .resolvedThread: "Resolved thread"
        }
    }

    var symbol: String {
        switch self {
        case .everything: "tray"
        case .relevant: "mappin.and.ellipse"
        case .resurfacing: "clock"
        case .changed: "arrow.triangle.2.circlepath"
        case .fading: "hourglass"
        case .archived: "archivebox"
        case .resolvedThread: "checkmark.circle"
        }
    }

    /// Whether `moment` belongs on this shelf.
    func contains(_ moment: MomentRecord, host: String?, now: Date) -> Bool {
        switch self {
        case .everything: !moment.isArchived
        case .relevant: MomentRules.isRelevant(moment, host: host)
        case .resurfacing: MomentRules.isResurfacing(moment, now: now)
        case .changed: !moment.isArchived && moment.changedAt != nil
        case .fading: MomentRules.isFading(moment, now: now)
        case .archived: moment.isArchived
        case .resolvedThread: false
        }
    }
}

enum MomentsLayout: Hashable { case grid, timeline }

extension BrowserModel {
    /// The site you're on, for "Relevant here".
    var momentsHost: String? {
        webPage?.url.flatMap { url in
            let host = url.host() ?? ""
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    // MARK: Saving

    /// ⌘D: saves the focused page as a moment right away (URL, title, scroll,
    /// selection, snapshot, text), then offers a "why" note and when to resurface.
    func saveMoment() {
        guard let page = webPage, let url = page.url, url.scheme?.hasPrefix("http") == true else { return }
        let threadID = thread.id
        Task {
            let state = await page.captureMomentState()
            let moment = MomentStore.shared.save(url: url, state: state, threadID: threadID, resurface: .nextWeek)
            ThumbnailStore.moments.capture(page, for: moment.id)
            withAnimation(.chrome) { savedMoment = moment }
        }
    }

    /// Closes the note island. The moment is already saved.
    func finishSavingMoment() {
        withAnimation(.chrome) { savedMoment = nil }
        refocusPage()
    }

    func undoSaveMoment() {
        if let savedMoment { MomentStore.shared.delete(savedMoment) }
        finishSavingMoment()
    }

    // MARK: Library

    func toggleMoments() {
        isMomentsOpen ? hideMoments() : showMoments()
    }

    func showMoments(_ shelf: MomentShelf? = nil) {
        hidePalette()
        hideSettings()
        apps.dismiss()
        savedMoment = nil
        momentsQuery = ""
        if let shelf { momentsShelf = shelf }
        MomentStore.shared.archiveStale()
        withAnimation(.chrome) { isMomentsOpen = true }
    }

    func hideMoments() {
        withAnimation(.chrome) { isMomentsOpen = false }
        refocusPage()
    }

    /// Takes you back to the moment: its page (an open column if there is one),
    /// scrolled to where you were, with your selection highlighted.
    func openMoment(_ moment: MomentRecord) {
        withAnimation(.chrome) { isMomentsOpen = false }
        MomentStore.shared.markOpened(moment)
        let restore = MomentRestore(moment)
        let rebaseline: (BrowserPage) -> Void = { page in
            Task {
                let text = await page.visibleText()
                MomentStore.shared.rebaseline(moment, text: text)
            }
        }
        if let open = trail.columns.first(where: { !$0.isDevTools && $0.device == nil && Self.samePage($0.url, moment.url) }) {
            trail.focus(id: open.id)
            Task {
                await open.applyRestore(restore)
                rebaseline(open)
            }
        } else {
            let page = trail.open(moment.url)
            page.pendingRestore = restore
            page.onRestored = rebaseline
        }
    }

    /// Opens every page of a resolved thread's record as a fresh thread.
    func reopenThread(_ record: ThreadRecord) {
        withAnimation(.chrome) { isMomentsOpen = false }
        reopenResolvedThread(id: record.id)
    }

    private static func samePage(_ a: URL?, _ b: URL) -> Bool {
        guard let a else { return false }
        var left = URLComponents(url: a, resolvingAgainstBaseURL: false)
        var right = URLComponents(url: b, resolvingAgainstBaseURL: false)
        left?.fragment = nil
        right?.fragment = nil
        return left == right
    }
}
