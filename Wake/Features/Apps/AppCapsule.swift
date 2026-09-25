import SwiftUI

/// Floating vertical glass capsule on the left: pinned web apps with unread badges,
/// then (below a divider) local dev servers found on the usual ports. While the
/// pointer is over it, a pin button offers to add the current page as an app.
struct AppCapsule: View {
    @Environment(BrowserModel.self) private var browser
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(browser.apps.apps.enumerated()), id: \.element.id) { index, app in
                AppIcon(app: app, isActive: browser.apps.activeID == app.id) {
                    browser.toggleApp(app)
                }
                .help(index < 9 ? "\(app.title) (⌃\(index + 1))" : app.title)
                .contextMenu {
                    Button("Reload") { app.page.reload() }
                    Button("Open in Trail") { browser.trail.open(app.page.url ?? app.url) }
                    Divider()
                    Button("Unpin", role: .destructive) { browser.unpin(app) }
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if let page = pinnablePage, isHovering || browser.devServers.isEmpty {
                PinButton(host: page.host) { browser.pin(page) }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if !browser.devServers.isEmpty {
                if !browser.apps.apps.isEmpty || (pinnablePage != nil && isHovering) {
                    Capsule()
                        .fill(.separator)
                        .frame(width: 20, height: 1)
                }
                ForEach(browser.devServers) { server in
                    DevServerIcon(server: server) { browser.openDevServer(server) }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            Capsule()
                .fill(.separator)
                .frame(width: 20, height: 1)
            MomentsButton()
        }
        .padding(.vertical, 6)
        .frame(width: Metrics.capsuleWidth)
        .glassSurface(Capsule(), vibrantContent: false)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .onHover { inside in withAnimation(.chrome) { isHovering = inside } }
        .animation(.chrome, value: browser.apps.apps.map(\.id))
        .animation(.chrome, value: browser.devServers)
    }

    /// The focused web page, if it isn't an app already.
    private var pinnablePage: BrowserPage? {
        guard let page = browser.webPage, page.url != nil, !browser.apps.isPinned(page.url) else { return nil }
        return page
    }
}

/// Pins the current page as an app in this capsule.
private struct PinButton: View {
    let host: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Pin \(host) here as an app (⇧⌘P)")
        .accessibilityLabel("Pin \(host) as an app")
    }
}

private struct AppIcon: View {
    let app: PinnedApp
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Favicon(url: app.page.faviconURL ?? URL(string: "https://\(app.host)/favicon.ico"), host: app.host, size: 18)
                .frame(width: 30, height: 30)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.primary.opacity(0.1), lineWidth: 0.5))
                .padding(2.5)
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: 10.5, style: .continuous).stroke(.tint, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let badge = app.badge { Badge(count: badge) }
                }
                .scaleEffect(isHovering ? 1.08 : 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.hover) { isHovering = hovering } }
        .accessibilityLabel(app.badge.map { "\(app.title), \($0) unread" } ?? app.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct Badge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 17, minHeight: 17)
            .background(Color(nsColor: .systemRed), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1.5))
            .offset(x: 4, y: -4)
            .transition(.scale.combined(with: .opacity))
    }
}

/// Opens Moments. A dot counts what's waiting: moments resurfacing today, pages
/// that changed, and (in the tint) moments saved on the site you're on.
private struct MomentsButton: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(MomentStore.self) private var store
    @State private var isHovering = false

    var body: some View {
        let now = Date.now
        let moments = store.moments()
        let waiting = moments.filter { MomentRules.isResurfacing($0, now: now) || $0.changedAt != nil }.count
        let relevant = moments.filter { MomentRules.isRelevant($0, host: browser.momentsHost) }.count
        Button {
            relevant > 0 && waiting == 0 ? browser.showMoments(.relevant) : browser.showMoments()
        } label: {
            Image(systemName: browser.isMomentsOpen ? "bookmark.fill" : "bookmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(browser.isMomentsOpen ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: 30, height: 30)
                .overlay(alignment: .topTrailing) {
                    if waiting > 0 || relevant > 0 {
                        Text("\(waiting > 0 ? waiting : relevant)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(waiting > 0 ? AnyShapeStyle(Color(nsColor: .systemOrange)) : AnyShapeStyle(.tint), in: Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
                .scaleEffect(isHovering ? 1.08 : 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.hover) { isHovering = hovering } }
        .help(help(waiting: waiting, relevant: relevant))
        .accessibilityLabel("Moments")
    }

    private func help(waiting: Int, relevant: Int) -> String {
        var parts = ["Moments (⌥⌘B)"]
        if waiting > 0 { parts.append("\(waiting) resurfacing or changed") }
        if relevant > 0, let host = browser.momentsHost { parts.append("\(relevant) saved on \(host)") }
        return parts.joined(separator: " · ")
    }
}
