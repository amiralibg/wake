import SwiftUI
import WebKit

/// Settings ▸ Extensions: get extensions (stores, other browsers, files), keep them
/// updated, and manage each one.
struct ExtensionsSettingsSection: View {
    var body: some View {
        if #available(macOS 15.4, *) {
            ExtensionsSettingsContent()
        } else {
            SettingsGroup {
                SettingsRow(
                    label: "Extensions need macOS 15.4 or later",
                    detail: "Wake runs Chrome and Firefox extensions with WebKit's extension support, which Apple added in macOS 15.4."
                ) { EmptyView() }
            }
        }
    }
}

@available(macOS 15.4, *)
private struct ExtensionsSettingsContent: View {
    @Environment(BrowserModel.self) private var browser
    @State private var isDropTargeted = false
    @State private var importable: [ImportableExtension] = []
    @State private var importing: ImportChoice?
    private let library = ExtensionLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StoresStrip(open: open)

            if !browsersWithExtensions.isEmpty {
                SettingsGroup(title: "Bring your extensions") {
                    ForEach(Array(browsersWithExtensions.enumerated()), id: \.element.name) { index, entry in
                        if index > 0 { SettingsDivider() }
                        BrowserImportRow(name: entry.name, candidates: entry.candidates, installed: installedKeys) {
                            importing = ImportChoice(browser: entry.name, candidates: entry.candidates)
                        }
                    }
                }
            }

            SettingsGroup(title: "More ways") {
                SettingsRow(
                    label: "Add from a file or folder",
                    detail: "A .crx, .xpi or .zip, or an unpacked extension folder. You can also drop one here."
                ) {
                    Button("Choose…") { Extensions.chooseAndInstall() }
                        .disabled(library.isPreparingInstall)
                }
                SettingsDivider()
                SettingsRow(label: "Keep extensions up to date", detail: updateDetail) {
                    HStack(spacing: 8) {
                        if library.isCheckingForUpdates { ProgressView().controlSize(.small) }
                        Button("Check Now") { Task { await library.checkForUpdates() } }
                            .disabled(library.isCheckingForUpdates || !library.items.contains { $0.record.source.storeItem != nil })
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(library.items.isEmpty ? "Installed" : "Installed · \(library.items.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if library.isPreparingInstall || library.isImporting {
                        ProgressView().controlSize(.mini)
                    }
                }
                .padding(.leading, 2)
                if library.items.isEmpty {
                    EmptyExtensions(isTargeted: isDropTargeted)
                } else {
                    VStack(spacing: 8) {
                        ForEach(library.items) { ExtensionCard(item: $0) }
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let file = urls.first(where: \.isFileURL) else { return false }
            library.beginInstall(.file(file))
            return true
        } isTargeted: { isDropTargeted = $0 }
        .task {
            importable = await Task.detached(priority: .userInitiated) { ExtensionImporter.scan() }.value
        }
        .sheet(item: $importing) { choice in
            ExtensionImportSheet(choice: choice, installed: installedKeys)
        }
    }

    private var updateDetail: String {
        let base = "Extensions from the Chrome Web Store, Edge Add-ons and Firefox Add-ons update by themselves every few hours."
        guard let last = library.lastUpdateCheck else { return base }
        let when = last.formatted(.relative(presentation: .named))
        return "\(base) Last checked \(when)\(library.lastUpdateSummary.map { ": \($0)" } ?? "")."
    }

    /// Browsers on this Mac that have extensions, in BrowserCatalog's order.
    private var browsersWithExtensions: [(name: String, candidates: [ImportableExtension])] {
        var order: [String] = []
        var groups: [String: [ImportableExtension]] = [:]
        for candidate in importable {
            if groups[candidate.browser] == nil { order.append(candidate.browser) }
            groups[candidate.browser, default: []].append(candidate)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Store ids and name+version pairs already in Wake, to mark what's there.
    private var installedKeys: Set<String> {
        var keys = Set<String>()
        for item in library.items {
            keys.insert("\(item.name)|\(item.version)")
            if let (_, id) = item.record.source.storeItem { keys.insert(id) }
            item.record.storeAliases.forEach { keys.insert($0) }
        }
        return keys
    }

    private func open(_ url: URL) {
        browser.hideSettings()
        browser.trail.open(url)
    }
}

// MARK: - Stores

@available(macOS 15.4, *)
private struct StoresStrip: View {
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Get extensions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            HStack(spacing: 8) {
                ForEach(ExtensionStore.allCases, id: \.self) { store in
                    StoreTile(store: store) { open(store.home) }
                }
            }
            Text("Find an extension, then click Add to Wake on its page. Chrome's store also serves Arc, Dia and Brave; Firefox's serves Zen.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@available(macOS 15.4, *)
private struct StoreTile: View {
    let store: ExtensionStore
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: .rect(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.primary.opacity(isHovered ? 0.07 : 0.035), in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 0.5))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.hover, value: isHovered)
        .help("Open \(store.title) in a new column")
    }

    private var symbol: String {
        switch store {
        case .chrome: "circle.hexagongrid.fill"
        case .edge: "wave.3.up"
        case .firefox: "flame.fill"
        }
    }

    private var tint: Color {
        switch store {
        case .chrome: Color(red: 0.10, green: 0.45, blue: 0.91)
        case .edge: Color(red: 0.05, green: 0.55, blue: 0.62)
        case .firefox: Color(red: 0.93, green: 0.36, blue: 0.13)
        }
    }

    private var caption: String {
        switch store {
        case .chrome: "Chrome, Arc, Dia, Brave"
        case .edge: "Microsoft Edge"
        case .firefox: "Firefox, Zen"
        }
    }
}

// MARK: - Other browsers

@available(macOS 15.4, *)
private struct BrowserImportRow: View {
    let name: String
    let candidates: [ImportableExtension]
    let installed: Set<String>
    let choose: () -> Void

    var body: some View {
        let new = candidates.filter { !ExtensionImportSheet.isInstalled($0, installed) }
        HStack(spacing: 12) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13))
                Text(new.isEmpty
                     ? "All \(candidates.count) of its extensions are in Wake"
                     : "\(candidates.count) extension\(candidates.count == 1 ? "" : "s")\(new.count < candidates.count ? " · \(new.count) not in Wake yet" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: -5) {
                    ForEach(new.prefix(8)) { candidate in
                        ImportIcon(candidate: candidate, side: 16)
                            .padding(2)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    }
                }
                .padding(.top, 2)
                .opacity(new.isEmpty ? 0 : 1)
                .frame(height: new.isEmpty ? 0 : nil)
            }
            Spacer(minLength: 8)
            if new.isEmpty {
                Label("Imported", systemImage: "checkmark")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                Button("Import…", action: choose)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var appIcon: NSImage {
        let bundleID = candidates.first?.bundleID ?? ""
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
    }
}

struct ImportChoice: Identifiable {
    let browser: String
    let candidates: [ImportableExtension]
    var id: String { browser }
}

/// Pick which of a browser's extensions to copy into Wake.
@available(macOS 15.4, *)
private struct ExtensionImportSheet: View {
    let choice: ImportChoice
    let installed: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var isWorking = false
    @State private var added: Int?

    static func isInstalled(_ candidate: ImportableExtension, _ installed: Set<String>) -> Bool {
        installed.contains("\(candidate.name)|\(candidate.version)") || candidate.storeID.map(installed.contains) == true
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import extensions from \(choice.browser)")
                    .font(.system(size: 15, weight: .semibold))
                Text("Wake copies them from \(choice.browser), nothing is downloaded. Their settings stay behind, and ones from a store keep updating from it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(choice.candidates) { candidate in
                        row(candidate)
                    }
                }
                .padding(8)
            }
            .frame(height: min(CGFloat(choice.candidates.count) * 46 + 16, 380))

            Divider()

            HStack {
                if let added {
                    Label(added == 0 ? "Nothing new to add" : "Added \(added) extension\(added == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                } else {
                    Button(allSelected ? "Select None" : "Select All") {
                        selected = allSelected ? [] : Set(available.map(\.id))
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
                Spacer()
                if added != nil {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button {
                        isWorking = true
                        let chosen = choice.candidates.filter { selected.contains($0.id) }
                        Task {
                            added = await ExtensionLibrary.shared.importExtensions(chosen)
                            isWorking = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isWorking { ProgressView().controlSize(.small) }
                            Text(selected.isEmpty ? "Import" : "Import \(selected.count)")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || isWorking)
                }
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 460)
        .onAppear { selected = Set(available.filter(\.isEnabled).map(\.id)) }
    }

    private var available: [ImportableExtension] {
        choice.candidates.filter { !Self.isInstalled($0, installed) }
    }

    private var allSelected: Bool { !available.isEmpty && selected.count == available.count }

    private func row(_ candidate: ImportableExtension) -> some View {
        let done = Self.isInstalled(candidate, installed)
        return Toggle(isOn: Binding(
            get: { done || selected.contains(candidate.id) },
            set: { on in if on { selected.insert(candidate.id) } else { selected.remove(candidate.id) } }
        )) {
            HStack(spacing: 10) {
                ImportIcon(candidate: candidate)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text([candidate.version.isEmpty ? nil : candidate.version,
                          candidate.profile,
                          candidate.store?.title ?? "Sideloaded",
                          candidate.isEnabled ? nil : "Off in \(candidate.browser)"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if done {
                    Text("In Wake")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(done || isWorking || added != nil)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// A candidate's icon: Chromium's from its folder, Firefox's from inside the `.xpi`.
@available(macOS 15.4, *)
private struct ImportIcon: View {
    let candidate: ImportableExtension
    var side: CGFloat = 26
    @State private var image: NSImage?

    var body: some View {
        ExtensionGlyph(image: image, side: side)
            .task(id: candidate.id) {
                if let icon = candidate.icon {
                    image = icon
                } else if let webExtension = try? await WKWebExtension(resourceBaseURL: candidate.package) {
                    image = webExtension.icon(for: CGSize(width: side * 2, height: side * 2))
                }
            }
    }
}

// MARK: - Installed

private struct EmptyExtensions: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            Text(isTargeted ? "Drop to add" : "No extensions yet")
                .font(.system(size: 13, weight: .medium))
            Text("Ad blockers, password managers, dark mode, translators: most Chrome and Firefox extensions work.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.primary.opacity(isTargeted ? 0.06 : 0.025), in: .rect(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .animation(.hover, value: isTargeted)
    }
}

@available(macOS 15.4, *)
private struct ExtensionCard: View {
    let item: InstalledExtension
    @State private var confirmingRemove = false
    @State private var showsAllAccess = false
    @State private var isApprovingUpdate = false
    private let library = ExtensionLibrary.shared

    var body: some View {
        let access = ExtensionPermissionSummary(item.webExtension).lines
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ExtensionGlyph(image: item.icon(64), side: 36)
                    .saturation(item.record.isEnabled ? 1 : 0)
                    .opacity(item.record.isEnabled ? 1 : 0.6)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(item.version)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        if let label = item.record.source.label {
                            Text(label)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(.primary.opacity(0.07), in: Capsule())
                                .lineLimit(1)
                        }
                    }
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { item.record.isEnabled },
                    set: { on in withAnimation(.chrome) { library.setEnabled(item, on) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }

            if let pending = item.record.pendingUpdateVersion {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                    Text("Version \(pending) is ready and asks for more access.")
                        .font(.system(size: 11.5))
                    Spacer()
                    if isApprovingUpdate { ProgressView().controlSize(.small) }
                    Button("Review…") { reviewUpdate() }
                        .controlSize(.small)
                        .disabled(isApprovingUpdate)
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 7, style: .continuous))
                .padding(.leading, 48)
            }

            if !access.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(showsAllAccess ? access : Array(access.prefix(2))) { line in
                        Label(line.text, systemImage: line.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(line.isBroad ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                    if access.count > 2 {
                        Button(showsAllAccess ? "Show less" : "\(access.count - 2) more…") {
                            withAnimation(.snappy) { showsAllAccess.toggle() }
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
                .padding(.leading, 48)
            }

            let shortcuts = (item.context?.commands ?? []).filter { $0.activationKey?.isEmpty == false }
            if !shortcuts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(shortcuts, id: \.id) { command in
                        HStack(spacing: 8) {
                            Text(Self.shortcut(command))
                                .font(.system(size: 10.5, weight: .medium).monospaced())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(.primary.opacity(0.08), in: .rect(cornerRadius: 4))
                            Text(command.id == "_execute_action" || command.title.isEmpty ? "Open its popup" : command.title)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 48)
            }

            ForEach(item.problems.prefix(3), id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.leading, 48)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                if item.context?.optionsPageURL != nil {
                    Button("Options") { library.openOptions(item) }
                }
                if item.hasToolbarAction {
                    Button(item.record.isPinned ? "Unpin" : "Pin to Toolbar") {
                        withAnimation(.chrome) { library.setPinned(item, !item.record.isPinned) }
                    }
                    .disabled(!item.record.isEnabled)
                }
                Spacer()
                Button("Remove…", role: .destructive) { confirmingRemove = true }
            }
            .controlSize(.small)
            .padding(.leading, 48)
        }
        .padding(14)
        .background(.primary.opacity(0.035), in: .rect(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 0.5))
        .confirmationDialog("Remove “\(item.name)”?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) { withAnimation(.chrome) { library.remove(item) } }
        } message: {
            Text("Its settings and the data it stored are deleted too.")
        }
    }

    /// ⌥⇧D, as macOS writes shortcuts.
    static func shortcut(_ command: WKWebExtension.Command) -> String {
        let flags = command.modifierFlags
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + (command.activationKey ?? "").uppercased()
    }

    private func reviewUpdate() {
        let alert = NSAlert()
        alert.messageText = "Update “\(item.name)”?"
        alert.informativeText = "The new version asks for more access than the one you have. If you don't update, the current version keeps working."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isApprovingUpdate = true
        Task {
            await library.approveUpdate(item)
            isApprovingUpdate = false
        }
    }
}
