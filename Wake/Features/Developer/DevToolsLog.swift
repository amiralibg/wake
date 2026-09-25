import Foundation
import Observation

/// A place in a script: where a console message or error came from.
struct SourceLocation: Hashable, Sendable {
    let url: URL
    let line: Int
    let column: Int

    var fileName: String { url.lastPathComponent.isEmpty ? url.host() ?? "" : url.lastPathComponent }

    /// The first frame of a JS stack that points at an http(s) script.
    /// Handles both "at fn (url:1:2)" (Chrome/V8) and "fn@url:1:2" (WebKit) shapes.
    static func firstFrame(in stack: String) -> SourceLocation? {
        for line in stack.split(separator: "\n") {
            guard let match = line.firstMatch(of: #/(https?://[^\s()]+?):(\d+):(\d+)/#),
                  let url = URL(string: String(match.1)),
                  let row = Int(match.2), let column = Int(match.3) else { continue }
            return SourceLocation(url: url, line: row, column: column)
        }
        return nil
    }
}

struct ConsoleEntry: Identifiable, Sendable {
    enum Level: String, Sendable {
        case log, info, debug, warn, error
    }

    let id = UUID()
    let level: Level
    let message: String
    let stack: String?
    let date: Date

    var source: SourceLocation? { stack.flatMap(SourceLocation.firstFrame(in:)) }

    /// React names the failing component in its error text; pick it out when present.
    var component: String? {
        let text = message + "\n" + (stack ?? "")
        return text.firstMatch(of: #/in the <(\w+)> component/#).map { String($0.1) }
            ?? text.firstMatch(of: #/at <?([A-Z]\w+)>? \(/#).map { String($0.1) }
    }
}

struct NetworkEntry: Identifiable, Sendable {
    let id: Int
    let method: String
    let url: URL
    let requestHeaders: [String: String]
    let requestBody: String?
    let startedAt: Date
    var status: Int?
    var duration: TimeInterval?
    var responsePreview: String?
    var error: String?
    var isMocked = false

    var isFailure: Bool { error != nil || (status ?? 0) >= 400 }
    var pathAndQuery: String {
        let query = url.query().map { "?\($0)" } ?? ""
        return url.path() + query
    }

    /// The request as a shell command, for reproducing it outside the browser.
    var curl: String {
        var parts = ["curl", "-X", method, shellQuoted(url.absoluteString)]
        for (name, value) in requestHeaders.sorted(by: { $0.key < $1.key }) {
            parts += ["-H", shellQuoted("\(name): \(value)")]
        }
        if let requestBody, !requestBody.isEmpty { parts += ["--data-raw", shellQuoted(requestBody)] }
        return parts.joined(separator: " ")
    }

    private func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// What developer mode has observed on one page: console, network, HMR, and the
/// mocked routes it's answering itself.
@MainActor
@Observable
final class DevToolsLog {
    enum HMR: Equatable {
        case none
        case connected(String)
        case disconnected(String)
    }

    private(set) var console: [ConsoleEntry] = []
    private(set) var network: [NetworkEntry] = []
    private(set) var hmr: HMR = .none
    private(set) var lastHotUpdate: Date?
    /// Path → JSON body. Matching fetches are answered without touching the network.
    private(set) var mocks: [String: String] = [:]

    private let consoleLimit = 500
    private let networkLimit = 300

    var errorCount: Int { console.filter { $0.level == .error }.count }

    func clearConsole() { console = [] }
    func clearNetwork() { network = [] }

    /// A new document: its requests and messages start fresh. Mocks persist.
    func reset() {
        console = []
        network = []
        hmr = .none
    }

    func setMock(_ body: String?, for path: String) {
        mocks[path] = body
    }

    // MARK: Messages from the page script

    func receive(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "console": addConsole(message)
        case "request": addRequest(message)
        case "response": completeRequest(message)
        case "hmr": updateHMR(message)
        default: break
        }
    }

    private func addConsole(_ message: [String: Any]) {
        let level = ConsoleEntry.Level(rawValue: message["level"] as? String ?? "log") ?? .log
        let entry = ConsoleEntry(level: level, message: message["message"] as? String ?? "", stack: message["stack"] as? String, date: .now)
        console.append(entry)
        if console.count > consoleLimit { console.removeFirst(console.count - consoleLimit) }
    }

    private func addRequest(_ message: [String: Any]) {
        guard let id = message["id"] as? Int,
              let urlString = message["url"] as? String, let url = URL(string: urlString) else { return }
        let entry = NetworkEntry(
            id: id,
            method: message["method"] as? String ?? "GET",
            url: url,
            requestHeaders: message["headers"] as? [String: String] ?? [:],
            requestBody: message["body"] as? String,
            startedAt: .now
        )
        network.append(entry)
        if network.count > networkLimit { network.removeFirst(network.count - networkLimit) }
    }

    private func completeRequest(_ message: [String: Any]) {
        guard let id = message["id"] as? Int, let index = network.lastIndex(where: { $0.id == id }) else { return }
        network[index].status = message["status"] as? Int
        network[index].duration = (message["ms"] as? Double).map { $0 / 1000 }
        network[index].responsePreview = message["preview"] as? String
        network[index].error = message["error"] as? String
        network[index].isMocked = message["mocked"] as? Bool ?? false
    }

    private func updateHMR(_ message: [String: Any]) {
        let kind = message["kind"] as? String ?? "HMR"
        switch message["state"] as? String {
        case "connected": hmr = .connected(kind)
        case "disconnected": hmr = .disconnected(kind)
        case "updated":
            hmr = .connected(kind)
            lastHotUpdate = .now
        default: break
        }
    }
}

/// What the component inspector picked.
struct ComponentPick: Sendable {
    let framework: String?
    let name: String?
    let file: String?
    let line: Int?
    let pageURL: URL?
}
