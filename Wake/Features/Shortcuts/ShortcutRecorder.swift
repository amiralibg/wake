import AppKit
import Observation

/// Listens for the next key press in Settings ▸ Shortcuts, ahead of the menus,
/// extensions and the page, so pressing ⌘W to record it doesn't close a column.
@MainActor
@Observable
final class ShortcutRecorder {
    static let shared = ShortcutRecorder()

    enum Target: Equatable {
        /// A new shortcut for this command.
        case command(WakeCommand)
        /// Finding commands by their keys, from the search field.
        case search
    }

    private(set) var target: Target?
    /// Modifiers held right now, shown on the keycap while recording ("⌥⌘…").
    private(set) var heldModifiers: KeyCombo.Modifiers = []
    /// Why the last key wasn't taken. Cleared on the next key.
    private(set) var refusal: String?
    /// A shortcut that clashes with something, waiting for Replace or Cancel.
    private(set) var pending: (command: WakeCommand, combo: KeyCombo, problem: ShortcutProblem)?
    /// The keys pressed while searching by keys.
    var searchCombo: KeyCombo?

    var isRecording: Bool { target != nil }

    @ObservationIgnored private var monitor: Any?

    func record(_ command: WakeCommand) {
        pending = nil
        start(.command(command))
    }

    func recordSearch() {
        searchCombo = nil
        start(.search)
    }

    func cancel() {
        stop()
        pending = nil
    }

    /// Replace: take the keys from whatever had them.
    func confirmPending() {
        guard let pending else { return }
        ShortcutStore.shared.assign(pending.combo, to: pending.command)
        self.pending = nil
    }

    private func start(_ target: Target) {
        stop()
        self.target = target
        refusal = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            MainActor.assumeIsolated { ShortcutRecorder.shared.handle(event) } ? nil : event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        target = nil
        heldModifiers = []
    }

    /// Returns whether the event was used up.
    private func handle(_ event: NSEvent) -> Bool {
        guard let target else { return false }
        if event.type == .flagsChanged {
            heldModifiers = KeyCombo(" ", []).withModifiers(of: event).modifiers
            return false
        }
        let bare = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        // Esc stops listening; it's never a shortcut on its own.
        if event.keyCode == 53 {
            cancel()
            return true
        }
        guard let combo = KeyCombo(event: event) else { return true }

        switch target {
        case .search:
            searchCombo = combo
            stop()
        case .command(let command):
            // ⌫ on its own removes the shortcut.
            if bare, combo.key == "delete" {
                ShortcutStore.shared.set(nil, for: command)
                stop()
                return true
            }
            switch ShortcutStore.shared.problem(with: combo, for: command) {
            case nil:
                ShortcutStore.shared.set(combo, for: command)
                stop()
            case let problem? where problem.canAssign:
                pending = (command, combo, problem)
                stop()
            case let problem?:
                refusal = "\(combo.display): \(problem.message)"
            }
        }
        return true
    }
}

private extension KeyCombo {
    func withModifiers(of event: NSEvent) -> KeyCombo {
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return KeyCombo(key, modifiers)
    }
}
