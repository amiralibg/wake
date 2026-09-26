import SwiftUI

/// Smart shelves with counts, then resolved threads with their outcomes.
struct MomentsSidebar: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(MomentStore.self) private var store

    var body: some View {
        let now = Date.now
        let host = browser.momentsHost
        let all = store.moments(includingArchived: true)
        let resolved = resolvedThreads
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("Moments")
            ForEach(MomentShelf.smart, id: \.self) { shelf in
                ShelfRow(
                    shelf: shelf,
                    title: shelf.title,
                    count: all.filter { shelf.contains($0, host: host, now: now) }.count
                )
            }
            ShelfRow(shelf: .archived, title: MomentShelf.archived.title, count: all.filter(\.isArchived).count)

            SectionLabel("History").padding(.top, 16)
            ShelfRow(shelf: .history, title: MomentShelf.history.title, count: HistoryStore.shared.visitCount)
            ShelfRow(shelf: .searches, title: MomentShelf.searches.title, count: HistoryStore.shared.searchCount)

            if !resolved.isEmpty {
                SectionLabel("Resolved threads").padding(.top, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(resolved) { record in
                            ResolvedRow(record: record)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            Spacer(minLength: 0)
            Button(action: browser.hideMoments) {
                Label("Back to the trail", systemImage: "chevron.left")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Back to the trail (esc)")
        }
        .padding(.horizontal, 10)
        // Clear of the traffic lights.
        .padding(.top, Metrics.toolbarHeight - 4)
        .padding(.bottom, 10)
    }

    private var resolvedThreads: [ThreadRecord] {
        _ = browser.threadListVersion
        _ = store.version
        return ThreadStore.shared.resolvedThreads()
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }
}

private struct ShelfRow: View {
    @Environment(BrowserModel.self) private var browser
    let shelf: MomentShelf
    let title: String
    let count: Int

    var body: some View {
        let isSelected = browser.momentsShelf == shelf && browser.momentsQuery.isEmpty
        Button {
            browser.momentsQuery = ""
            browser.momentsShelf = shelf
        } label: {
            HStack(spacing: 8) {
                Image(systemName: shelf.symbol)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isSelected ? AnyShapeStyle(.primary.opacity(0.09)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ResolvedRow: View {
    @Environment(BrowserModel.self) private var browser
    let record: ThreadRecord

    var body: some View {
        let isSelected = browser.momentsShelf == .resolvedThread(record.id)
        Button {
            browser.momentsQuery = ""
            browser.momentsShelf = .resolvedThread(record.id)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(record.customTitle ?? record.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if let outcome = record.outcome, !outcome.isEmpty {
                    Text(outcome)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(.primary.opacity(0.09)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
