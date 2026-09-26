#if BENCH
import AppKit
import Foundation
import WebKit

/// Scripted scenarios for `Scripts/bench/bench.sh`. Only compiled into the bench
/// build (`-D BENCH`, bundle id `app.wake.Wake.bench`), never into a release.
///
/// The scenario comes from `WAKE_BENCH`. Each measurement point prints `MARK <name>`
/// on stdout; the script samples memory and CPU of Wake and its WebKit processes
/// there. `DONE` ends the run.
@MainActor
enum Benchmark {
    static func startIfRequested() {
        guard let scenario = ProcessInfo.processInfo.environment["WAKE_BENCH"] else { return }
        Task { @MainActor in
            while BrowserModel.active == nil { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
            guard let browser = BrowserModel.active else { return }
            await run(scenario, browser)
            emit("DONE")
        }
    }

    static let sites = [
        "https://en.wikipedia.org/wiki/WebKit",
        "https://github.com/apple/swift",
        "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
        "https://www.notion.com/help",
        "https://www.theverge.com",
        "http://localhost:8765/",
    ]

    static let pool = [
        "https://en.wikipedia.org/wiki/Swift_(programming_language)", "https://developer.apple.com/documentation/webkit",
        "https://news.ycombinator.com", "https://github.com/apple/swift-collections",
        "https://en.wikipedia.org/wiki/Safari_(web_browser)", "https://developer.mozilla.org/en-US/docs/Web/JavaScript",
        "https://www.apple.com/macos/", "https://github.com/sparkle-project/Sparkle",
        "https://en.wikipedia.org/wiki/Memory_management", "https://developer.mozilla.org/en-US/docs/Web/CSS",
        "https://www.bbc.com/news", "https://github.com/yonaskolb/XcodeGen",
        "https://en.wikipedia.org/wiki/Macintosh", "https://developer.mozilla.org/en-US/docs/Web/HTML",
        "https://lobste.rs", "https://github.com/pointfreeco/swift-composable-architecture",
        "https://en.wikipedia.org/wiki/Web_browser", "https://www.swift.org/documentation/",
        "https://www.theguardian.com/international", "https://github.com/apple/swift-nio",
        "https://en.wikipedia.org/wiki/Unix", "https://developer.mozilla.org/en-US/docs/Web/API",
        "https://arstechnica.com", "https://github.com/vapor/vapor",
    ]

    static func emit(_ line: String) {
        let visible = BrowserModel.active?.window?.occlusionState.contains(.visible) ?? false
        let hidden = pages.compactMap(\.page).filter { $0.webView.isHidden }.count
        print(line.hasPrefix("MARK ") ? "\(line) pages=\(livePages),webviews=\(webViews.filter { $0.view != nil }.count),hidden=\(hidden),visible=\(visible)" : line)
        fflush(stdout)
    }

    private struct Weak { weak var page: BrowserPage? }
    private static var pages: [Weak] = []
    private struct WeakView { weak var view: WKWebView? }
    private static var webViews: [WeakView] = []

    /// Every BrowserPage made, weakly: a closed column that stays counted is leaking.
    static func track(_ page: BrowserPage) {
        pages.removeAll { $0.page == nil }
        pages.append(Weak(page: page))
        webViews.removeAll { $0.view == nil }
        webViews.append(WeakView(view: page.webView))
    }

    static var livePages: Int {
        pages.removeAll { $0.page == nil }
        return pages.count
    }

    static func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    static func open(_ urls: [String], in browser: BrowserModel, spacing: Double = 1.5) async {
        for string in urls {
            browser.trail.open(URL(string: string)!)
            await wait(spacing)
        }
    }

    /// Back to a single column in a single thread, as a person closing everything would.
    static func closeEverything(_ browser: BrowserModel, threads: [UUID]) async {
        for id in threads {
            browser.switchToThread(id: id)
            await wait(0.5)
            // An emptied thread is unloaded when it's switched away from.
            while let page = browser.trail.columns.first { browser.trail.close(page) }
        }
        browser.trail.open(URL(string: pool[0])!)
    }

    /// Pauses audio and video everywhere, as in "YouTube with a paused video".
    static func pauseMedia(_ browser: BrowserModel) async {
        for page in browser.trail.columns {
            _ = try? await page.webView.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(m => m.pause()); 0")
        }
    }

    static func run(_ scenario: String, _ browser: BrowserModel) async {
        switch scenario {
        case "leak":
            await open(Array(sites[0..<3]), in: browser)
            await wait(8)
            if ProcessInfo.processInfo.environment["WAKE_BENCH_PAUSE"] != nil { await pauseMedia(browser) }
            while browser.trail.columns.count > 1, let page = browser.trail.columns.last { browser.trail.close(page) }
            await wait(8)
            let focused = browser.trail.focused.map { ObjectIdentifier($0) }
            for entry in pages {
                guard let page = entry.page, ObjectIdentifier(page) != focused else { continue }
                emit("LEAKED \(Unmanaged.passUnretained(page).toOpaque()) \(page.url?.absoluteString ?? "")")
            }
            emit("MARK leak")
            await wait(600)

        case "discard":
            // Thread A: four pages, the focused one scrolled; then thread B in front.
            let threadA = browser.thread.id
            await open(Array(pool[0..<4]), in: browser)
            await wait(10)
            _ = try? await browser.trail.focused?.webView.evaluateJavaScript("window.scrollTo(0, 900); 0")
            await wait(1)
            browser.newThread()
            browser.hidePalette()
            await open([pool[4]], in: browser)
            await wait(12)
            emit("MARK discard_before")
            BrowserModel.discardBackgroundThreads()
            await wait(12)
            emit("MARK discard_after")
            await wait(60)
            emit("MARK discard_after_60s")
            browser.switchToThread(id: threadA)
            await wait(12)
            let y = await browser.trail.focused?.scrollY() ?? -1
            emit("TIME restored-scroll \(Int(y)) (was 900) columns=\(browser.trail.columns.count)")
            emit("MARK discard_back")

        case "cold":
            await wait(10)
            emit("MARK cold")

        case "browse":
            await open(sites, in: browser)
            await wait(10)
            await pauseMedia(browser)
            await wait(20)
            await pauseMedia(browser)
            emit("MARK browse")
            while browser.trail.columns.count > 1, let page = browser.trail.columns.last { browser.trail.close(page) }
            await wait(30)
            emit("MARK browse_closed")

        case "threads":
            var ids = [browser.thread.id]
            await open(Array(pool[0..<4]), in: browser)
            for index in 1..<6 {
                browser.newThread()
                browser.hidePalette()
                ids.append(browser.thread.id)
                await open(Array(pool[(index * 4)..<(index * 4 + 4)]), in: browser)
                await wait(4)
            }
            await wait(15)
            emit("MARK threads_built")
            for _ in 0..<2 {
                for id in ids {
                    browser.switchToThread(id: id)
                    await wait(3)
                }
            }
            await wait(10)
            emit("MARK threads_switched")
            await closeEverything(browser, threads: ids)
            await wait(30)
            emit("MARK threads_closed")

        case "offscreen":
            // Window in front and visible, six columns, focus on the first two.
            await open(sites, in: browser)
            await wait(10)
            await pauseMedia(browser)
            browser.trail.focus(0)
            await wait(15)
            await pauseMedia(browser)
            emit("MARK offscreen_start")
            await wait(60)
            emit("MARK offscreen_end")

        case "offanim":
            // Six pages that animate constantly; only the first two (and a neighbour)
            // are on stage.
            await open(Array(repeating: "http://localhost:8766/anim.html", count: 6), in: browser)
            browser.trail.focus(0)
            await wait(10)
            emit("MARK offanim_start")
            await wait(30)
            emit("MARK offanim_end")

        case "idle":
            await open(sites, in: browser)
            await wait(10)
            await pauseMedia(browser)
            await wait(15)
            await pauseMedia(browser)
            NSApp.hide(nil)
            await wait(5)
            emit("MARK idle_start")
            await wait(120)
            emit("MARK idle_end")

        case "deck":
            await seedHistory(count: 25_000)
            var ids = [browser.thread.id]
            await open(Array(pool[0..<2]), in: browser)
            for index in 1..<4 {
                browser.newThread()
                browser.hidePalette()
                ids.append(browser.thread.id)
                await open(Array(pool[(index * 2)..<(index * 2 + 2)]), in: browser)
            }
            await wait(15)
            emit("MARK deck_base")
            for _ in 0..<10 {
                browser.openDeck()
                await wait(1.5)
                browser.hidePalette()
                await wait(0.8)
            }
            await wait(3)
            emit("MARK deck_opened")
            browser.showMoments()
            await wait(4)
            emit("MARK moments")
            browser.showHistory()
            await wait(4)
            for query in ["w", "wi", "wik", "wiki", "github", "e"] {
                browser.momentsQuery = query
                await wait(0.4)
            }
            browser.momentsQuery = ""
            await wait(4)
            timeHistoryQueries()
            emit("MARK history")
            browser.hideMoments()
            await wait(30)
            emit("MARK deck_closed")

        case "devtools":
            browser.trail.open(URL(string: "http://localhost:8765/")!)
            await wait(12)
            emit("MARK devtools_base")
            for round in 1...5 {
                guard let page = browser.webPage else { break }
                browser.toggleDevTools()
                for tab in DevToolsSession.Tab.allCases {
                    page.inspector.tab = tab
                    await wait(2)
                }
                browser.toggleDevTools()
                await wait(8)
                emit("MARK devtools_\(round)")
            }

        case "onboarding":
            await wait(5)
            emit("MARK onboarding_start")
            await wait(30)
            emit("MARK onboarding_end")

        default:
            emit("unknown scenario \(scenario)")
        }
    }

    /// Main-thread cost of what History runs while you type (and on every redraw).
    static func timeHistoryQueries() {
        let store = HistoryStore.shared
        func time(_ label: String, _ work: () -> Int) {
            let start = ContinuousClock.now
            var result = 0
            for _ in 0..<5 { result = work() }
            let ms = (ContinuousClock.now - start) / 5
            emit("TIME \(label) \(ms.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1)))) -> \(result)")
        }
        time("visits(empty)") { store.visits(matching: "", limit: 100).count }
        time("visits(wiki)") { store.visits(matching: "wiki", limit: 100).count }
        time("visits(github.com/rust)") { store.visits(matching: "github.com/rust", limit: 100).count }
        time("visits(nomatch)") { store.visits(matching: "zzqx", limit: 100).count }
        time("visitCount") { store.visitCount }
    }

    /// Makes History big enough to matter (imports once per bench container).
    static func seedHistory(count: Int) async {
        guard HistoryStore.shared.visitCount < count else { return }
        let words = ["swift", "webkit", "memory", "design", "apple", "rust", "graph", "cache", "thread", "column"]
        let hosts = ["en.wikipedia.org", "github.com", "developer.apple.com", "news.ycombinator.com", "example.com"]
        let now = Date.now
        let visits = (0..<count).map { index in
            let word = words[index % words.count]
            let host = hosts[index % hosts.count]
            return HistoryStore.ImportedVisit(
                url: URL(string: "https://\(host)/\(word)/\(index)")!,
                title: "\(word.capitalized) page \(index)",
                lastVisit: now.addingTimeInterval(-Double(index) * 90),
                visitCount: 1 + index % 7
            )
        }
        _ = await HistoryStore.shared.importVisits(visits, source: "bench")
    }
}
#endif
