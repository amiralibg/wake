import AppKit
import SwiftUI

struct ConsolePane: View {
    let page: BrowserPage
    @State private var filter: Filter = .all
    @State private var search = ""
    @AppStorage("devtools.console.timestamps") private var showsTimestamps = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", errors = "Errors", warnings = "Warnings", info = "Info", logs = "Logs"
        var id: Self { self }

        func includes(_ level: ConsoleEntry.Level) -> Bool {
            switch self {
            case .all: true
            case .errors: level == .error
            case .warnings: level == .warn
            case .info: level == .info
            case .logs: [.log, .debug, .input, .result].contains(level)
            }
        }
    }

    var body: some View {
        @Bindable var log = page.devtools
        let query = search.trimmingCharacters(in: .whitespaces)
        let entries = page.devtools.console.filter { entry in
            filter.includes(entry.level) && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query))
        }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { filter in
                        Text(label(for: filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                DevToolsSearchField(text: $search, prompt: "Filter")
                Menu {
                    Toggle("Show Timestamps", isOn: $showsTimestamps)
                    Toggle("Preserve Log on Navigation", isOn: $log.preservesLog)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Console options")
            }
            .controlSize(.small)
            .padding(8)
            Divider()
            if !page.isDeveloperMode {
                CaptureBanner(page: page)
            }
            if entries.isEmpty {
                ContentUnavailableView(
                    page.devtools.console.isEmpty ? "No messages" : "Nothing matches",
                    systemImage: "text.bubble",
                    description: Text(page.devtools.console.isEmpty ? "Console output from the page appears here. Type JavaScript below to run it in the page." : "Try another filter.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                ConsoleRow(entry: entry, page: page, showsTimestamp: showsTimestamps)
                                    .id(entry.id)
                                Divider()
                            }
                        }
                    }
                    .onChange(of: entries.last?.id) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                    .onAppear { if let id = entries.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            Divider()
            ConsolePrompt(session: page.inspector)
        }
    }

    private func label(for filter: Filter) -> String {
        switch filter {
        case .errors where page.devtools.errorCount > 0: "Errors \(page.devtools.errorCount)"
        case .warnings where page.devtools.warningCount > 0: "Warnings \(page.devtools.warningCount)"
        default: filter.rawValue
        }
    }
}

/// Page logs need developer mode's hooks; the prompt works without them.
struct CaptureBanner: View {
    let page: BrowserPage
    var message = "Page logs are captured in developer mode."

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Turn On and Reload") {
                page.developerModeOverride = true
                page.reload()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.04))
    }
}

/// The JavaScript prompt: ↩ runs, ⌥↩ adds a line, ↑/↓ walk history, ⇥ completes.
private struct ConsolePrompt: View {
    let session: DevToolsSession

    @State private var code = ""
    @State private var historyIndex: Int?
    @State private var completions: [String] = []
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !completions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(completions, id: \.self) { name in
                            Button(name) { complete(with: name) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.primary.opacity(0.07), in: .rect(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                Divider()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tint)
                TextField("Run JavaScript in the page ($0 is the selected element)", text: $code, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .onSubmit(run)
                    .onKeyPress(.upArrow) { walkHistory(-1) }
                    .onKeyPress(.downArrow) { walkHistory(1) }
                    .onKeyPress(.tab) {
                        Task { await suggest() }
                        return .handled
                    }
                    .onChange(of: code) { if !completions.isEmpty { completions = [] } }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(.primary.opacity(0.025))
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
    }

    private func run() {
        let input = code
        code = ""
        historyIndex = nil
        completions = []
        Task { await session.evaluate(input) }
    }

    private func walkHistory(_ delta: Int) -> KeyPress.Result {
        let history = session.history
        guard !history.isEmpty, !code.contains("\n") || historyIndex != nil else { return .ignored }
        let next = (historyIndex ?? history.count) + delta
        if next >= history.count {
            historyIndex = nil
            code = ""
        } else {
            historyIndex = max(0, next)
            code = history[historyIndex!]
        }
        return .handled
    }

    private func suggest() async {
        let found = await session.completions(for: code)
        if found.count == 1 { complete(with: found[0]) } else { completions = found }
    }

    private func complete(with name: String) {
        let prefixEnd = code.lastIndex { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "$") }
        let base = prefixEnd.map { String(code[...$0]) } ?? ""
        code = base + name
        completions = []
        isFocused = true
    }
}

/// A compact search field for DevTools toolbars.
struct DevToolsSearchField: View {
    @Binding var text: String
    var prompt = "Filter"
    var onSubmit: () -> Void = {}
    /// ↑/↓ inside the field, e.g. to step through search matches. Nil leaves the keys alone.
    var onStep: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .onSubmit(onSubmit)
                .onKeyPress(.upArrow) { step(-1) }
                .onKeyPress(.downArrow) { step(1) }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .frame(minWidth: 90, maxWidth: .infinity)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 6, style: .continuous))
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        guard let onStep else { return .ignored }
        onStep(delta)
        return .handled
    }
}

private struct ConsoleRow: View {
    let entry: ConsoleEntry
    let page: BrowserPage
    var showsTimestamp = false

    @State private var isExpanded = false
    @State private var isHovering = false
    @State private var status: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: [.log, .debug].contains(entry.level) ? 5 : 11))
                .foregroundStyle(tint)
                .frame(width: 14, height: 14)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(entry.level == .error ? tint : (entry.level == .result ? .secondary : .primary))
                    .lineLimit(isExpanded ? nil : 3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isExpanded, let stack = entry.stack {
                    Text(stack)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    if let source = entry.source {
                        Button("\(source.fileName):\(source.line)") { openInEditor(source) }
                            .buttonStyle(.link)
                            .font(.system(size: 10.5))
                            .help("Open in Editor")
                    }
                    if let status {
                        Text(status).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if showsTimestamp {
                        Text(entry.date, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if isHovering, entry.level == .error || entry.level == .warn {
                        Button("Copy for AI") { copyForAI() }
                            .buttonStyle(.link)
                            .font(.system(size: 10.5))
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if entry.repeatCount > 1 {
                Text("\(entry.repeatCount)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(tint == .secondary ? Color(nsColor: .systemGray) : tint, in: Capsule())
                    .padding(6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(entry.level == .error ? tint.opacity(0.06) : (entry.level == .warn ? tint.opacity(0.05) : .clear))
        .contentShape(.rect)
        .onTapGesture { withAnimation(.hover) { isExpanded.toggle() } }
        .onHover { isHovering = $0 }
        .contextMenu {
            if let source = entry.source { Button("Open in Editor") { openInEditor(source) } }
            Button("Copy for AI") { copyForAI() }
            Button("Copy Message") { copy(entry.message) }
        }
    }

    private var icon: String {
        switch entry.level {
        case .error: "xmark.octagon.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        case .log, .debug: "circle.fill"
        case .input: "chevron.right"
        case .result: "arrow.turn.down.left"
        }
    }

    private var tint: Color {
        switch entry.level {
        case .error: Color(nsColor: .systemRed)
        case .warn: Color(nsColor: .systemOrange)
        case .input: Color(nsColor: .controlAccentColor)
        default: .secondary
        }
    }

    private func openInEditor(_ source: SourceLocation) {
        status = "Resolving…"
        Task {
            let result = await EditorOpener.open(source)
            status = switch result {
            case .success: nil
            case .failure(.noProjectFolder): "Link the project folder to open files"
            case .failure(.noSource): "No source found"
            }
        }
    }

    private func copyForAI() {
        copy(AIReport.markdown(for: entry, page: page))
        status = "Copied"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// "Copy for AI": the error, where it happened, the component, and the request that
/// failed around it, as markdown ready to paste into an assistant.
@MainActor
enum AIReport {
    static func markdown(for entry: ConsoleEntry, page: BrowserPage) -> String {
        var lines = ["## \(entry.level == .warn ? "Warning" : "Error"): \(entry.message.split(separator: "\n").first ?? "")", ""]
        if let url = page.url { lines.append("- **Page:** \(url.absoluteString)") }
        if let component = entry.component { lines.append("- **Component:** `<\(component)>`") }
        if let source = entry.source { lines.append("- **Location:** `\(source.url.path()):\(source.line):\(source.column)`") }
        if let failure = page.devtools.network.last(where: { $0.isFailure && $0.startedAt <= entry.date.addingTimeInterval(1) }) {
            lines.append("- **Failing request:** `\(failure.method) \(failure.pathAndQuery)` → \(failure.status.map(String.init) ?? "no response")\(failure.error.map { " (\($0))" } ?? "")")
            if let body = failure.responsePreview, !body.isEmpty {
                lines += ["", "Response:", "```", String(body.prefix(1200)), "```"]
            }
        }
        lines += ["", "Message:", "```", entry.message, "```"]
        if let stack = entry.stack, !stack.isEmpty {
            lines += ["", "Stack:", "```", stack, "```"]
        }
        return lines.joined(separator: "\n")
    }
}
