import SwiftUI

/// DevTools as a trail column beside the page it inspects: Elements, Console,
/// Network, Sources, Storage and Performance, a Tools menu of page overrides, and a
/// button for WebKit's full Web Inspector (the debugger, Timelines, Layers…).
///
/// Console and fetch/XHR capture need developer mode's hooks; every other pane
/// reads the page on demand and works on any site.
struct DevToolsColumn: View {
    let target: BrowserPage?
    let onClose: () -> Void

    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        VStack(spacing: 0) {
            if let target {
                DevToolsHeader(target: target, onClose: onClose)
                Divider()
                DevToolsContent(target: target, tab: target.inspector.tab)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: appearance.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous).stroke(.primary.opacity(0.1), lineWidth: 0.5))
        .clipShape(.rect(cornerRadius: appearance.cornerRadius, style: .continuous))
        // Cast by a shape: the panes' contents change constantly (see PageCard).
        .background {
            RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        }
    }
}

private struct DevToolsContent: View {
    let target: BrowserPage
    let tab: DevToolsSession.Tab

    var body: some View {
        Group {
            switch tab {
            case .elements: ElementsPane(page: target)
            case .console: ConsolePane(page: target)
            case .network: NetworkPane(page: target)
            case .sources: SourcesPane(page: target)
            case .storage: StoragePane(page: target)
            case .performance: PerformancePane(page: target)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DevToolsHeader: View {
    let target: BrowserPage
    let onClose: () -> Void

    private var session: DevToolsSession { target.inspector }

    var body: some View {
        HStack(spacing: 6) {
            // Titles while they fit; icons (with tooltips) in a narrow column.
            ViewThatFits(in: .horizontal) {
                tabs(showsTitles: true)
                tabs(showsTitles: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HMRBadge(state: target.devtools.hmr, lastUpdate: target.devtools.lastHotUpdate)
            if session.tab == .console || session.tab == .network {
                Button {
                    if session.tab == .console { target.devtools.clearConsole() } else {
                        target.devtools.clearNetwork()
                        session.clearResources()
                    }
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Clear")
            }
            DevToolsMenu(target: target)
            Button {
                if !WebInspector.show(for: target.webView) { showUnavailable() }
            } label: {
                Image(systemName: "safari").font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Open WebKit's Web Inspector: debugger, Timelines, Layers, Graphics (⌥⇧⌘I)")
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderless)
            .help("Close DevTools (⌥⌘I)")
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
    }

    private func tabs(showsTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(DevToolsSession.Tab.allCases) { tab in
                TabButton(tab: tab, badge: badge(for: tab), isSelected: session.tab == tab, showsTitle: showsTitles) {
                    withAnimation(.hover) { session.tab = tab }
                }
            }
        }
        .fixedSize()
    }

    private func badge(for tab: DevToolsSession.Tab) -> (String, Color)? {
        switch tab {
        case .console:
            if target.devtools.errorCount > 0 { return ("\(target.devtools.errorCount)", Color(nsColor: .systemRed)) }
            if target.devtools.warningCount > 0 { return ("\(target.devtools.warningCount)", Color(nsColor: .systemOrange)) }
            return nil
        case .network:
            let failures = target.devtools.network.filter(\.isFailure).count
            return failures > 0 ? ("\(failures)", Color(nsColor: .systemRed)) : nil
        default:
            return nil
        }
    }

    private func showUnavailable() {
        let alert = NSAlert()
        alert.messageText = "Web Inspector isn't available here"
        alert.informativeText = "Turn it on in Settings ▸ Developer and reopen the page, or use Safari ▸ Develop ▸ \(Host.current().localizedName ?? "this Mac") ▸ Wake."
        alert.runModal()
    }
}

/// A tab: icon and title while there's room, icon alone when the column is narrow.
private struct TabButton: View {
    let tab: DevToolsSession.Tab
    let badge: (String, Color)?
    let isSelected: Bool
    var showsTitle = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.symbol).font(.system(size: 10.5, weight: .medium))
                if showsTitle {
                    Text(tab.title).font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                }
                if let badge {
                    Text(badge.0)
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 14)
                        .background(badge.1, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.8)))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.primary.opacity(isHovering ? 0.06 : 0)))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.hover) { isHovering = hovering } }
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Page overrides and one-off actions, like Safari's Develop menu.
private struct DevToolsMenu: View {
    let target: BrowserPage

    private var session: DevToolsSession { target.inspector }

    var body: some View {
        Menu {
            Section("Inspect") {
                Button("Web Inspector") { WebInspector.show(for: target.webView) }
                Button("Web Inspector Console") { WebInspector.show(for: target.webView, panel: .console) }
                Button("Pick Element in Page") {
                    session.tab = .elements
                    session.setPicking(true)
                }
            }
            Section("Emulate") {
                Picker("Appearance", selection: Binding(get: { session.colorScheme }, set: { session.setColorScheme($0) })) {
                    ForEach(DevToolsSession.ColorScheme.allCases) { Text($0.title).tag($0) }
                }
                Picker("User Agent", selection: Binding(get: { session.userAgent }, set: { session.setUserAgent($0) })) {
                    Text("Default (Wake)").tag(UserAgentPreset?.none)
                    Divider()
                    ForEach(UserAgentPreset.allCases) { Text($0.title).tag(Optional($0)) }
                }
                Menu("Preview on Device") {
                    DevicePresetButtons { BrowserModel.active?.openResponsivePreview($0) }
                }
            }
            Section("Page") {
                Toggle("Disable JavaScript", isOn: Binding(get: { session.isJavaScriptDisabled }, set: { session.setJavaScriptDisabled($0) }))
                Toggle("Disable Styles", isOn: Binding(get: { session.stylesDisabled }, set: { session.setStylesDisabled($0) }))
                Toggle("Show Layout Outlines", isOn: Binding(get: { session.outlinesShown }, set: { session.setOutlines($0) }))
                Toggle("Edit Page Text", isOn: Binding(get: { session.designMode }, set: { session.setDesignMode($0) }))
                Toggle("Developer Mode", isOn: Binding(get: { target.isDeveloperMode }, set: {
                    target.developerModeOverride = $0
                    target.reload()
                }))
            }
            Section("Caches") {
                Button("Reload Without Cache") { target.reloadFromOrigin() }
                Button("Empty Caches") { Task { await DevToolsSession.emptyCaches() } }
                Button("Clear Site Data and Reload") { Task { await session.clearSiteData() } }
            }
            Section("Capture") {
                Button("Copy Screenshot") { Task { await session.copyScreenshot() } }
                Button("Copy Full Page as PDF") { Task { await session.copyFullPagePDF() } }
                Button("Copy Page Source") {
                    Task {
                        let source = await session.documentSource()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(source, forType: .string)
                    }
                }
            }
        } label: {
            Image(systemName: "wrench.and.screwdriver").font(.system(size: 11.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tools: emulation, page overrides, caches, screenshots")
    }
}

/// HMR connection state for the dev server's hot-reload socket.
struct HMRBadge: View {
    let state: DevToolsLog.HMR
    let lastUpdate: Date?

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .connected(let kind), .disconnected(let kind):
            let connected = if case .connected = state { true } else { false }
            HStack(spacing: 5) {
                Circle()
                    .fill(connected ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
                    .frame(width: 7, height: 7)
                Text(connected ? kind : "\(kind) offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .help(lastUpdate.map { "Last hot update \($0.formatted(.relative(presentation: .named)))" } ?? "Hot reload")
        }
    }
}
