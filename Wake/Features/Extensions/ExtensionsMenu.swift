import SwiftUI

/// The puzzle-piece popover: every enabled extension with its badge, a pin to keep
/// it in the toolbar, and the way to add or manage them.
@available(macOS 15.4, *)
struct ExtensionsMenu: View {
    let close: () -> Void
    @Environment(BrowserModel.self) private var browser
    private let library = ExtensionLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Extensions")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let host = browser.webPage?.host, !host.isEmpty {
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            let enabled = library.enabled
            if enabled.isEmpty {
                Text("Every extension is turned off.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 2) {
                    ForEach(enabled) { item in
                        ExtensionsMenuRow(item: item, run: {
                            close()
                            // Let SwiftUI's popover go before WebKit's popup takes its place.
                            Task {
                                try? await Task.sleep(for: .milliseconds(120))
                                library.performAction(item, in: browser)
                            }
                        })
                    }
                }
                .padding(.horizontal, 6)
            }

            Divider().padding(.top, 8)

            HStack(spacing: 4) {
                MenuFooterButton(symbol: "plus", title: "Add Extension…") {
                    close()
                    Extensions.chooseAndInstall()
                }
                Spacer(minLength: 0)
                MenuFooterButton(symbol: "gearshape", title: "Manage") {
                    close()
                    browser.showSettings(.extensions)
                }
            }
            .padding(6)
        }
        .frame(width: 300)
    }
}

@available(macOS 15.4, *)
private struct ExtensionsMenuRow: View {
    let item: InstalledExtension
    let run: () -> Void
    @Environment(BrowserModel.self) private var browser
    @State private var isHovered = false
    private let library = ExtensionLibrary.shared

    var body: some View {
        let _ = item.actionVersion
        let action = library.action(of: item, in: browser)
        HStack(spacing: 10) {
            Button(action: run) {
                HStack(spacing: 10) {
                    ExtensionGlyph(image: action?.icon(for: CGSize(width: 20, height: 20)) ?? item.icon(20), side: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        if let label = action?.label, !label.isEmpty, label != item.name {
                            Text(label)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if let badge = action?.badgeText, !badge.isEmpty {
                        ExtensionBadge(text: badge)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!item.hasToolbarAction)

            if item.hasToolbarAction {
                Button {
                    withAnimation(.chrome) { library.setPinned(item, !item.record.isPinned) }
                } label: {
                    Image(systemName: item.record.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(item.record.isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .opacity(isHovered || item.record.isPinned ? 1 : 0)
                .help(item.record.isPinned ? "Unpin from the toolbar" : "Pin to the toolbar")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 7, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.hover, value: isHovered)
        .contextMenu { ExtensionContextMenu(item: item) }
    }
}

private struct MenuFooterButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 6, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
