import AppKit
import Foundation
import Observation

enum DevEnvironment: String, Codable, CaseIterable, Identifiable {
    case local, staging, production

    var id: Self { self }

    var label: String {
        switch self {
        case .local: "Local"
        case .staging: "Staging"
        case .production: "Production"
        }
    }
}

/// A project you develop: its origins per environment and, optionally, its folder on
/// disk (for the git branch and for opening source files in your editor).
struct DevProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var origins: [DevEnvironment: String] = [:]
    /// Security-scoped bookmark to the project folder, so access survives relaunch.
    var folderBookmark: Data?
    var folderPath: String?

    func environment(of url: URL) -> DevEnvironment? {
        guard let origin = Self.origin(of: url) else { return nil }
        return origins.first { Self.origin(of: $0.value) == origin }?.key
    }

    /// The same path and query, on another environment's origin.
    func url(_ url: URL, in environment: DevEnvironment) -> URL? {
        guard let base = origins[environment].flatMap(URL.init(string:)),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = target.scheme
        components.host = target.host
        components.port = target.port
        return components.url
    }

    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host() else { return nil }
        return "\(scheme)://\(host.lowercased()):\(url.port ?? (scheme == "https" ? 443 : 80))"
    }

    static func origin(of string: String) -> String? {
        URL(string: string).flatMap(origin(of:))
    }
}

/// Your projects, saved in preferences.
@MainActor
@Observable
final class DevProjectStore {
    static let shared = DevProjectStore()

    private(set) var projects: [DevProject] = []

    @ObservationIgnored private let key = "developer.projects"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let projects = try? JSONDecoder().decode([DevProject].self, from: data) {
            self.projects = projects
        }
    }

    func project(for url: URL?) -> DevProject? {
        guard let url else { return nil }
        return projects.first { $0.environment(of: url) != nil }
    }

    func save(_ project: DevProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        persist()
    }

    func delete(_ project: DevProject) {
        projects.removeAll { $0.id == project.id }
        persist()
    }

    /// Creates a project for a local page you haven't set up yet.
    func makeProject(for url: URL) -> DevProject {
        let port = url.port.map { ":\($0)" } ?? ""
        var project = DevProject(name: "\(url.host() ?? "localhost")\(port)")
        if let scheme = url.scheme, let host = url.host() {
            project.origins[.local] = "\(scheme)://\(host)\(port)"
        }
        return project
    }

    // MARK: Project folder

    /// Asks for the project folder and saves it with the project.
    func chooseFolder(for project: DevProject) -> DevProject? {
        guard let folder = pickFolder(for: project.name) else { return nil }
        var project = project
        project.folderBookmark = folder.bookmark
        project.folderPath = folder.path
        save(project)
        return project
    }

    /// Asks for a folder and returns a bookmark to it, without saving anything.
    func pickFolder(for name: String) -> (bookmark: Data, path: String)? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Link Folder"
        panel.message = "Choose the folder for \(name). Wake reads its git branch and opens source files from it."
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return nil }
        return (bookmark, url.path)
    }

    /// Runs `body` with access to the project folder (sandboxed apps need the bookmark).
    func withFolder<T>(of project: DevProject, _ body: (URL) -> T?) -> T? {
        guard let bookmark = project.folderBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return body(url)
    }

    /// The checked-out branch, read from `.git/HEAD` (or the commit, when detached).
    func gitBranch(of project: DevProject) -> String? {
        withFolder(of: project) { folder in
            var gitDirectory = folder.appending(path: ".git")
            // Worktrees and submodules have a ".git" file pointing at the real directory.
            if let pointer = try? String(contentsOf: gitDirectory, encoding: .utf8), pointer.hasPrefix("gitdir:") {
                let path = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                gitDirectory = URL(fileURLWithPath: path, relativeTo: folder)
            }
            guard let head = try? String(contentsOf: gitDirectory.appending(path: "HEAD"), encoding: .utf8) else { return nil }
            let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("ref: refs/heads/") { return String(trimmed.dropFirst("ref: refs/heads/".count)) }
            return String(trimmed.prefix(7))
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
