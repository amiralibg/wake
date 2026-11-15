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
                ScrollView {
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
                // A browser's worth of imported extensions scrolls instead of running
                // off the screen.
                .frame(maxHeight: 440)
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize)
            }

            if let page = browser.webPage, library.pageNeedingReload == page.id {
                ReloadToApply { library.reloadAfterAccessChange(page) }
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
        .animation(.chrome, value: library.pageNeedingReload)
    }
}

/// Shown after site access changed: content scripts only start or stop on a reload.
@available(macOS 15.4, *)
private struct ReloadToApply: View {
    let reload: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.tint)
            Text("Reload the page to apply the change.")
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Reload", action: reload)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8, style: .continuous))
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: run) {
                    HStack(spacing: 10) {
                        ExtensionGlyph(image: action?.icon(for: CGSize(width: 20, height: 20)) ?? item.icon(20), side: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            if library.wantsAccess(item, to: browser.webPage?.url) {
                                Label("Wants access here", systemImage: "circle.fill")
                                    .labelStyle(DotLabelStyle())
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tint)
                                    .lineLimit(1)
                            } else if !library.wantsSiteAccess(item), let label = action?.label, !label.isEmpty, label != item.name {
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

                // Outside the row's button, so choosing doesn't also run the extension.
                if library.wantsSiteAccess(item) {
                    let restricted = item.record.siteAccess == .chosenSites
                    SiteAccessMenu(item: item)
                        .opacity(isHovered || restricted ? 1 : 0)
                }
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 7, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.hover, value: isHovered)
        .contextMenu { ExtensionContextMenu(item: item) }
    }
}

/// The globe at the end of a row: where the extension may read and change pages, for
/// the focused column's site. Picking "When you click it" leaves it off this site until its
/// button is clicked.
@available(macOS 15.4, *)
private struct SiteAccessMenu: View {
    let item: InstalledExtension
    @Environment(BrowserModel.self) private var browser
    private let library = ExtensionLibrary.shared

    var body: some View {
        let _ = item.actionVersion
        let page = browser.webPage
        let host = page?.url?.host() ?? ""
        let isWeb = ["http", "https"].contains(page?.url?.scheme ?? "")
        let choice = library.siteChoice(of: item, on: host)
        let wants = library.wantsAccess(item, to: page?.url)
        Menu {
            Text("\(item.name) can read and change")
            Picker("Can read and change", selection: Binding(
                get: { choice },
                set: { library.setSiteChoice($0, for: item, on: host, page: page) }
            )) {
                Text("When you click it").tag(ExtensionLibrary.SiteChoice.onClick)
                if isWeb, !host.isEmpty {
                    Text("On \(Self.short(host))").tag(ExtensionLibrary.SiteChoice.thisSite)
                }
                Text("On all sites").tag(ExtensionLibrary.SiteChoice.allSites)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: Self.symbol(choice))
                .font(.system(size: 11))
                .foregroundStyle(wants || choice != .allSites ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(item.name) can read and change: \(Self.title(choice, host: host).lowercased(with: nil))")
    }

    static func symbol(_ choice: ExtensionLibrary.SiteChoice) -> String {
        switch choice {
        case .allSites: "globe"
        case .thisSite: "checkmark.circle"
        case .onClick: "hand.tap"
        }
    }

    static func title(_ choice: ExtensionLibrary.SiteChoice, host: String) -> String {
        switch choice {
        case .allSites: "On all sites"
        case .thisSite: "On \(short(host))"
        case .onClick: "When you click it"
        }
    }

    static func short(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A small accent dot before the text.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 5))
            configuration.title
        }
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
