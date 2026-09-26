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
        /// Typed at the console prompt, and what it evaluated to.
        case input, result
    }

    let id = UUID()
    let level: Level
    let message: String
    let stack: String?
    let date: Date
    /// Identical messages in a row are shown once with a count, as in Safari.
    var repeatCount = 1

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
    var responseHeaders: [String: String] = [:]
    var responseSize: Int?
    var error: String?
    var isMocked = false
    /// fetch or xhr.
    var initiator = "fetch"

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
    /// Keep the console and network across navigations.
    var preservesLog = false
    /// When the current document started, to place requests on the waterfall.
    private(set) var documentStart = Date.now

    private let consoleLimit = 500
    private let networkLimit = 300

    private(set) var errorCount = 0
    private(set) var warningCount = 0

    func clearConsole() {
        console = []
        errorCount = 0
        warningCount = 0
    }
    func clearNetwork() { network = [] }

    /// A new document: its requests and messages start fresh. Mocks persist.
    func reset() {
        documentStart = .now
        hmr = .none
        guard !preservesLog else {
            append(ConsoleEntry(level: .info, message: "Navigated to a new page", stack: nil, date: .now))
            return
        }
        clearConsole()
        network = []
    }

    /// Console lines Wake writes itself: prompt input, results, evaluation errors.
    func addLocal(_ level: ConsoleEntry.Level, _ message: String) {
        append(ConsoleEntry(level: level, message: message, stack: nil, date: .now))
    }

    private func append(_ entry: ConsoleEntry) {
        if let last = console.last, last.level == entry.level, last.message == entry.message,
           last.stack == entry.stack, entry.level != .input, entry.level != .result {
            console[console.count - 1].repeatCount += 1
        } else {
            console.append(entry)
            if console.count > consoleLimit { console.removeFirst(console.count - consoleLimit) }
        }
        if entry.level == .error { errorCount += 1 }
        if entry.level == .warn { warningCount += 1 }
    }

    func setMock(_ body: String?, for path: String) {
        mocks[path] = body
    }

    // MARK: Messages from the page script

    func receive(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "console": addConsole(message)
        case "consoleClear": clearConsole()
        case "request": addRequest(message)
        case "response": completeRequest(message)
        case "hmr": updateHMR(message)
        default: break
        }
    }

    private func addConsole(_ message: [String: Any]) {
        let level = ConsoleEntry.Level(rawValue: message["level"] as? String ?? "log") ?? .log
        append(ConsoleEntry(level: level, message: message["message"] as? String ?? "", stack: Self.pageFrames(message["stack"] as? String), date: .now))
    }

    /// Drops Wake's own frames (its console hook is a user script) from a stack, so
    /// the first line is the page's code.
    static func pageFrames(_ stack: String?) -> String? {
        guard let stack else { return nil }
        let frames = stack.split(separator: "\n").filter { !$0.contains("user-script:") }
        return frames.isEmpty ? nil : frames.joined(separator: "\n")
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
            startedAt: .now,
            initiator: message["initiator"] as? String ?? "fetch"
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
        network[index].responseHeaders = message["headers"] as? [String: String] ?? [:]
        network[index].responseSize = message["size"] as? Int
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
