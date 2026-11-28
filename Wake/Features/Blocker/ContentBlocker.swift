import Foundation
import Observation
import WebKit

/// Built-in ad and tracker blocking: EasyList and EasyPrivacy, converted by
/// `FilterListConverter` and compiled once into a `WKContentRuleList`, which WebKit
/// applies inside the network stack with no JavaScript. Blocked requests never
/// load, so pages use less memory and CPU.
///
/// The compiled list is kept by WebKit's rule-list store, so launches only look it
/// up. The lists are downloaded again once a week.
///
/// Limitation: WebKit doesn't report which requests a rule list blocked, so Wake
/// can't show a per-page count.
@MainActor
@Observable
final class ContentBlocker {
    static let shared = ContentBlocker()

    enum Status: Equatable {
        case off
        case updating
        case ready(rules: Int, updated: Date)
        case failed(String)
    }

    var isEnabled: Bool = UserDefaults.standard.bool(forKey: "blocker.enabled") {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: "blocker.enabled")
            if isEnabled { start() } else { turnOff() }
        }
    }

    /// Sites where nothing is blocked ("example.com" covers its subdomains).
    private(set) var allowedSites: [String] = UserDefaults.standard.stringArray(forKey: "blocker.allowed") ?? []
    private(set) var status: Status = .off

    @ObservationIgnored private var ruleList: WKContentRuleList?
    @ObservationIgnored private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    private static let identifier = "wake.blocker"
    nonisolated private static let lists = [
        URL(string: "https://easylist.to/easylist/easylist.txt")!,
        URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
    ]
    private static let refreshInterval: TimeInterval = 7 * 24 * 3600

    private var lastUpdated: Date? {
        get { UserDefaults.standard.object(forKey: "blocker.updated") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "blocker.updated") }
    }

    private var ruleCount: Int {
        get { UserDefaults.standard.integer(forKey: "blocker.rules") }
        set { UserDefaults.standard.set(newValue, forKey: "blocker.rules") }
    }

    /// Every page configuration registers here; the list is added now if it's
    /// ready, or later when it is.
    func attach(to controller: WKUserContentController) {
        controllers.add(controller)
        if let ruleList { controller.add(ruleList) }
    }

    /// At launch: picks up the compiled list, and refreshes it when it's a week old.
    func start() {
        guard isEnabled else { return }
        Task {
            if let list = try? await WKContentRuleListStore.default().contentRuleList(forIdentifier: Self.identifier) {
                install(list)
                status = .ready(rules: ruleCount, updated: lastUpdated ?? .now)
                if let lastUpdated, Date.now.timeIntervalSince(lastUpdated) < Self.refreshInterval { return }
            }
            update()
        }
    }

    /// Downloads the lists again (or uses the last copy offline) and recompiles.
    func update() {
        guard isEnabled else { return }
        updateTask?.cancel()
        status = .updating
        let allowed = allowedSites
        updateTask = Task {
            let texts = await Self.download()
            guard !Task.isCancelled else { return }
            guard !texts.isEmpty else {
                status = .failed("Couldn't download the filter lists. Check your connection and try again.")
                return
            }
            let (json, count) = await Task.detached(priority: .utility) { () -> (String, Int) in
                let output = FilterListConverter.convert(texts, allowedSites: allowed)
                return (output.json, output.rules.count)
            }.value
            guard !Task.isCancelled, isEnabled else { return }
            do {
                guard let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: Self.identifier, encodedContentRuleList: json) else {
                    status = .failed("WebKit couldn't compile the filter lists.")
                    return
                }
                install(list)
                ruleCount = count
                lastUpdated = .now
                status = .ready(rules: count, updated: .now)
            } catch {
                status = .failed("WebKit couldn't compile the filter lists: \(error.localizedDescription)")
            }
        }
    }

    func isAllowed(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return allowedSites.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Turns blocking off (or back on) for a site. Takes a few seconds to recompile.
    func toggleAllowed(_ url: URL?) {
        guard let host = url?.host()?.lowercased() else { return }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let existing = allowedSites.first(where: { host == $0 || host.hasSuffix("." + $0) }) {
            allowedSites.removeAll { $0 == existing }
        } else {
            allowedSites.append(site)
        }
        UserDefaults.standard.set(allowedSites, forKey: "blocker.allowed")
        update()
    }

    func removeAllowed(_ site: String) {
        allowedSites.removeAll { $0 == site }
        UserDefaults.standard.set(allowedSites, forKey: "blocker.allowed")
        update()
    }

    private func install(_ list: WKContentRuleList) {
        for controller in controllers.allObjects {
            if let ruleList { controller.remove(ruleList) }
            controller.add(list)
        }
        ruleList = list
    }

    private func turnOff() {
        updateTask?.cancel()
        if let ruleList {
            for controller in controllers.allObjects { controller.remove(ruleList) }
        }
        ruleList = nil
        status = .off
        Task { try? await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: Self.identifier) }
    }

    // MARK: Lists

    nonisolated private static var folder: URL {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("Blocker", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Each list fresh from the network, or the last saved copy if that fails.
    nonisolated private static func download() async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            for url in lists {
                group.addTask {
                    let file = folder.appendingPathComponent(url.lastPathComponent)
                    if let (data, response) = try? await URLSession.shared.data(from: url),
                       (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) {
                        try? data.write(to: file, options: .atomic)
                        return text
                    }
                    return try? String(contentsOf: file, encoding: .utf8)
                }
            }
            var texts: [String] = []
            for await text in group { if let text { texts.append(text) } }
            return texts
        }
    }
}
