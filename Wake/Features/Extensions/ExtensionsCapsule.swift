import AppKit
import SwiftUI
import WebKit

/// The toolbar island for extensions: one button per pinned extension (icon, badge,
/// popup) and a menu with the rest. Not shown while nothing is installed; store pages
/// get their own "Add to Wake" button, in the page (`extension-stores.js`).
struct ExtensionsCapsule: View {
    var body: some View {
        if #available(macOS 15.4, *) {
            ExtensionsCapsuleContent()
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionsCapsuleContent: View {
    @Environment(BrowserModel.self) private var browser
    @State private var isMenuOpen = false
    private let library = ExtensionLibrary.shared

    var body: some View {
        let pinned = library.enabled.filter { $0.record.isPinned }
        if !library.items.isEmpty {
            HStack(spacing: 0) {
                ForEach(pinned) { item in
                    ExtensionActionButton(item: item)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                Button { isMenuOpen.toggle() } label: {
                    ToolbarIcon(symbol: "puzzlepiece.extension")
                }
                .buttonStyle(.plain)
                .help("Extensions")
                .accessibilityLabel("Extensions")
                .background(PopupAnchor(id: ExtensionLibrary.menuAnchorID))
                .popover(isPresented: $isMenuOpen, arrowEdge: .bottom) {
                    ExtensionsMenu(close: { isMenuOpen = false })
                        .environment(browser)
                }
            }
            .padding(.horizontal, 4)
            .frame(height: Metrics.capsuleHeight)
            .glassSurface(Capsule())
            .animation(.chrome, value: pinned.map(\.id))
        }
    }
}

/// One extension's toolbar button: its current icon and badge for the focused column.
@available(macOS 15.4, *)
struct ExtensionActionButton: View {
    let item: InstalledExtension
    @Environment(BrowserModel.self) private var browser
    private let library = ExtensionLibrary.shared

    var body: some View {
        let _ = item.actionVersion
        let action = library.action(of: item, in: browser)
        Button {
            library.performAction(item, in: browser)
        } label: {
            ExtensionGlyph(image: action?.icon(for: CGSize(width: 16, height: 16)) ?? item.icon(16), side: 16)
                .frame(width: 32, height: 28)
                .overlay(alignment: .topTrailing) {
                    if let badge = action?.badgeText, !badge.isEmpty {
                        ExtensionBadge(text: badge)
                            .offset(x: -1, y: 1)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(action?.isEnabled == false ? 0.4 : 1)
        .help(action?.label.isEmpty == false ? action!.label : item.name)
        .accessibilityLabel(item.name)
        .background(PopupAnchor(id: item.id))
        .contextMenu {
            ExtensionContextMenu(item: item)
        }
    }
}

@available(macOS 15.4, *)
struct ExtensionContextMenu: View {
    let item: InstalledExtension
    @Environment(BrowserModel.self) private var browser
    private let library = ExtensionLibrary.shared

    var body: some View {
        Text(item.name)
        if item.context?.optionsPageURL != nil {
            Button("Options") { library.openOptions(item) }
        }
        Button(item.record.isPinned ? "Unpin from Toolbar" : "Pin to Toolbar") {
            withAnimation(.chrome) { library.setPinned(item, !item.record.isPinned) }
        }
        Divider()
        Button("Manage Extensions…") { browser.showSettings(.extensions) }
    }
}

/// An extension's icon, or a puzzle piece when it has none.
struct ExtensionGlyph: View {
    let image: NSImage?
    let side: CGFloat

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
        } else {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: side * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: side, height: side)
        }
    }
}

/// The extension's badge text (a count, "ON"), as a small pill on its icon.
///
/// Limitation: WebKit doesn't expose the badge colour an extension sets
/// (`action.setBadgeBackgroundColor`), so badges use Wake's accent.
struct ExtensionBadge: View {
    let text: String

    var body: some View {
        Text(text.prefix(4))
            .font(.system(size: 8.5, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 3.5)
            .frame(minWidth: 13, minHeight: 12)
            .background(Capsule().fill(.tint))
            .overlay(Capsule().stroke(.background.opacity(0.6), lineWidth: 1))
            .fixedSize()
    }
}

/// Gives the library an AppKit view to hang an extension's popup from.
struct PopupAnchor: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        register(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        register(view)
    }

    private func register(_ view: NSView) {
        if #available(macOS 15.4, *) {
            ExtensionLibrary.shared.register(anchor: view, for: id)
        }
    }
}
