import AppKit
import SwiftUI

struct ConsolePane: View {
    let page: BrowserPage
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", errors = "Errors", warnings = "Warnings"
        var id: Self { self }
    }

    var body: some View {
        let entries = page.devtools.console.filter { entry in
            switch filter {
            case .all: true
            case .errors: entry.level == .error
            case .warnings: entry.level == .warn
            }
        }
        VStack(spacing: 0) {
            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(8)
            if entries.isEmpty {
                ContentUnavailableView("No messages", systemImage: "text.bubble", description: Text("Console output from the page appears here."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                ConsoleRow(entry: entry, page: page)
                                    .id(entry.id)
                                Divider()
                            }
                        }
                    }
                    .onChange(of: entries.last?.id) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
    }
}

private struct ConsoleRow: View {
    let entry: ConsoleEntry
    let page: BrowserPage

    @State private var isExpanded = false
    @State private var isHovering = false
    @State private var status: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(entry.level == .error ? tint : .primary)
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
                    if isHovering, entry.level == .error || entry.level == .warn {
                        Button("Copy for AI") { copyForAI() }
                            .buttonStyle(.link)
                            .font(.system(size: 10.5))
                    }
                }
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
        case .log, .debug: "chevron.right"
        }
    }

    private var tint: Color {
        switch entry.level {
        case .error: Color(nsColor: .systemRed)
        case .warn: Color(nsColor: .systemOrange)
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
