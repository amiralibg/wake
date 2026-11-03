import AppKit
import Foundation

/// Opening local files the way other browsers do: any path just works, with the
/// images and styles around it.
///
/// Wake stays sandboxed and reads files through a read-only entitlement for the whole
/// disk (`project.yml`). macOS still asks once before Wake reads Documents, Desktop,
/// Downloads or a removable drive, as it does for any browser.
///
/// Limitation: `fetch()` of a local file stays blocked, because WebKit treats each
/// file as its own origin. Safari behaves the same way.
@MainActor
enum LocalFileAccess {
    /// What to pass as `allowingReadAccessTo`. A page may refer to anything around it
    /// (`../css/a.css`), so this is wide: WebKit gives the page's web content process
    /// read access to all of it. Scripts in a local page still can't read other files.
    static func readAccessRoot(for file: URL) -> URL {
        let home = URL(filePath: URLInput.realHomeDirectory, directoryHint: .isDirectory)
        let path = file.standardizedFileURL.path
        return path.hasPrefix(home.path + "/") ? home : URL(filePath: "/", directoryHint: .isDirectory)
    }

    /// File ▸ Open File: returns the file to show. A chosen folder opens its index
    /// page, or asks which of its files to open.
    static func chooseFileToOpen() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        return isDirectory ? page(in: url) : url
    }

    private static func page(in folder: URL) -> URL? {
        for name in ["index.html", "index.htm"] {
            let candidate = folder.appending(path: name)
            if FileManager.default.isReadableFile(atPath: candidate.path) { return candidate }
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Open"
        panel.message = "This folder has no index page. Choose the file to open."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
