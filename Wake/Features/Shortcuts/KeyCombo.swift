import AppKit
import SwiftUI

/// A key plus modifiers, as stored for a command and shown on keycaps.
///
/// `key` is a lowercase character from the US layout ("k", "=", "[") or a named key
/// ("left", "tab", "f5"). Shortcuts recorded on a Persian, Russian or Greek layout
/// are stored by the physical key's US character, which is also what AppKit's menus
/// fall back to when a layout's own letters aren't ASCII.
struct KeyCombo: Codable, Hashable, Sendable {
    struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt8
        static let control = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let shift = Modifiers(rawValue: 4)
        static let command = Modifiers(rawValue: 8)
    }

    var key: String
    var modifiers: Modifiers

    init(_ key: String, _ modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    // MARK: Display

    /// "⌥⌘[" in the order macOS menus use: ⌃⌥⇧⌘, then the key.
    var display: String { modifierSymbols + keySymbol }

    /// Each part on its own keycap: ["⌥", "⌘", "["].
    var parts: [String] {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keySymbol)
        return parts
    }

    private var modifierSymbols: String { parts.dropLast().joined() }

    var keySymbol: String {
        if let named = Self.named[key] { return named.symbol }
        return key.uppercased()
    }

    // MARK: SwiftUI and AppKit

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    var keyEquivalent: KeyEquivalent {
        if let named = Self.named[key] { return named.equivalent }
        return KeyEquivalent(Character(key))
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.command) { result.insert(.command) }
        return result
    }

    /// The combo a key press makes, or nil for keys that can't be a shortcut on their
    /// own (Esc, a bare modifier).
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        if let name = Self.namedKeyCodes[event.keyCode] {
            self.init(name, modifiers)
            return
        }
        guard var key = Self.usKey(for: event) else { return nil }
        // ⇧ with a symbol key: AppKit matches the shifted character ("+" for ⇧=),
        // so store that, the way Zoom In is ⌘+ in every Mac app.
        if modifiers.contains(.shift), !key.first!.isLetter,
           let shifted = event.charactersIgnoringModifiers, shifted.count == 1,
           shifted.unicodeScalars.allSatisfy(\.isASCII), shifted != key {
            key = shifted
            modifiers.remove(.shift)
        }
        self.init(key, modifiers)
    }

    /// From an extension manifest's `commands` (activation key "D" or "Left" plus
    /// AppKit flags).
    init(extensionKey: String, flags: NSEvent.ModifierFlags) {
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let lowered = extensionKey.lowercased()
        let names = ["left": "left", "right": "right", "up": "up", "down": "down", "space": "space",
                     "home": "home", "end": "end", "pageup": "pageUp", "pagedown": "pageDown", "tab": "tab",
                     "delete": "forwardDelete", "insert": "insert", "comma": ",", "period": "."]
        self.init(names[lowered] ?? lowered, modifiers)
    }

    /// Whether this is a key press that matches the combo, on any layout.
    func matches(_ event: NSEvent) -> Bool {
        KeyCombo(event: event) == self
    }

    // MARK: Tables

    private struct Named {
        let symbol: String
        let equivalent: KeyEquivalent
    }

    private static let named: [String: Named] = {
        var table: [String: Named] = [
            "left": Named(symbol: "←", equivalent: .leftArrow),
            "right": Named(symbol: "→", equivalent: .rightArrow),
            "up": Named(symbol: "↑", equivalent: .upArrow),
            "down": Named(symbol: "↓", equivalent: .downArrow),
            "tab": Named(symbol: "⇥", equivalent: .tab),
            "return": Named(symbol: "↩", equivalent: .return),
            "space": Named(symbol: "Space", equivalent: .space),
            "delete": Named(symbol: "⌫", equivalent: .delete),
            "forwardDelete": Named(symbol: "⌦", equivalent: .deleteForward),
            "home": Named(symbol: "↖", equivalent: .home),
            "end": Named(symbol: "↘", equivalent: .end),
            "pageUp": Named(symbol: "⇞", equivalent: .pageUp),
            "pageDown": Named(symbol: "⇟", equivalent: .pageDown),
        ]
        for number in 1...12 {
            let scalar = UnicodeScalar(UInt32(NSF1FunctionKey) + UInt32(number - 1))!
            table["f\(number)"] = Named(symbol: "F\(number)", equivalent: KeyEquivalent(Character(scalar)))
        }
        return table
    }()

    private static let namedKeyCodes: [UInt16: String] = [
        123: "left", 124: "right", 126: "up", 125: "down",
        48: "tab", 36: "return", 76: "return", 49: "space", 51: "delete", 117: "forwardDelete",
        115: "home", 119: "end", 116: "pageUp", 121: "pageDown",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
        98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
    ]

    /// The unshifted character of the key, falling back to its US-layout character
    /// when the current layout's isn't ASCII.
    private static func usKey(for event: NSEvent) -> String? {
        if let base = event.characters(byApplyingModifiers: []), base.count == 1,
           base.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 }) {
            return base.lowercased()
        }
        return usLayout[event.keyCode]
    }

    /// Key codes of the ANSI US layout.
    static let usLayout: [UInt16: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i",
        38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q",
        15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        24: "=", 27: "-", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'",
        43: ",", 47: ".", 44: "/", 50: "`",
    ]
}

/// A row of keycaps for a combo.
struct Keycaps: View {
    let combo: KeyCombo
    var prominent = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(combo.parts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .frame(minWidth: 14)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(prominent ? 0.12 : 0.07), in: .rect(cornerRadius: 5, style: .continuous))
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(.primary.opacity(0.12), lineWidth: 0.5)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo.display)
    }
}
