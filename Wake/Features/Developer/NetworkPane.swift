import AppKit
import SwiftUI

struct NetworkPane: View {
    let page: BrowserPage
    @State private var selection: NetworkEntry.ID?
    @State private var mockTarget: NetworkEntry?

    var body: some View {
        let entries = page.devtools.network
        VStack(spacing: 0) {
            if entries.isEmpty {
                ContentUnavailableView("No requests yet", systemImage: "network", description: Text("fetch and XMLHttpRequest calls from the page appear here."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries.reversed()) { entry in
                            Button {
                                withAnimation(.hover) { selection = selection == entry.id ? nil : entry.id }
                            } label: {
                                NetworkRow(entry: entry, isSelected: entry.id == selection, isMocked: page.devtools.mocks[entry.url.path()] != nil)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.method) \(entry.pathAndQuery), \(entry.status.map(String.init) ?? "pending")")
                            Divider()
                        }
                    }
                }
                if let entry = entries.first(where: { $0.id == selection }) {
                    Divider()
                    NetworkDetail(entry: entry, page: page, onMock: { mockTarget = entry })
                        .frame(maxHeight: 280)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $mockTarget) { entry in
            MockEditor(entry: entry, current: page.devtools.mocks[entry.url.path()]) { body in
                page.setMock(body, for: entry.url.path())
            }
        }
    }
}

private struct NetworkRow: View {
    let entry: NetworkEntry
    let isSelected: Bool
    let isMocked: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.method)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(entry.pathAndQuery)
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isMocked {
                Text("MOCK")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(.tint)
            }
            Text(statusText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 34, alignment: .trailing)
            Text(entry.duration.map { "\(Int($0 * 1000)) ms" } ?? "…")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear))
        .contentShape(.rect)
    }

    private var statusText: String {
        if entry.error != nil { return "ERR" }
        return entry.status.map(String.init) ?? "…"
    }

    private var statusColor: Color {
        guard let status = entry.status, entry.error == nil else { return Color(nsColor: .systemRed) }
        switch status {
        case 200..<300: return Color(nsColor: .systemGreen)
        case 300..<400: return .secondary
        default: return Color(nsColor: .systemRed)
        }
    }
}

private struct NetworkDetail: View {
    let entry: NetworkEntry
    let page: BrowserPage
    let onMock: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Replay") { page.replay(entry) }
                Button(copied ? "Copied" : "Copy as cURL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.curl, forType: .string)
                    copied = true
                }
                Button("Mock Response…", action: onMock)
                if page.devtools.mocks[entry.url.path()] != nil {
                    Button("Remove Mock") { page.setMock(nil, for: entry.url.path()) }
                }
            }
            .controlSize(.small)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("URL", entry.url.absoluteString)
                    if !entry.requestHeaders.isEmpty {
                        section("Request headers", entry.requestHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                    }
                    if let body = entry.requestBody, !body.isEmpty { section("Request body", body) }
                    if let error = entry.error { section("Error", error) }
                    if let preview = entry.responsePreview, !preview.isEmpty { section("Response", JSONFormatter.pretty(preview)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        }
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
            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
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
