import SwiftUI

/// Developer tools in the toolbar, shown while the focused page is in developer mode:
/// git branch, hot-reload state, DevTools, responsive preview, component inspector.
struct DevIsland: View {
    @Environment(BrowserModel.self) private var browser
    let page: BrowserPage

    var body: some View {
        HStack(spacing: 2) {
            BranchLabel(page: page)
            if case .none = page.devtools.hmr {} else {
                HMRBadge(state: page.devtools.hmr, lastUpdate: page.devtools.lastHotUpdate)
                    .padding(.horizontal, 6)
            }
            Rectangle().fill(.separator).frame(width: 1, height: 16).padding(.horizontal, 3)
            ToolbarIconButton(symbol: "wrench.and.screwdriver", label: "DevTools (⌥⌘I)") { browser.toggleDevTools() }
                .overlay(alignment: .topTrailing) {
                    if page.devtools.errorCount > 0 {
                        Text("\(min(page.devtools.errorCount, 99))")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Color(nsColor: .systemRed), in: Capsule())
                            .offset(x: -2, y: 1)
                            .allowsHitTesting(false)
                    }
                }
            Menu {
                DevicePresetMenuItems()
            } label: {
                ToolbarIcon(symbol: "iphone")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Responsive preview")
            ToolbarIconButton(
                symbol: page.isInspectingComponents ? "viewfinder.circle.fill" : "viewfinder",
                label: "Inspect components (⌥⌘C)"
            ) { browser.toggleComponentInspector() }
        }
        .padding(.horizontal, 4)
        .frame(height: Metrics.capsuleHeight)
        .glassSurface(Capsule())
    }
}

/// The project's checked-out branch, refreshed every few seconds. Without a linked
/// folder it offers to link one.
private struct BranchLabel: View {
    let page: BrowserPage
    @State private var branch: String?

    var body: some View {
        let store = DevProjectStore.shared
        let project = store.project(for: page.url)
        Group {
            if let project, project.folderPath != nil {
                Label(branch ?? "—", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .help(project.folderPath ?? "")
                    .task(id: project.id) {
                        while !Task.isCancelled {
                            branch = store.gitBranch(of: project)
                            try? await Task.sleep(for: .seconds(3))
                        }
                    }
            } else {
                Button {
                    let base = project ?? page.url.map(store.makeProject(for:))
                    if let base { _ = store.chooseFolder(for: base) }
                } label: {
                    Label("Link folder", systemImage: "folder.badge.plus")
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .help("Link this project's folder to see its git branch and open files in your editor")
            }
        }
    }
}

/// Phones and tablets for the responsive preview (toolbar and Develop menu).
struct DevicePresetMenuItems: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        DevicePresetButtons { browser.openResponsivePreview($0) }
    }
}

struct DevicePresetButtons: View {
    let action: (DevicePreset) -> Void

    var body: some View {
        Section("Phones") {
            ForEach(DevicePreset.phones) { preset in
                Button(preset.menuTitle) { action(preset) }
            }
        }
        Section("Tablets") {
            ForEach(DevicePreset.tablets) { preset in
                Button(preset.menuTitle) { action(preset) }
            }
        }
    }
}
