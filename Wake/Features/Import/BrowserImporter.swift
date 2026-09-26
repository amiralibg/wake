import Foundation
import Observation
import WebKit

/// Runs one import: reads the other browser off the main thread, then merges into
/// Wake's history, cookie jar and site storage.
@MainActor
@Observable
final class BrowserImporter {
    struct Options {
        var history = true
        var searches = true
        var cookies = true
        var siteData = true
    }

    struct Report {
        var options = Options()
        var pages = 0
        var searches = 0
        var cookies = 0
        var sites = 0
        var notes: [String] = []
    }

    enum Phase {
        case idle
        case running(String)
        case finished(Report)
    }

    private(set) var phase: Phase = .idle

    var isRunning: Bool { if case .running = phase { true } else { false } }

    func run(_ profile: BrowserProfile, options: Options) async {
        var report = Report(options: options)
        let source = profile.browser

        if options.history || options.searches {
            phase = .running("Reading \(source) history…")
            do {
                let visits = try await Task.detached { try BrowserReader.history(profile) }.value
                if options.history {
                    phase = .running("Adding \(visits.count.formatted()) pages…")
                    report.pages = await HistoryStore.shared.importVisits(visits, source: source)
                }
                if options.searches {
                    phase = .running("Finding searches…")
                    let searches = await Task.detached { BrowserReader.searches(profile, visits: visits) }.value
                    report.searches = await HistoryStore.shared.importSearches(searches, source: source)
                }
            } catch {
                report.notes.append(error.localizedDescription)
            }
        }

        if options.cookies {
            phase = .running("Reading \(source) cookies…")
            do {
                let cookies = try await Task.detached { try BrowserReader.cookies(profile) }.value
                phase = .running("Adding \(cookies.count.formatted()) cookies…")
                report.cookies = await addCookies(cookies)
            } catch {
                report.notes.append(error.localizedDescription)
            }
        }

        if options.siteData, profile.supportsSiteData {
            phase = .running("Reading \(source) site data…")
            let sites = await Task.detached { LocalStorageReader.read(profile) }.value
            let writer = LocalStorageWriter()
            for (index, site) in sites.enumerated() {
                phase = .running("Site data \(index + 1) of \(sites.count)…")
                if await writer.write(origin: site.key, items: site.value) > 0 { report.sites += 1 }
            }
            report.notes.append("IndexedDB, caches and service workers can't move between browser engines; sites rebuild them as you use them.")
        }

        phase = .finished(report)
    }

    func reset() { phase = .idle }

    /// Adds cookies Wake doesn't have yet (same name, domain and path), so importing
    /// never signs you out of something you're already signed into in Wake.
    private func addCookies(_ cookies: [ImportedCookie]) async -> Int {
        let store = WKWebsiteDataStore.default().httpCookieStore
        var existing = Set(await store.allCookies().map { "\($0.name)|\($0.domain)|\($0.path)" })
        var added = 0
        for cookie in cookies {
            guard let http = cookie.httpCookie, existing.insert("\(http.name)|\(http.domain)|\(http.path)").inserted else { continue }
            await store.setCookie(http)
            added += 1
        }
        return added
    }
}
