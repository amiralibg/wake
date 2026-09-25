import Observation
import SwiftUI
import WebKit

/// Ordered columns of pages, left to right, with one in focus.
@MainActor
@Observable
final class TrailModel {
    private(set) var columns: [BrowserPage] = []
    private(set) var focusedIndex = 0
    /// Non-nil while a trackpad gesture or a resize is moving the trail.
    private(set) var dragOffset: CGFloat?
    /// Where the trail rests after a resize, instead of centring the focused column.
    /// Cleared as soon as focus moves, so the usual "keep focus in view" takes over.
    private(set) var restingOffset: CGFloat?
    /// Columns the user resized, as a share of the stage width.
    private(set) var customWidths: [BrowserPage.ID: CGFloat] = [:]
    /// True while a column edge is being dragged (the trail follows without springs).
    private(set) var isResizing = false
    /// The thread's developer-mode choice, applied to every page (`nil` = automatic).
    var developerModeOverride: Bool? {
        didSet { columns.forEach { $0.developerModeOverride = developerModeOverride } }
    }

    /// Written by TrailView whenever the stage or appearance changes.
    @ObservationIgnored var geometry = TrailGeometry()
    /// Called for every page this trail creates, so the owner can hook history etc.
    @ObservationIgnored var didCreatePage: (BrowserPage) -> Void = { _ in }
    /// Called whenever something worth saving changes: columns, focus, widths, URLs.
    @ObservationIgnored var onChange: () -> Void = {}

    var focused: BrowserPage? {
        columns.indices.contains(focusedIndex) ? columns[focusedIndex] : nil
    }

    // MARK: Opening and closing

    /// Opens `url` in a new column right after `source` (or after the focused column).
    @discardableResult
    func open(_ url: URL, after source: BrowserPage? = nil, focus: Bool = true) -> BrowserPage {
        let page = makePage()
        insert(page, after: source ?? focused, focus: focus)
        page.load(url)
        return page
    }

    /// Popups (`target=_blank`, `window.open`) must use WebKit's configuration so
    /// `window.opener` keeps working — OAuth sign-in flows depend on it.
    func openPopup(configuration: WKWebViewConfiguration, from source: BrowserPage?) -> WKWebView {
        let page = makePage(configuration: configuration)
        insert(page, after: source, focus: true)
        return page.webView
    }

    func close(_ page: BrowserPage) {
        guard let index = columns.firstIndex(where: { $0 === page }) else { return }
        // DevTools and previews belonging to this page go with it.
        let companions = columns.filter { isCompanion($0, of: page) }
        if !page.isEphemeral, let url = page.url ?? page.requestedURL {
            recentlyClosed.append(ClosedColumn(url: url, index: index, widthFraction: customWidths[page.id]))
            if recentlyClosed.count > 20 { recentlyClosed.removeFirst() }
        }
        withAnimation(.trail) {
            columns.remove(at: index)
            customWidths[page.id] = nil
            if index < focusedIndex || focusedIndex >= columns.count {
                focusedIndex = max(0, focusedIndex - 1)
            }
            restingOffset = nil
            // A lone column always fills the stage again.
            if columns.count == 1 { customWidths = [:] }
        }
        unlinkPreview(page)
        companions.forEach(close)
        focused.map(makeFirstResponder)
        onChange()
    }

    /// Closes every column, e.g. when the thread is resolved.
    func closeAll() {
        columns.forEach { $0.webView.stopLoading() }
        columns = []
        customWidths = [:]
        focusedIndex = 0
        restingOffset = nil
    }

    /// Recreates columns from a saved thread and starts loading them.
    func restore(_ snapshots: [BrowserThread.ColumnSnapshot], focusedIndex: Int) {
        let pages = snapshots.map { snapshot -> BrowserPage in
            let page = makePage()
            if snapshots.count > 1, let fraction = snapshot.widthFraction { customWidths[page.id] = fraction }
            page.load(snapshot.url)
            return page
        }
        columns = pages
        self.focusedIndex = min(max(focusedIndex, 0), max(pages.count - 1, 0))
    }

    func closeFocused() {
        focused.map(close)
    }

    struct ClosedColumn {
        let url: URL
        let index: Int
        let widthFraction: CGFloat?
    }

    /// Most recent last; ⇧⌘T brings them back.
    @ObservationIgnored private(set) var recentlyClosed: [ClosedColumn] = []

    /// Reopens the last closed column where it was.
    func reopenClosed() {
        guard let closed = recentlyClosed.popLast() else { return }
        let page = makePage()
        let index = min(closed.index, columns.count)
        if columns.count >= 1, let fraction = closed.widthFraction { customWidths[page.id] = fraction }
        withAnimation(.trail) {
            columns.insert(page, at: index)
            focusedIndex = index
            restingOffset = nil
        }
        page.load(closed.url)
        makeFirstResponder(page)
        onChange()
    }

    /// Opens the focused page again right after itself.
    func duplicateFocused() {
        guard let page = focused, !page.isDevTools, let url = page.url ?? page.requestedURL else { return }
        open(url, after: page)
    }

    /// Moves the focused column (with its DevTools and previews) one place left or right.
    func moveFocused(by step: Int) {
        guard let page = focused else { return }
        // Each page with its companions moves as one block.
        var groups: [[BrowserPage]] = []
        for column in columns {
            if let last = groups.last?.first, isCompanion(column, of: last) {
                groups[groups.count - 1].append(column)
            } else {
                groups.append([column])
            }
        }
        guard let from = groups.firstIndex(where: { $0.contains { $0 === page } }) else { return }
        let to = from + (step < 0 ? -1 : 1)
        guard groups.indices.contains(to) else { return }
        groups.swapAt(from, to)
        let owner = groups[to][0]
        withAnimation(.trail) {
            columns = groups.flatMap { $0 }
            focusedIndex = columns.firstIndex { $0 === owner } ?? focusedIndex
            restingOffset = nil
        }
        onChange()
    }

    private func insert(_ page: BrowserPage, after source: BrowserPage?, focus: Bool) {
        let index = source.map(insertionIndex(after:)) ?? columns.count
        withAnimation(.trail) {
            columns.insert(page, at: index)
            if focus {
                focusedIndex = index
            } else if index <= focusedIndex, columns.count > 1 {
                focusedIndex += 1
            }
            restingOffset = nil
        }
        if focus { makeFirstResponder(page) }
        onChange()
    }

    private func makePage(configuration: WKWebViewConfiguration? = nil) -> BrowserPage {
        let page = configuration.map(BrowserPage.init(configuration:)) ?? BrowserPage()
        page.onOpenLink = { [weak self, weak page] url, background in
            if !background, !BrowsingSettings.shared.linksOpenInNewColumn {
                page?.load(url)
            } else {
                self?.open(url, after: page, focus: !background)
            }
        }
        page.onOpenPopup = { [weak self, weak page] configuration in
            guard let self, let page else { return nil }
            return openPopup(configuration: configuration, from: page)
        }
        page.onClose = { [weak self, weak page] in
            if let page { self?.close(page) }
        }
        page.onStateChange = { [weak self] in self?.onChange() }
        page.onInspect = { pick in _ = EditorOpener.open(pick) }
        page.developerModeOverride = developerModeOverride
        didCreatePage(page)
        return page
    }

    // MARK: Focus

    func focus(_ index: Int) {
        guard columns.indices.contains(index) else { return }
        withAnimation(.trail) {
            focusedIndex = index
            dragOffset = nil
            restingOffset = nil
        }
        unbandedDrag = nil
        makeFirstResponder(columns[index])
        onChange()
    }

    func focus(id: BrowserPage.ID) {
        columns.firstIndex { $0.id == id }.map(focus)
    }

    func focusNext() { focus(min(focusedIndex + 1, columns.count - 1)) }
    func focusPrevious() { focus(max(focusedIndex - 1, 0)) }

    /// ⌃Tab: next column, wrapping around.
    func cycleFocus(forward: Bool) {
        guard !columns.isEmpty else { return }
        focus((focusedIndex + (forward ? 1 : columns.count - 1)) % columns.count)
    }

    private func makeFirstResponder(_ page: BrowserPage) {
        page.webView.window?.makeFirstResponder(page.webView)
    }

    // MARK: Developer columns

    @ObservationIgnored private var previewSources: [BrowserPage.ID: BrowserPage] = [:]

    func devTools(for page: BrowserPage) -> BrowserPage? {
        columns.first { $0.isDevTools && $0.inspectedPage === page }
    }

    /// Shows or hides the DevTools column next to `page`. Focus stays on the page.
    func toggleDevTools(for page: BrowserPage) {
        if let existing = devTools(for: page) {
            close(existing)
            return
        }
        let tools = BrowserPage(devToolsFor: page)
        customWidths[tools.id] = Self.devToolsFraction(usable: geometry.usableWidth)
        insert(tools, after: page, focus: false)
    }

    /// DevTools open at the width they were last dragged to; the first time, about
    /// two fifths of the stage (never under 480pt).
    private static func devToolsFraction(usable: CGFloat) -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: "devtools.widthFraction")
        if saved > 0 { return saved }
        guard usable > 0 else { return 0.4 }
        return min(0.6, max(0.4, 480 / usable))
    }

    /// Opens the same URL in a device-sized column that scrolls in step with the
    /// original. Phones get a mobile user agent.
    ///
    /// Limitation: WKWebView has no device emulation. `devicePixelRatio` stays the
    /// Mac screen's, there are no touch events, and `(pointer: coarse)` / `(hover: none)`
    /// media queries still describe the Mac's pointer.
    func openResponsivePreview(of page: BrowserPage, device: DevicePreset) {
        if let existing = previews(of: page).first {
            existing.device = DeviceFrame(preset: device)
            return
        }
        guard let url = page.url else { return }
        let preview = makePage()
        preview.isEphemeral = true
        preview.device = DeviceFrame(preset: device)
        previewSources[preview.id] = page
        insert(preview, after: page, focus: false)
        preview.load(url)
        page.syncsScroll = true
        preview.syncsScroll = true
        page.onScroll = { [weak self, weak page] fraction in
            guard let self, let page else { return }
            self.previews(of: page).forEach { $0.scroll(toFraction: fraction) }
        }
        preview.onScroll = { [weak page] fraction in page?.scroll(toFraction: fraction) }
        page.setScrollSync(true)
    }

    /// The focused column plus the DevTools and previews right after it, kept in view together.
    var focusSpan: Int {
        guard let focused else { return 1 }
        let companions = columns.dropFirst(focusedIndex + 1).prefix { isCompanion($0, of: focused) }
        return 1 + companions.count
    }

    /// The DevTools and previews right after `page`.
    func companions(of page: BrowserPage) -> [BrowserPage] {
        guard let index = columns.firstIndex(where: { $0 === page }) else { return [] }
        return Array(columns.dropFirst(index + 1).prefix { isCompanion($0, of: page) })
    }

    func previewSource(of page: BrowserPage) -> BrowserPage? {
        previewSources[page.id]
    }

    /// Right after `source` and its DevTools and previews, which stay beside it.
    private func insertionIndex(after source: BrowserPage) -> Int {
        guard let index = columns.firstIndex(where: { $0 === source }) else { return columns.count }
        let companions = columns.dropFirst(index + 1).prefix { isCompanion($0, of: source) }
        return index + 1 + companions.count
    }

    private func isCompanion(_ column: BrowserPage, of page: BrowserPage) -> Bool {
        column.inspectedPage === page || previewSources[column.id] === page
    }

    private func previews(of page: BrowserPage) -> [BrowserPage] {
        columns.filter { previewSources[$0.id] === page }
    }

    private func unlinkPreview(_ page: BrowserPage) {
        if let source = previewSources.removeValue(forKey: page.id), previews(of: source).isEmpty {
            source.syncsScroll = false
            source.onScroll = nil
            source.setScrollSync(false)
        }
    }

    // MARK: Column widths

    func widthFraction(of page: BrowserPage) -> CGFloat? {
        customWidths[page.id]
    }

    enum Edge { case leading, trailing }

    @ObservationIgnored private var activeResize: (id: BrowserPage.ID, edge: Edge, width: CGFloat, offset: CGFloat)?

    /// Where the trail is showing right now (as the view computes it).
    var displayedOffset: CGFloat {
        dragOffset ?? restingOffset.map(geometry.clamped) ?? geometry.targetOffset(focusing: focusedIndex, span: focusSpan)
    }

    /// Starts dragging one edge of `page`. Only that column changes width; its
    /// neighbours keep theirs and slide, and the trail scrolls when it outgrows the
    /// stage (like resizing a window beside another).
    func beginResize(_ page: BrowserPage, edge: Edge) {
        guard let index = columns.firstIndex(where: { $0 === page }) else { return }
        activeResize = (page.id, edge, geometry.width(of: index), displayedOffset)
        isResizing = true
    }

    /// `delta` is how far the pointer moved since the drag began. The edge under the
    /// pointer follows it; the opposite edge stays where it is on screen.
    func resize(by delta: CGFloat) {
        guard let resize = activeResize else { return }
        let usable = geometry.usableWidth
        guard usable > 0 else { return }
        let minimum = min(Metrics.minResizedColumnWidth, usable)
        let width = min(max(resize.width + (resize.edge == .trailing ? delta : -delta), minimum), usable)
        customWidths[resize.id] = width / usable
        // Dragging the leading edge: the columns before it move out of the way.
        dragOffset = resize.edge == .leading ? resize.offset + (width - resize.width) : resize.offset
    }

    func endResize() {
        guard let resize = activeResize else { return }
        activeResize = nil
        if let page = columns.first(where: { $0.id == resize.id }), page.isDevTools, let fraction = customWidths[page.id] {
            UserDefaults.standard.set(Double(fraction), forKey: "devtools.widthFraction")
        }
        let rest = dragOffset
        withAnimation(.trail) {
            isResizing = false
            dragOffset = nil
            restingOffset = rest
        }
        onChange()
    }

    /// Double-click on an edge: the column goes back to its default width.
    func resetWidth(of page: BrowserPage) {
        withAnimation(.trail) {
            customWidths[page.id] = nil
            restingOffset = nil
        }
        onChange()
    }

    /// ⌥⌘= / ⌥⌘−: the focused column grows or shrinks by a tenth of the stage.
    func resizeFocused(by step: CGFloat) {
        guard let page = focused, columns.count > 1, page.device == nil else { return }
        let usable = geometry.usableWidth
        guard usable > 0 else { return }
        let current = geometry.width(of: focusedIndex) / usable
        let minimum = min(Metrics.minResizedColumnWidth / usable, 1)
        withAnimation(.trail) {
            customWidths[page.id] = min(max(current + step, minimum), 1)
            restingOffset = nil
        }
        onChange()
    }

    // MARK: Trackpad scrolling

    /// Drag position without rubber-banding, so resistance doesn't compound.
    @ObservationIgnored private var unbandedDrag: CGFloat?

    /// `delta` follows the fingers: positive moves the trail right (towards earlier columns).
    func scroll(by delta: CGFloat) {
        let next = (unbandedDrag ?? displayedOffset) - delta
        unbandedDrag = next
        dragOffset = geometry.rubberBanded(next)
    }

    /// Snaps to the column the gesture is heading for. `velocity` is in points/second.
    func endScroll(velocity: CGFloat) {
        guard let drag = unbandedDrag else { return }
        var target = geometry.nearestIndex(to: drag - velocity * 0.18)
        // A deliberate flick always moves at least one column.
        if target == focusedIndex, abs(velocity) > 350 {
            target = min(max(focusedIndex + (velocity < 0 ? 1 : -1), 0), columns.count - 1)
        }
        focus(target)
    }
}
