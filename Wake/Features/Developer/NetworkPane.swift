import AppKit
import SwiftUI

/// Every request the page made. fetch and XHR come from developer mode's hooks, with
/// headers, bodies, replay and mocks; everything else (documents, scripts, styles,
/// images, fonts, media) comes from the page's Resource Timing buffer, on any page.
///
/// Limitation: Resource Timing has no headers or bodies, and cross-origin entries
/// without `Timing-Allow-Origin` report zero sizes and phases. WebKit also has no
/// public API for network throttling or for turning the cache off per page, so the
/// Tools menu offers Empty Caches and Reload Without Cache instead.
struct NetworkPane: View {
    let page: BrowserPage
    @State private var selection: NetworkItem.ID?
    @State private var mockTarget: NetworkEntry?
    @State private var filter: NetworkItem.Category = .all
    @State private var search = ""
    @State private var copiedHAR = false

    var body: some View {
        let all = NetworkItem.items(log: page.devtools, resources: page.inspector.resources, hooked: page.isDeveloperMode, documentStatus: page.live.httpStatus)
        let query = search.trimmingCharacters(in: .whitespaces)
        let items = all.filter { (filter == .all || $0.category == filter) && (query.isEmpty || $0.url.absoluteString.localizedCaseInsensitiveContains(query)) }
        let scale = WaterfallScale(items.compactMap { item in item.start.map { ($0, $0 + (item.duration ?? 0)) } })
        VStack(spacing: 0) {
            toolbar
            Divider()
            if !page.isDeveloperMode {
                CaptureBanner(page: page, message: "Turn on developer mode for fetch/XHR headers, bodies, replay and mocks.")
            }
            if items.isEmpty {
                ContentUnavailableView(all.isEmpty ? "No requests yet" : "Nothing matches", systemImage: "network",
                                       description: Text(all.isEmpty ? "Requests appear here as the page makes them. Reload to see the page load." : "Try another filter."))
                    .frame(maxHeight: .infinity)
            } else {
                header(compressed: scale.isCompressed)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            Button {
                                withAnimation(.hover) { selection = selection == item.id ? nil : item.id }
                            } label: {
                                NetworkRow(item: item, scale: scale, isSelected: item.id == selection,
                                           isMocked: page.devtools.mocks[item.url.path()] != nil)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { NetworkItemMenu(item: item, page: page) }
                            .accessibilityLabel("\(item.method) \(item.url.path()), \(item.statusText)")
                        }
                    }
                }
                if let item = items.first(where: { $0.id == selection }) {
                    Divider()
                    NetworkDetail(item: item, page: page, onMock: { mockTarget = item.hooked })
                        .frame(height: 300)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            Divider()
            footer(items: items, all: all)
        }
        .task(id: page.url) {
            while !Task.isCancelled {
                await page.inspector.pollResources()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(item: $mockTarget) { entry in
            MockEditor(entry: entry, current: page.devtools.mocks[entry.url.path()]) { body in
                page.setMock(body, for: entry.url.path())
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            DevToolsSearchField(text: $search, prompt: "Filter URLs")
                .frame(maxWidth: 180)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(NetworkItem.Category.allCases) { category in
                        Button(category.title) { filter = category }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: filter == category ? .semibold : .regular))
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(filter == category ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5))
                            .foregroundStyle(filter == category ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                }
            }
        }
        .padding(8)
    }

    private func header(compressed: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Status").frame(width: 42, alignment: .trailing)
            Text("Type").frame(width: 50, alignment: .leading)
            Text("Size").frame(width: 56, alignment: .trailing)
            Text("Time").frame(width: 52, alignment: .trailing)
            Text(compressed ? "Waterfall ⋯" : "Waterfall")
                .frame(width: 90, alignment: .leading)
                .help(compressed ? "Idle stretches over a second are shortened so every burst of requests stays readable." : "")
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 22)
    }

    private func footer(items: [NetworkItem], all: [NetworkItem]) -> some View {
        let transferred = items.reduce(0) { $0 + ($1.transferSize ?? 0) }
        let resources = items.reduce(0) { $0 + ($1.size ?? 0) }
        let finish = items.compactMap { item in item.start.map { $0 + (item.duration ?? 0) } }.max()
        return HStack(spacing: 12) {
            Text(items.count == all.count ? "\(all.count) requests" : "\(items.count) / \(all.count) requests")
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(transferred), countStyle: .file)) transferred")
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(resources), countStyle: .file)) resources")
            if let finish { Text("Finish \(NetworkItem.milliseconds(finish))") }
            Spacer(minLength: 0)
            Button(copiedHAR ? "Copied" : "Copy HAR") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(HARExporter.har(for: all, documentStart: page.devtools.documentStart), forType: .string)
                copiedHAR = true
            }
            .buttonStyle(.link)
            .disabled(all.isEmpty)
            .help("Copy every request as an HTTP Archive (HAR) for other tools")
        }
        .font(.system(size: 10.5).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .onChange(of: all.count) { copiedHAR = false }
    }
}

/// One row of the Network list, whichever source it came from.
struct NetworkItem: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case all, fetch, document, script, style, image, font, media, other
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "All"
            case .fetch: "Fetch/XHR"
            case .document: "Doc"
            case .script: "JS"
            case .style: "CSS"
            case .image: "Img"
            case .font: "Font"
            case .media: "Media"
            case .other: "Other"
            }
        }
    }

    let id: String
    let method: String
    let url: URL
    let status: Int?
    let category: Category
    let typeLabel: String
    let transferSize: Int?
    let size: Int?
    let duration: Double?
    let start: Double?
    let isCached: Bool
    var hooked: NetworkEntry?
    var resource: DevToolsSession.Resource?

    var isFailure: Bool { hooked?.isFailure ?? ((status ?? 0) >= 400) }

    var name: String {
        let last = url.lastPathComponent
        let base = last.isEmpty || last == "/" ? (url.host() ?? url.absoluteString) : last
        return url.query().map { "\(base)?\($0)" } ?? base
    }

    var statusText: String {
        if hooked?.error != nil { return "ERR" }
        if let status, status > 0 { return "\(status)" }
        if hooked != nil { return "…" }
        return isCached ? "cache" : "—"
    }

    /// Compact sizes for the table: "519 B", "12.4 kB". Zero means "not reported".
    static func bytes(_ value: Int?) -> String {
        guard let value, value > 0 else { return "—" }
        if value < 1000 { return "\(value) B" }
        if value < 1_000_000 { return String(format: "%.1f kB", Double(value) / 1000) }
        return String(format: "%.1f MB", Double(value) / 1_000_000)
    }

    static func milliseconds(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.2f s", value / 1000) : "\(Int(value.rounded())) ms"
    }

    @MainActor static func items(log: DevToolsLog, resources: [DevToolsSession.Resource], hooked: Bool, documentStatus: Int? = nil) -> [NetworkItem] {
        var items: [NetworkItem] = []
        var claimed = Set<Int>()
        let fetchLike: Set<String> = ["fetch", "xmlhttprequest", "beacon"]
        if hooked {
            for entry in log.network {
                // Pair the hooked request with its timing entry, if the page reported one.
                let match = resources.last { $0.url == entry.url && fetchLike.contains($0.type) && !claimed.contains($0.id) }
                if let match { claimed.insert(match.id) }
                let start = match?.start ?? entry.startedAt.timeIntervalSince(log.documentStart) * 1000
                items.append(NetworkItem(
                    id: "h\(entry.id)", method: entry.method, url: entry.url, status: entry.status,
                    category: .fetch, typeLabel: entry.initiator,
                    transferSize: match.map(\.transferSize), size: entry.responseSize ?? match?.decodedSize,
                    duration: entry.duration.map { $0 * 1000 } ?? match?.duration, start: start,
                    isCached: false, hooked: entry, resource: match
                ))
            }
        }
        for resource in resources where !claimed.contains(resource.id) && !(hooked && fetchLike.contains(resource.type)) {
            let category = category(of: resource)
            // WebKit's Resource Timing has no status; for the document, Wake knows it.
            let status = resource.status > 0 ? resource.status : (resource.type == "navigation" ? documentStatus : nil)
            items.append(NetworkItem(
                id: "r\(resource.id)", method: "GET", url: resource.url, status: status,
                category: category, typeLabel: typeLabel(resource, category),
                transferSize: resource.transferSize, size: resource.decodedSize,
                duration: resource.duration, start: resource.start, isCached: resource.isCached, resource: resource
            ))
        }
        return items.sorted { ($0.start ?? .infinity) < ($1.start ?? .infinity) }
    }

    private static func category(of resource: DevToolsSession.Resource) -> Category {
        let ext = resource.url.pathExtension.lowercased()
        if ["woff", "woff2", "ttf", "otf", "eot"].contains(ext) { return .font }
        if ["png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "ico"].contains(ext) { return .image }
        if ["mp4", "webm", "mp3", "m4a", "ogg", "wav", "m3u8", "ts"].contains(ext) { return .media }
        if ext == "css" { return .style }
        if ["js", "mjs", "cjs"].contains(ext) { return .script }
        switch resource.type {
        case "navigation", "iframe", "frame": return .document
        case "script": return .script
        case "css", "link": return ext == "css" ? .style : .other
        case "img", "image", "input": return .image
        case "video", "audio", "track": return .media
        case "fetch", "xmlhttprequest", "beacon": return .fetch
        default: return .other
        }
    }

    private static func typeLabel(_ resource: DevToolsSession.Resource, _ category: Category) -> String {
        switch category {
        case .document: "document"
        case .script: "script"
        case .style: "stylesheet"
        case .image: resource.url.pathExtension.isEmpty ? "image" : resource.url.pathExtension.lowercased()
        case .font: "font"
        case .media: "media"
        case .fetch: resource.type == "xmlhttprequest" ? "xhr" : resource.type
        default: resource.type
        }
    }
}

private struct NetworkRow: View {
    let item: NetworkItem
    let scale: WaterfallScale
    let isSelected: Bool
    let isMocked: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(item.name)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(item.isFailure ? Color(nsColor: .systemRed) : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isMocked {
                    Text("MOCK")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.tint.opacity(0.18), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.statusText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 42, alignment: .trailing)
            Text(item.typeLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 50, alignment: .leading)
            Text(item.isCached && (item.transferSize ?? 0) == 0 ? "cache" : NetworkItem.bytes(item.size))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Text(item.duration.map(NetworkItem.milliseconds) ?? "…")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            WaterfallBar(item: item, scale: scale)
                .frame(width: 90, height: 8)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear))
        .contentShape(.rect)
    }

    private var symbol: String {
        switch item.category {
        case .document: "doc"
        case .script: "curlybraces"
        case .style: "paintbrush"
        case .image: "photo"
        case .font: "textformat"
        case .media: "play.rectangle"
        case .fetch: "arrow.left.arrow.right"
        default: "shippingbox"
        }
    }

    private var statusColor: Color {
        if item.hooked?.error != nil { return Color(nsColor: .systemRed) }
        guard let status = item.status else { return .secondary }
        switch status {
        case 200..<300: return Color(nsColor: .systemGreen)
        case 300..<400: return .secondary
        default: return Color(nsColor: .systemRed)
        }
    }
}

/// Where the request sat on the page's timeline, split into its phases.
private struct WaterfallBar: View {
    let item: NetworkItem
    let scale: WaterfallScale

    var body: some View {
        GeometryReader { geometry in
            let from = item.start ?? 0
            let start = scale.x(from, width: geometry.size.width)
            let width = max(2, scale.x(from + (item.duration ?? 0), width: geometry.size.width) - start)
            HStack(spacing: 0) {
                if let r = item.resource, r.duration > 0 {
                    ForEach(Array(TimingPhase.phases(of: r).enumerated()), id: \.offset) { _, phase in
                        phase.color.frame(width: max(0, width * phase.value / r.duration))
                    }
                    Spacer(minLength: 0)
                } else {
                    Color(nsColor: .systemBlue)
                }
            }
            .frame(width: width, height: geometry.size.height)
            .clipShape(.rect(cornerRadius: 2))
            .offset(x: min(start, geometry.size.width - width))
        }
    }
}

/// The waterfall's time axis. Linear, except that idle stretches (nothing in flight
/// for over a second, e.g. a fetch long after the page loaded) are shortened, so one
/// late request doesn't squash everything the page loaded into a sliver.
struct WaterfallScale {
    /// Real-time ranges where something was in flight, and where each starts on the axis.
    private var busy: [(start: Double, end: Double, axis: Double)] = []
    private var span: Double = 1
    private(set) var isCompressed = false

    private static let idleThreshold = 1.0

    init(_ intervals: [(start: Double, end: Double)]) {
        var merged: [(start: Double, end: Double)] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end + Self.idleThreshold {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        guard !merged.isEmpty else { return }
        // A shortened gap still reads as a gap: a twentieth of the busy time (at least
        // a quarter of the threshold).
        let busyTime = merged.reduce(0) { $0 + ($1.end - $1.start) }
        let gap = max(Self.idleThreshold / 4, busyTime / 20)
        // The document start is time zero; a long wait before the first request is idle too.
        var axis = merged[0].start
        if axis > Self.idleThreshold {
            axis = gap
            isCompressed = true
        }
        for (index, range) in merged.enumerated() {
            if index > 0 {
                axis += gap
                isCompressed = true
            }
            busy.append((range.start, range.end, axis))
            axis += range.end - range.start
        }
        span = max(axis, 0.001)
    }

    /// Where time `t` (seconds since the document started) falls on a bar `width` wide.
    func x(_ t: Double, width: CGFloat) -> CGFloat {
        guard let range = busy.last(where: { $0.start <= t }) ?? busy.first else { return CGFloat(t / span) * width }
        let axis = range.axis + min(max(t - range.start, 0), range.end - range.start)
        return CGFloat(axis / span) * width
    }
}

struct TimingPhase {
    let name: String
    let value: Double
    let color: Color

    static func phases(of r: DevToolsSession.Resource) -> [TimingPhase] {
        [
            TimingPhase(name: "Queued", value: r.blocked, color: Color(nsColor: .systemGray)),
            TimingPhase(name: "DNS", value: r.dns, color: Color(nsColor: .systemTeal)),
            TimingPhase(name: "Connect", value: max(0, r.connect - r.tls), color: Color(nsColor: .systemOrange)),
            TimingPhase(name: "TLS", value: r.tls, color: Color(nsColor: .systemPurple)),
            TimingPhase(name: "Waiting (TTFB)", value: r.wait, color: Color(nsColor: .systemGreen)),
            TimingPhase(name: "Download", value: r.download, color: Color(nsColor: .systemBlue)),
        ]
    }
}

private struct NetworkItemMenu: View {
    let item: NetworkItem
    let page: BrowserPage

    var body: some View {
        Button("Copy URL") { copy(item.url.absoluteString) }
        if let entry = item.hooked {
            Button("Copy as cURL") { copy(entry.curl) }
            Button("Copy as fetch") { copy(HARExporter.fetch(for: entry)) }
            if let body = entry.responsePreview { Button("Copy Response") { copy(body) } }
            Divider()
            Button("Replay") { page.replay(entry) }
        } else {
            Button("Copy as cURL") { copy("curl '\(item.url.absoluteString.replacingOccurrences(of: "'", with: "'\\''"))'") }
        }
        Divider()
        Button("Open in New Column") { BrowserModel.active?.trail.open(item.url) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct NetworkDetail: View {
    let item: NetworkItem
    let page: BrowserPage
    let onMock: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case headers = "Headers", payload = "Payload", response = "Response", timing = "Timing"
        var id: Self { self }
    }

    @State private var tab: Tab = .headers
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                if let entry = item.hooked {
                    Button("Replay") { page.replay(entry) }
                    Button(copied ? "Copied" : "cURL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.curl, forType: .string)
                        copied = true
                    }
                    if page.devtools.mocks[entry.url.path()] != nil {
                        Button("Remove Mock") { page.setMock(nil, for: entry.url.path()) }
                    } else {
                        Button("Mock…", action: onMock)
                    }
                }
            }
            .controlSize(.small)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .headers: headers
                    case .payload: payload
                    case .response: response
                    case .timing: timing
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .onChange(of: item.id) { copied = false }
    }

    @ViewBuilder private var headers: some View {
        DetailSection(title: "General", rows: [
            ("URL", item.url.absoluteString),
            ("Method", item.method),
            ("Status", item.statusText),
            ("Type", item.typeLabel),
            ("Protocol", item.resource?.protocolName ?? ""),
            ("Transferred", item.transferSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""),
            ("Size", item.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""),
        ].filter { !$0.1.isEmpty })
        if let entry = item.hooked {
            if !entry.responseHeaders.isEmpty {
                DetailSection(title: "Response headers", rows: entry.responseHeaders.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
            }
            if !entry.requestHeaders.isEmpty {
                DetailSection(title: "Request headers", rows: entry.requestHeaders.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
            }
        } else {
            Text("Headers are only captured for fetch and XHR in developer mode.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var payload: some View {
        let query = URLComponents(url: item.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if !query.isEmpty {
            DetailSection(title: "Query string", rows: query.map { ($0.name, $0.value ?? "") })
        }
        if let body = item.hooked?.requestBody, !body.isEmpty {
            DetailText(title: "Request body", text: JSONFormatter.pretty(body))
        }
        if query.isEmpty, item.hooked?.requestBody?.isEmpty != false {
            Text("No payload.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var response: some View {
        if let error = item.hooked?.error {
            DetailText(title: "Error", text: error)
        }
        if item.category == .image {
            AsyncImage(url: item.url) { image in
                image.resizable().scaledToFit().frame(maxWidth: 260, maxHeight: 200)
            } placeholder: { ProgressView().controlSize(.small) }
        } else if let preview = item.hooked?.responsePreview, !preview.isEmpty {
            DetailText(title: "Response", text: JSONFormatter.pretty(preview))
        } else if item.category == .script || item.category == .style || item.category == .document {
            SourcePreview(url: item.url, session: page.inspector)
        } else {
            Text("No response body captured.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var timing: some View {
        if let r = item.resource, r.duration > 0 {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(TimingPhase.phases(of: r).filter { $0.value > 0.05 }, id: \.name) { phase in
                    HStack(spacing: 8) {
                        Text(phase.name).font(.system(size: 11)).frame(width: 110, alignment: .leading)
                        GeometryReader { geometry in
                            phase.color
                                .frame(width: max(2, geometry.size.width * phase.value / r.duration))
                                .clipShape(.rect(cornerRadius: 2))
                        }
                        .frame(height: 8)
                        Text(NetworkItem.milliseconds(phase.value))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                Divider()
                HStack {
                    Text("Total").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(NetworkItem.milliseconds(r.duration)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                Text("Started \(NetworkItem.milliseconds(r.start)) after navigation.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        } else if let duration = item.duration {
            Text("Took \(NetworkItem.milliseconds(duration)). The server didn't allow detailed timing (Timing-Allow-Origin).")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            Text("Pending…").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

/// Fetches and shows a script, stylesheet or document for the Response tab.
private struct SourcePreview: View {
    let url: URL
    let session: DevToolsSession
    @State private var text: String?

    var body: some View {
        Group {
            if let text {
                DetailText(title: "Response", text: String(text.prefix(30000)))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) { text = await session.text(of: url) }
    }
}

struct DetailSection: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.0)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)
                        .lineLimit(1)
                    Text(row.1)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct DetailText: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        }
    }
}

/// HTTP Archive export and "Copy as fetch".
@MainActor
enum HARExporter {
    static func har(for items: [NetworkItem], documentStart: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let entries: [[String: Any]] = items.map { item in
            let started = documentStart.addingTimeInterval((item.start ?? 0) / 1000)
            let requestHeaders = (item.hooked?.requestHeaders ?? [:]).map { ["name": $0.key, "value": $0.value] }
            let responseHeaders = (item.hooked?.responseHeaders ?? [:]).map { ["name": $0.key, "value": $0.value] }
            let query = (URLComponents(url: item.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ["name": $0.name, "value": $0.value ?? ""] }
            var request: [String: Any] = [
                "method": item.method, "url": item.url.absoluteString, "httpVersion": item.resource?.protocolName ?? "",
                "headers": requestHeaders, "queryString": query, "cookies": [], "headersSize": -1,
                "bodySize": item.hooked?.requestBody?.utf8.count ?? 0,
            ]
            if let body = item.hooked?.requestBody {
                request["postData"] = ["mimeType": item.hooked?.requestHeaders["content-type"] ?? "", "text": body]
            }
            let r = item.resource
            return [
                "startedDateTime": formatter.string(from: started),
                "time": item.duration ?? 0,
                "request": request,
                "response": [
                    "status": item.status ?? 0, "statusText": "", "httpVersion": r?.protocolName ?? "",
                    "headers": responseHeaders, "cookies": [], "redirectURL": "", "headersSize": -1,
                    "bodySize": item.transferSize ?? -1,
                    "content": ["size": item.size ?? 0, "mimeType": item.hooked?.responseHeaders["content-type"] ?? item.typeLabel,
                                "text": item.hooked?.responsePreview ?? ""],
                ],
                "cache": [:],
                "timings": [
                    "blocked": r?.blocked ?? -1, "dns": r?.dns ?? -1, "connect": r?.connect ?? -1, "ssl": r?.tls ?? -1,
                    "send": 0, "wait": r?.wait ?? (item.duration ?? 0), "receive": r?.download ?? 0,
                ],
            ]
        }
        let har: [String: Any] = ["log": ["version": "1.2", "creator": ["name": "Wake", "version": "0.1"], "entries": entries]]
        let data = (try? JSONSerialization.data(withJSONObject: har, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func fetch(for entry: NetworkEntry) -> String {
        var options: [String: Any] = ["method": entry.method, "headers": entry.requestHeaders]
        if let body = entry.requestBody { options["body"] = body }
        let json = (try? JSONSerialization.data(withJSONObject: options, options: [.prettyPrinted, .sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "fetch(\(DevToolsScripts.quoted(entry.url.absoluteString)), \(json));"
    }
}

/// Answer a route with JSON you write, without touching the server. fetch calls to
/// that path are intercepted in the page. (XMLHttpRequest isn't mocked.)
private struct MockEditor: View {
    let entry: NetworkEntry
    let current: String?
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mock \(entry.url.path())").font(.headline)
            Text("fetch calls to this path return this JSON with status 200 until you remove the mock.")
                .font(.callout).foregroundStyle(.secondary)
            CodeTextEditor(text: $text)
                .frame(minWidth: 480, minHeight: 260)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            if let error {
                Text(error).font(.caption).foregroundStyle(Color(nsColor: .systemRed))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Mock") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear { text = current ?? JSONFormatter.pretty(entry.responsePreview ?? "{}") }
    }

    private func save() {
        guard (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) != nil else {
            error = "That isn't valid JSON."
            return
        }
        onSave(text)
        dismiss()
    }
}

enum JSONFormatter {
    /// Pretty-printed JSON when `text` parses; otherwise `text` unchanged.
    static func pretty(_ text: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        else { return text }
        return String(decoding: data, as: UTF8.self)
    }
}
