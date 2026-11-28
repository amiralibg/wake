import AppKit
import Observation

/// The keys each command uses: its default unless you changed it in Settings.
///
/// Changes are saved as JSON under `shortcuts.overrides`, which `BrowserCommands`
/// also watches through `@AppStorage` so the menu bar rebuilds when one changes.
@MainActor
@Observable
final class ShortcutStore {
    static let shared = ShortcutStore()
    static let defaultsKey = "shortcuts.overrides"

    /// A command missing here uses its default. One mapped to nil has no shortcut.
    private(set) var overrides: [WakeCommand: KeyCombo?] = [:]

    private init() {
        guard let json = UserDefaults.standard.string(forKey: Self.defaultsKey),
              let data = json.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: KeyCombo?].self, from: data) else { return }
        for (id, combo) in stored {
            if let command = WakeCommand(rawValue: id) { overrides[command] = combo }
        }
    }

    func combo(for command: WakeCommand) -> KeyCombo? {
        if let override = overrides[command] { return override }
        return command.defaultCombo
    }

    func isChanged(_ command: WakeCommand) -> Bool { overrides[command] != nil }

    var changedCount: Int { overrides.count }

    func set(_ combo: KeyCombo?, for command: WakeCommand) {
        if combo == command.defaultCombo {
            overrides[command] = nil
        } else {
            overrides[command] = .some(combo)
        }
        save()
    }

    /// Gives `combo` to `command`, taking it from whichever command had it.
    func assign(_ combo: KeyCombo, to command: WakeCommand) {
        for other in WakeCommand.allCases where other != command && self.combo(for: other) == combo {
            set(nil, for: other)
        }
        set(combo, for: command)
    }

    func reset(_ command: WakeCommand) {
        overrides[command] = nil
        save()
    }

    func resetAll() {
        overrides = [:]
        save()
    }

    /// The command a combo runs, if any.
    func command(for combo: KeyCombo) -> WakeCommand? {
        WakeCommand.allCases.first { self.combo(for: $0) == combo }
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(stored), let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: Self.defaultsKey)
    }
}

// MARK: - Checking a new shortcut

/// Why a combo can't be used, or what else already uses it.
enum ShortcutProblem: Equatable {
    /// Can't be used at all.
    case refused(String)
    /// Another Wake command has it; assigning moves it.
    case takenBy(WakeCommand)
    /// One of Wake's fixed keys, like ⌘1–⌘8.
    case fixed(String)
    /// An extension's `commands` entry. Wake's menus win over extensions.
    case extensionCommand(String)

    var message: String {
        switch self {
        case .refused(let reason): reason
        case .takenBy(let command): "Already used by “\(command.title)”."
        case .fixed(let name): "Wake uses this for \(name)."
        case .extensionCommand(let name): "\(name) uses this too. Wake's shortcut will win."
        }
    }

    /// Whether you can go ahead anyway.
    var canAssign: Bool {
        switch self {
        case .refused, .fixed: false
        case .takenBy, .extensionCommand: true
        }
    }
}

extension ShortcutStore {
    /// Keys Wake never takes: macOS and text editing need them.
    static let reserved: [KeyCombo: String] = [
        KeyCombo("q", .command): "Quit",
        KeyCombo("h", .command): "Hide Wake",
        KeyCombo("h", [.command, .option]): "Hide Others",
        KeyCombo("m", .command): "Minimize",
        KeyCombo("c", .command): "Copy",
        KeyCombo("v", .command): "Paste",
        KeyCombo("x", .command): "Cut",
        KeyCombo("a", .command): "Select All",
        KeyCombo("z", .command): "Undo",
        KeyCombo("z", [.command, .shift]): "Redo",
        KeyCombo("v", [.command, .option, .shift]): "Paste and Match Style",
        KeyCombo("f", [.command, .control]): "Full Screen",
        KeyCombo("`", .command): "switching windows",
        KeyCombo("tab", .command): "switching apps",
        KeyCombo("space", .command): "Spotlight",
        KeyCombo("space", .control): "switching input sources",
        KeyCombo("space", [.command, .control]): "Emoji & Symbols",
        KeyCombo("q", [.command, .control]): "Lock Screen",
        KeyCombo("3", [.command, .shift]): "screenshots",
        KeyCombo("4", [.command, .shift]): "screenshots",
        KeyCombo("5", [.command, .shift]): "screenshots",
        KeyCombo("?", .command): "Help",
    ]

    /// Fixed shortcuts that aren't commands of their own, shown in Settings and checked
    /// for clashes.
    static var fixed: [(name: String, keys: String, combos: [KeyCombo])] {
        var list: [(String, String, [KeyCombo])] = [
            ("Column 1–8", "⌘1 … ⌘8", (1...8).map { KeyCombo("\($0)", .command) }),
            ("pinned app 1–9", "⌃1 … ⌃9", (1...9).map { KeyCombo("\($0)", .control) }),
        ]
        if BrowsingSettings.shared.columnModeKeyEnabled {
            list.append(("column mode", "⌃W", [KeyCombo("w", .control)]))
        }
        return list
    }

    /// What stands in the way of giving `combo` to `command`, most serious first.
    func problem(with combo: KeyCombo, for command: WakeCommand) -> ShortcutProblem? {
        let mods = combo.modifiers
        let isFunctionKey = combo.key.count > 1 && combo.key.hasPrefix("f")
        if !mods.contains(.command), !mods.contains(.control), !isFunctionKey {
            // ⌥ alone types accented letters (⌥e) and moves by word (⌥←) in text fields.
            return .refused(mods.contains(.option)
                ? "⌥ on its own types special characters and moves by word. Add ⌘ or ⌃."
                : "Add ⌘ or ⌃, or it would take the key from typing.")
        }
        if let name = Self.reserved[combo] {
            return .refused("macOS uses this for \(name).")
        }
        for entry in Self.fixed where entry.combos.contains(combo) {
            return .fixed(entry.name)
        }
        if let other = self.command(for: combo), other != command {
            return .takenBy(other)
        }
        if #available(macOS 15.4, *), let name = ExtensionLibrary.shared.commandName(for: combo) {
            return .extensionCommand(name)
        }
        return nil
    }
}
