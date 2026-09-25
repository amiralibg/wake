import SwiftUI

/// A resolved thread in Moments: its outcome, the pages it ended with, and any
/// moments saved along the way. It can be reopened as a live thread.
struct ResolvedThreadDetail: View {
    let threadID: UUID

    @Environment(BrowserModel.self) private var browser
    @Environment(MomentStore.self) private var store

    var body: some View {
        _ = browser.threadListVersion
        let record = ThreadStore.shared.record(for: threadID)
        return VStack(spacing: 0) {
            if let record {
                header(record)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let outcome = record.outcome, !outcome.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Outcome", systemImage: "checkmark.seal")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(outcome)
                                    .font(.system(size: 15))
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.tint.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
                        }
                        pages(record)
                        moments
                    }
                    .padding(24)
                }
            } else {
                Text("This thread no longer exists.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func header(_ record: ThreadRecord) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(record.customTitle ?? record.title)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                Text(resolvedLine(record))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Delete", role: .destructive) {
                browser.momentsShelf = .everything
                browser.deleteThread(id: record.id)
            }
            Button("Reopen Thread") { browser.reopenThread(record) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .frame(height: 60)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func resolvedLine(_ record: ThreadRecord) -> String {
        let pages = record.columns.count
        let when = (record.resolvedAt ?? record.lastActiveAt).formatted(date: .abbreviated, time: .omitted)
        return "Resolved \(when) · \(pages) page\(pages == 1 ? "" : "s")"
    }

    private func pages(_ record: ThreadRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pages")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let columns = record.orderedColumns
                ForEach(columns, id: \.order) { column in
                    PageRow(url: column.url, title: column.title) {
                        browser.hideMoments()
                        browser.trail.open(column.url)
                    }
                    if column.order != columns.last?.order { Divider().padding(.leading, 38) }
                }
            }
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    @ViewBuilder private var moments: some View {
        let saved = store.moments(includingArchived: true).filter { $0.threadID == threadID }
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Moments saved in this thread")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 18)], spacing: 18) {
                    ForEach(saved) { moment in
                        MomentCard(moment: moment, status: MomentStatus.of(moment, host: nil, now: .now)) {
                            browser.openMoment(moment)
                        }
                        .contextMenu { MomentMenu(moment: moment) }
                    }
                }
            }
        }
    }
}

private struct PageRow: View {
    let url: URL
    let title: String
    let action: () -> Void

    var body: some View {
        let host = url.host() ?? ""
        Button(action: action) {
            HStack(spacing: 10) {
                Favicon(url: URL(string: "https://\(host)/favicon.ico"), host: host, size: 16)
                Text(title.isEmpty ? url.absoluteString : title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(host)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Open in the trail")
    }
}
