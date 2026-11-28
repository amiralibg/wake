import SwiftUI

/// Settings ▸ Shortcuts: every command with its keys. Click a shortcut (or press
/// Space on it) and press new keys; ⌫ removes it, Esc cancels. Clashes with another
/// command or an extension are caught before anything changes.
struct ShortcutsSettingsSection: View {
    @Environment(BrowsingSettings.self) private var browsing
    @State private var store = ShortcutStore.shared
    @State private var recorder = ShortcutRecorder.shared
    @State private var query = ""
    @State private var filter: Filter = .all

    enum Filter: Hashable {
        case all, changed
        case category(WakeCommand.Category)
    }

    var body: some View {
        @Bindable var browsing = browsing
        VStack(alignment: .leading, spacing: 16) {
            searchBar
            filters

            if let pending = recorder.pending {
                ConflictBanner(command: pending.command, combo: pending.combo, problem: pending.problem)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if commandsShown.isEmpty, filter != .changed || !query.isEmpty || recorder.searchCombo != nil {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            }

            ForEach(WakeCommand.Category.allCases) { category in
                let commands = commandsShown.filter { $0.category == category }
                if !commands.isEmpty {
                    SettingsGroup(title: category.title) {
                        ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                            if index > 0 { SettingsDivider() }
                            ShortcutRow(command: command)
                        }
                    }
                }
            }

            if isUnfiltered {
                SettingsGroup(title: "Keyboard") {
                    SettingsRow("columnMode") {
                        Toggle("", isOn: $browsing.columnModeKeyEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    ForEach(fixedRows, id: \.0) { row in
                        SettingsDivider()
                        FixedShortcutRow(title: row.0, keys: row.1)
                    }
                }
                ExtensionShortcutsGroup()

                HStack {
                    Text("Wake's shortcuts win over a page's and an extension's. macOS's own (⌘Q, ⌘Tab, ⌘Space) can't be changed.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Restore Defaults") { withAnimation(.snappy) { store.resetAll() } }
                        .disabled(store.changedCount == 0)
                }
            }
        }
        .animation(.snappy, value: recorder.pending?.combo)
        .animation(.snappy, value: filter)
        .onDisappear { recorder.cancel() }
    }

    // MARK: Search and filters

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let combo = recorder.searchCombo {
                    Keycaps(combo: combo, prominent: true)
                    Button {
                        recorder.searchCombo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear keys")
                    Spacer(minLength: 0)
                } else if recorder.target == .search {
                    Text(recorder.heldModifiers.isEmpty ? "Press the keys to find…" : "\(KeyCombo("", recorder.heldModifiers).display)…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tint)
                    Spacer(minLength: 0)
                } else {
                    TextField("Search commands", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))

            Button {
                if recorder.target == .search { recorder.cancel() } else { query = ""; recorder.recordSearch() }
            } label: {
                Label(recorder.target == .search ? "Cancel" : "Find by Keys", systemImage: "keyboard")
            }
            .help("Press a shortcut to see what it does")
        }
    }

    private var filters: some View {
        HStack(spacing: 6) {
            chip("All", .all)
            chip(store.changedCount > 0 ? "Changed \(store.changedCount)" : "Changed", .changed)
            Divider().frame(height: 14)
            ForEach(WakeCommand.Category.allCases) { category in
                chip(category.shortTitle, .category(category))
            }
        }
    }

    private func chip(_ title: String, _ value: Filter) -> some View {
        let selected = filter == value
        return Button(title) { filter = value }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.07)), in: .capsule)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var isUnfiltered: Bool { filter == .all && query.isEmpty && recorder.searchCombo == nil }

    private var commandsShown: [WakeCommand] {
        var commands = WakeCommand.allCases
        switch filter {
        case .all: break
        case .changed: commands = commands.filter(store.isChanged)
        case .category(let category): commands = commands.filter { $0.category == category }
        }
        if let combo = recorder.searchCombo {
            return commands.filter { store.combo(for: $0) == combo }
        }
        let words = SettingsSearch.tokens(query)
        guard !words.isEmpty else { return commands }
        return commands.filter {
            SettingsSearch.score(words, label: $0.title, keywords: $0.keywords + [store.combo(for: $0)?.display ?? ""], context: [$0.category.title], detail: nil) != nil
        }
    }

    private var emptyText: String {
        if let combo = recorder.searchCombo {
            if let fixed = ShortcutStore.fixed.first(where: { $0.combos.contains(combo) }) { return "\(combo.display) is Wake's key for \(fixed.name)." }
            if let reserved = ShortcutStore.reserved[combo] { return "\(combo.display) is macOS's key for \(reserved)." }
            return "Nothing uses \(combo.display)."
        }
        return filter == .changed ? "You haven't changed any shortcuts." : "No commands match “\(query)”."
    }

    private var fixedRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Go to column 1–8", "⌘1 … ⌘8"),
            ("Show pinned app 1–9", "⌃1 … ⌃9"),
            ("Previous / next column with a mouse wheel", "⇧ scroll"),
        ]
        if browsing.columnModeKeyEnabled {
            rows += [
                ("In column mode: focus · move · jump", "h l  H L  1–9"),
                ("In column mode: width · close · new · done", "< > =  x  n  esc"),
            ]
        }
        return rows
    }
}

extension WakeCommand.Category {
    var shortTitle: String {
        switch self {
        case .threads: "Threads"
        case .moments: "Moments"
        default: title
        }
    }
}

// MARK: - Rows

private struct ShortcutRow: View {
    let command: WakeCommand
    @State private var store = ShortcutStore.shared
    @State private var recorder = ShortcutRecorder.shared

    private var isRecording: Bool { recorder.target == .command(command) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(command.title).font(.system(size: 13))
                if store.isChanged(command) {
                    Circle().fill(.tint).frame(width: 5, height: 5)
                        .help("Changed from \(command.defaultCombo?.display ?? "none")")
                        .accessibilityLabel("Changed")
                }
                Spacer(minLength: 8)
                if store.isChanged(command), !isRecording {
                    iconButton("arrow.uturn.backward", help: "Restore \(command.defaultCombo?.display ?? "no shortcut")") {
                        withAnimation(.snappy) { store.reset(command) }
                    }
                }
                if store.combo(for: command) != nil, !isRecording {
                    iconButton("minus.circle", help: "Remove shortcut") {
                        withAnimation(.snappy) { store.set(nil, for: command) }
                    }
                }
                recordButton
            }
            if isRecording, let refusal = recorder.refusal {
                Text(refusal)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 38)
        .settingsAnchor("shortcut.\(command.rawValue)")
        .animation(.snappy, value: isRecording)
        .animation(.snappy, value: recorder.refusal)
    }

    private var recordButton: some View {
        Button {
            isRecording ? recorder.cancel() : recorder.record(command)
        } label: {
            Group {
                if isRecording {
                    Text(recorder.heldModifiers.isEmpty ? "Press keys…" : "\(KeyCombo("", recorder.heldModifiers).display)…")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])))
                } else if let combo = store.combo(for: command) {
                    Keycaps(combo: combo)
                } else {
                    Text("Record")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.18), lineWidth: 0.5))
                }
            }
            .frame(minWidth: 90, alignment: .trailing)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press the new keys. ⌫ removes the shortcut, Esc cancels." : "Click to change")
        .accessibilityLabel(isRecording ? "Recording shortcut for \(command.title)" : "\(command.title): \(store.combo(for: command)?.display ?? "no shortcut")")
        .accessibilityHint("Press to record a new shortcut")
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct FixedShortcutRow: View {
    let title: String
    let keys: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Text(keys)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.07), in: .rect(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }
}

/// "⇧⌘N is already used by New Thread": Replace takes it, Cancel leaves both alone.
private struct ConflictBanner: View {
    let command: WakeCommand
    let combo: KeyCombo
    let problem: ShortcutProblem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Keycaps(combo: combo, prominent: true)
                    Text("for “\(command.title)”").font(.system(size: 12, weight: .medium))
                }
                Text(problem.message + (problem.canAssign ? replaceNote : ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Cancel") { ShortcutRecorder.shared.cancel() }
                .keyboardShortcut(.cancelAction)
            Button(isTakenByCommand ? "Replace" : "Use Anyway") { withAnimation(.snappy) { ShortcutRecorder.shared.confirmPending() } }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.orange.opacity(0.35), lineWidth: 0.5))
    }

    private var isTakenByCommand: Bool {
        if case .takenBy = problem { return true }
        return false
    }

    private var replaceNote: String {
        if case .takenBy(let other) = problem { return " Replace removes it from “\(other.title)”." }
        return ""
    }
}

/// Extensions' own shortcuts (their manifest `commands`), read-only for now.
private struct ExtensionShortcutsGroup: View {
    var body: some View {
        if #available(macOS 15.4, *) {
            let shortcuts = ExtensionLibrary.shared.commandShortcuts
            if !shortcuts.isEmpty {
                SettingsGroup(title: "Extensions") {
                    ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                        if index > 0 { SettingsDivider() }
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(shortcut.title.isEmpty ? shortcut.extensionName : shortcut.title).font(.system(size: 13))
                                Text(shortcut.extensionName).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let owner = ShortcutStore.shared.command(for: shortcut.combo) {
                                Text("Wake uses it for \(owner.title)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                            Keycaps(combo: shortcut.combo)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                    }
                }
            }
        }
    }
}
