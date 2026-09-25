import AppKit
import Foundation

/// Opens source files at a line in the editor chosen in Settings.
///
/// Cursor, VS Code and Zed register URL schemes that take `path:line:column`.
/// Limitation: Xcode has no such scheme, and a sandboxed app can't run `xed`, so
/// for Xcode the file opens without jumping to the line.
@MainActor
enum EditorOpener {
    enum Failure: Error {
        case noSource, noProjectFolder
    }

    /// Resolves a console location through its source map to a file in the page's
    /// project, then opens it. If the project has no linked folder yet, asks for one.
    static func open(_ location: SourceLocation) async -> Result<Void, Failure> {
        guard let original = await SourceMapResolver.resolve(location) else {
            // No source map: the served path is often the file itself (Vite).
            return openInProject(relativePath: String(location.url.path().drop(while: { $0 == "/" })),
                                 line: location.line, column: location.column, pageURL: location.url)
        }
        if original.source.hasPrefix("/"), FileManager.default.fileExists(atPath: original.source) {
            openFile(path: original.source, line: original.line, column: original.column)
            return .success(())
        }
        return openInProject(relativePath: original.projectRelativePath, line: original.line,
                             column: original.column, pageURL: location.url)
    }

    /// A component picked with the inspector. React gives absolute paths; Vue and
    /// Svelte give paths relative to the project.
    static func open(_ pick: ComponentPick) -> Result<Void, Failure> {
        guard let file = pick.file else { return .failure(.noSource) }
        if file.hasPrefix("/") {
            openFile(path: file, line: pick.line ?? 1, column: 1)
            return .success(())
        }
        return openInProject(relativePath: file, line: pick.line ?? 1, column: 1, pageURL: pick.pageURL)
    }

    private static func openInProject(relativePath: String, line: Int, column: Int, pageURL: URL?) -> Result<Void, Failure> {
        let store = DevProjectStore.shared
        var project = store.project(for: pageURL) ?? pageURL.map(store.makeProject(for:))
        if project?.folderPath == nil, let unlinked = project {
            project = store.chooseFolder(for: unlinked)
        }
        guard let folder = project?.folderPath else { return .failure(.noProjectFolder) }
        openFile(path: (folder as NSString).appendingPathComponent(relativePath), line: line, column: column)
        return .success(())
    }

    static func openFile(path: String, line: Int, column: Int) {
        let editor = DeveloperSettings.shared.editor
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let scheme: String? = switch editor {
        case .cursor: "cursor"
        case .vscode: "vscode"
        case .zed: "zed"
        case .xcode: nil
        }
        if let scheme, let url = URL(string: "\(scheme)://file\(encoded):\(line):\(column)") {
            NSWorkspace.shared.open(url)
        } else if let xcode = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") {
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: xcode, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
