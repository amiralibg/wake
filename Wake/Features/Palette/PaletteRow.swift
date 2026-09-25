import SwiftUI

struct PaletteRow: View {
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if isSelected {
                KeyHint(item.isRefinement ? "tab" : "↩")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.tint.opacity(0.16))
            }
        }
        .contentShape(.rect)
    }

    @ViewBuilder private var icon: some View {
        switch item {
        case .open(let url):
            Favicon(url: nil, host: url.host() ?? "", size: 22)
        case .result(let result):
            Favicon(url: URL(string: "https://\(result.url.host() ?? "")/favicon.ico"), host: result.host, size: 22)
        case .recent(let page):
            Favicon(url: URL(string: "https://\(page.url.host() ?? "")/favicon.ico"), host: page.url.host() ?? "", size: 22)
        case .suggestion:
            symbol("magnifyingglass")
        case .searchOnWeb:
            symbol("globe")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var title: String {
        switch item {
        case .open(let url): "Open \(url.host() ?? url.absoluteString)"
        case .result(let result): result.title
        case .suggestion(let text): text
        case .recent(let page): page.title.isEmpty ? (page.url.host() ?? "") : page.title
        case .searchOnWeb(let query): "Open results for “\(query)” on DuckDuckGo"
        }
    }

    private var subtitle: String? {
        switch item {
        case .open(let url): url.absoluteString
        case .result(let result): result.snippet.isEmpty ? result.host : "\(result.host) — \(result.snippet)"
        case .recent(let page): page.url.host()
        case .suggestion, .searchOnWeb: nil
        }
    }
}

extension PaletteItem {
    var isRefinement: Bool {
        if case .suggestion = self { return true }
        return false
    }
}
