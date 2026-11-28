import SwiftUI
import WebKit

/// Find in page (⌘F): a glass island under the toolbar. ↩ and ⌘G go to the next
/// match, ⇧↩ and ⇧⌘G to the previous one, Esc closes it.
///
/// WebKit limitation: `WKWebView.find(_:configuration:)` only says whether there was
/// a match and selects it; it has no match count or index and doesn't highlight the
/// other matches. The count comes from `shared/scripts/find-count.js` (visible text,
/// so it can differ from WebKit's matches in hidden text), and the island shows
/// "n matches" rather than "3 of 12".
@MainActor
@Observable
final class FindModel {
    enum Status: Equatable {
        case idle
        case found(count: Int)
        case notFound
    }

    private(set) var isOpen = false
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    var caseSensitive = false {
        didSet { if caseSensitive != oldValue { scheduleSearch() } }
    }
    private(set) var status: Status = .idle
    /// Bumped to focus and select the field again (⌘F while it's already open).
    private(set) var focusRequest = 0

    @ObservationIgnored private weak var page: BrowserPage?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    func open(on page: BrowserPage) {
        if self.page !== page {
            self.page = page
            status = .idle
            if !query.isEmpty { scheduleSearch() }
        }
        isOpen = true
        focusRequest += 1
    }

    func close() {
        searchTask?.cancel()
        isOpen = false
        status = .idle
        page = nil
    }

    /// ⌘G / ⇧⌘G, and ↩ / ⇧↩ in the field.
    func findAgain(forward: Bool) {
        guard !query.isEmpty, let webView = page?.webView else { return }
        Task { await find(in: webView, forward: forward) }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard let webView = page?.webView else { return }
        let query = query
        guard !query.isEmpty else {
            status = .idle
            Task { _ = try? await webView.evaluateJavaScript("getSelection().removeAllRanges()", in: nil, contentWorld: WebScripts.world) }
            return
        }
        searchTask = Task {
            // Typing fast shouldn't search for every letter.
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            // Start from the top, so the first match is the page's first, not the one
            // after an old selection.
            _ = try? await webView.evaluateJavaScript("getSelection().removeAllRanges()", in: nil, contentWorld: WebScripts.world)
            guard !Task.isCancelled else { return }
            let count = try? await webView.evaluateJavaScript(
                SharedScript.findCount.source(["query": query, "caseSensitive": caseSensitive, "limit": 1000]),
                in: nil, contentWorld: WebScripts.world
            ) as? Int
            guard !Task.isCancelled else { return }
            await find(in: webView, forward: true, count: count)
        }
    }

    private func find(in webView: WKWebView, forward: Bool, count: Int? = nil) async {
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.caseSensitive = caseSensitive
        configuration.wraps = true
        let result = try? await webView.find(query, configuration: configuration)
        guard isOpen else { return }
        if result?.matchFound == true {
            let known: Int = if case .found(let previous) = status { previous } else { 1 }
            status = .found(count: max(count ?? known, 1))
        } else {
            status = .notFound
        }
    }
}

extension BrowserModel {
    func showFind() {
        guard let page = webPage else { return }
        find.open(on: page)
    }

    func findAgain(forward: Bool) {
        if find.isOpen { find.findAgain(forward: forward) } else { showFind() }
    }

    func hideFind() {
        find.close()
        refocusPage()
    }
}

/// The island itself, top right under the toolbar like the Save Moment island.
struct FindIsland: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(\.isZen) private var isZen

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if browser.find.isOpen {
                FindField(model: browser.find, onClose: browser.hideFind)
                    .padding(.top, isZen ? Metrics.stageInset : Metrics.toolbarHeight + 2)
                    .padding(.trailing, Metrics.toolbarPadding)
                    .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.chrome, value: browser.find.isOpen)
        // A page switch moves find to the new page, or closes it if there's none.
        .onChange(of: browser.webPage?.id) {
            guard browser.find.isOpen else { return }
            if let page = browser.webPage { browser.find.open(on: page) } else { browser.find.close() }
        }
    }
}

private struct FindField: View {
    @Bindable var model: FindModel
    let onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Find in page", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .frame(width: 170)
                .onSubmit { model.findAgain(forward: !NSEvent.modifierFlags.contains(.shift)) }
                .onKeyPress(.escape) { onClose(); return .handled }
            Text(statusText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(model.status == .notFound ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .frame(minWidth: 64, alignment: .trailing)
                .contentTransition(.numericText())
            Toggle(isOn: $model.caseSensitive) { Text("Aa").font(.system(size: 11, weight: .semibold)) }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Match case")
            HStack(spacing: 2) {
                islandButton("chevron.up", help: "Previous match (⇧⌘G)") { model.findAgain(forward: false) }
                islandButton("chevron.down", help: "Next match (⌘G)") { model.findAgain(forward: true) }
            }
            .disabled(model.query.isEmpty)
            islandButton("xmark", help: "Close (esc)", action: onClose)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: .capsule)
        .glassSurface(Capsule(), vibrantContent: false)
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
        .task(id: model.focusRequest) {
            await Task.yield()
            isFocused = true
            // ⌘F again selects what's there, ready to type over.
            NSApp.keyWindow?.firstResponder.flatMap { $0 as? NSTextView }?.selectAll(nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Find in page")
    }

    private var statusText: String {
        switch model.status {
        case .idle: ""
        case .found(let count): count >= 1000 ? "1000+ matches" : count == 1 ? "1 match" : "\(count) matches"
        case .notFound: "Not found"
        }
    }

    private func islandButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
