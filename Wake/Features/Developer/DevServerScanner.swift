import AppKit
import Observation

/// A local dev server found on one of the usual ports.
struct DevServer: Identifiable, Equatable, Sendable {
    enum Framework: String, Sendable {
        case vite = "Vite", next = "Next.js", storybook = "Storybook", angular = "Angular"
        case django = "Django", rails = "Rails", express = "Express", unknown = "Server"

        /// SF Symbol for the capsule.
        var symbol: String {
            switch self {
            case .vite: "bolt.fill"
            case .next: "triangle.fill"
            case .storybook: "book.closed.fill"
            case .angular: "a.circle.fill"
            case .django, .rails: "server.rack"
            case .express, .unknown: "network"
            }
        }
    }

    let port: Int
    var framework: Framework
    var title: String
    var isRunning: Bool

    var id: Int { port }
    var url: URL { URL(string: "http://localhost:\(port)/")! }
}

/// Polls the usual dev-server ports on localhost and identifies what answers from
/// response headers and the start of the HTML. Servers seen this session stay listed
/// (with a grey dot) after they stop, so restarting one doesn't reshuffle the capsule.
@MainActor
@Observable
final class DevServerScanner {
    static let shared = DevServerScanner()

    static let ports: [Int] = Array(3000...3010) + [4200] + Array(5173...5180) + [6006, 8000, 8080]

    private(set) var servers: [DevServer] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private init() {}

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                // Every 5 seconds while you're in Wake; in the background a server
                // appearing can wait, and 24 probes every 5 seconds add up.
                try? await Task.sleep(for: .seconds(NSApp.isActive ? 5 : 30))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func scan() async {
        let session = session
        let found = await withTaskGroup(of: DevServer?.self) { group in
            for port in Self.ports {
                group.addTask { await Self.probe(port: port, session: session) }
            }
            var found: [Int: DevServer] = [:]
            for await server in group { if let server { found[server.port] = server } }
            return found
        }
        var next = servers.map { server in
            var server = server
            server.isRunning = false
            return found[server.port] ?? server
        }
        for server in found.values where !next.contains(where: { $0.port == server.port }) {
            next.append(server)
        }
        next.sort { $0.port < $1.port }
        if next != servers { servers = next }
    }

    private nonisolated static func probe(port: Int, session: URLSession) async -> DevServer? {
        let url = URL(string: "http://localhost:\(port)/")!
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse else { return nil }
        let html = String(decoding: data.prefix(16_384), as: UTF8.self)
        let framework = identify(http, html: html)
        let title = html.firstMatch(of: #/<title[^>]*>([^<]{1,80})</title>/#).map { String($0.1) } ?? framework.rawValue
        return DevServer(port: port, framework: framework, title: title, isRunning: true)
    }

    private nonisolated static func identify(_ response: HTTPURLResponse, html: String) -> DevServer.Framework {
        let poweredBy = (response.value(forHTTPHeaderField: "X-Powered-By") ?? "").lowercased()
        let server = (response.value(forHTTPHeaderField: "Server") ?? "").lowercased()
        if poweredBy.contains("next") || html.contains("/_next/") || html.contains("__NEXT_DATA__") { return .next }
        if html.contains("/@vite/client") { return .vite }
        if html.lowercased().contains("storybook") { return .storybook }
        if html.contains("ng-version") || html.contains("<app-root") { return .angular }
        if server.contains("wsgiserver") || html.contains("csrfmiddlewaretoken") { return .django }
        if server.contains("puma") || response.value(forHTTPHeaderField: "X-Runtime") != nil { return .rails }
        if poweredBy.contains("express") { return .express }
        return .unknown
    }
}
