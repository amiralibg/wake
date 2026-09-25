import SwiftUI

/// Rename or resolve the current thread, switch to another, or start a new one.
struct ThreadSwitcher: View {
    @Environment(BrowserModel.self) private var browser
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var isResolving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            currentThread
                .padding(14)
            Divider()
            if isResolving {
                ResolveThreadForm(
                    onResolve: { outcome in
                        isPresented = false
                        browser.resolveThread(outcome: outcome)
                    },
                    onCancel: { withAnimation(.snappy) { isResolving = false } }
                )
                .padding(14)
                .transition(.opacity)
            } else {
                otherThreads
                Divider()
                Button {
                    isPresented = false
                    browser.newThread()
                } label: {
                    Label("New Thread", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .help("New Thread (⇧⌘N)")
            }
        }
        .frame(width: 320)
        .onAppear { title = browser.thread.customTitle ?? "" }
    }

    private var currentThread: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(browser.thread.title, text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .onChange(of: title) { _, new in browser.renameThread(new) }
                .accessibilityLabel("Thread name")
            HStack {
                Text(pageCount(browser.thread.pageCount))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if !isResolving, browser.thread.pageCount > 0 {
                    Button("Resolve Thread…") { withAnimation(.snappy) { isResolving = true } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private var otherThreads: some View {
        let threads = browser.otherThreads
        if threads.isEmpty {
            Text("No other threads")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(14)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(threads) { record in
                        ThreadRow(record: record) {
                            isPresented = false
                            browser.switchToThread(id: record.id)
                        }
                        .contextMenu {
                            Button("Delete Thread", role: .destructive) { browser.deleteThread(id: record.id) }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pageCount(_ count: Int) -> String {
        count == 1 ? "1 page" : "\(count) pages"
    }
}

private struct ThreadRow: View {
    let record: ThreadRecord
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.customTitle ?? record.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("\(record.columns.count) pages · \(record.lastActiveAt, format: .relative(presentation: .named))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovering ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// "Resolve thread": one line on what you found out.
private struct ResolveThreadForm: View {
    let onResolve: (String) -> Void
    let onCancel: () -> Void

    @State private var outcome = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What did you find out?")
                .font(.system(size: 13, weight: .semibold))
            TextField("Booked Kōtoen for May 3–5", text: $outcome)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(resolve)
            Text("The thread closes and is kept in Moments with this line.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Resolve", action: resolve)
                    .keyboardShortcut(.defaultAction)
                    .disabled(outcome.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task {
            await Task.yield()
            isFocused = true
        }
    }

    private func resolve() {
        guard !outcome.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onResolve(outcome)
    }
}
