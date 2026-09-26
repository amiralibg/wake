import Foundation
import Observation

enum CodeEditor: String, CaseIterable, Identifiable {
    case cursor, vscode, zed, xcode

    var id: Self { self }

    var label: String {
        switch self {
        case .cursor: "Cursor"
        case .vscode: "VS Code"
        case .zed: "Zed"
        case .xcode: "Xcode"
        }
    }
}

/// Developer-mode preferences. Shared, because pages consult it as they navigate.
@MainActor
@Observable
final class DeveloperSettings {
    static let shared = DeveloperSettings()

    var editor: CodeEditor { didSet { defaults.set(editor.rawValue, forKey: "developer.editor") } }
    var autoEnableForLocalhost: Bool { didSet { defaults.set(autoEnableForLocalhost, forKey: "developer.autoLocalhost") } }
    /// Watch the usual dev-server ports and list what's running in the app capsule.
    var scansPorts: Bool { didSet { defaults.set(scansPorts, forKey: "developer.scanPorts") } }
    /// WebKit's Web Inspector, and "Inspect Element" in the page's context menu.
    /// Applies to pages opened after the change.
    var webInspectorEnabled: Bool { didSet { defaults.set(webInspectorEnabled, forKey: "developer.webInspector") } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        editor = CodeEditor(rawValue: defaults.string(forKey: "developer.editor") ?? "") ?? .cursor
        autoEnableForLocalhost = defaults.object(forKey: "developer.autoLocalhost") as? Bool ?? true
        scansPorts = defaults.object(forKey: "developer.scanPorts") as? Bool ?? true
        webInspectorEnabled = defaults.object(forKey: "developer.webInspector") as? Bool ?? true
    }
}
