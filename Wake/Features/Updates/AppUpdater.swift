import Foundation
import Observation
import Sparkle

/// Updates through Sparkle: checks the appcast attached to the newest GitHub release,
/// verifies the download with the EdDSA key in Info.plist, and installs through
/// Sparkle's XPC installer (Wake is sandboxed).
///
/// Limitations:
/// - Builds without a signing key (`SPARKLE_PUBLIC_ED_KEY` empty) don't check at all.
/// - Releases signed ad hoc (no Developer ID) change their code signature on every
///   build, so macOS may ask whether the updated Wake may keep its data, and
///   Gatekeeper asks before the first launch of a downloaded copy. A Developer ID
///   certificate in the release workflow removes both.
@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    /// False while a check is running, or when updates are off in this build.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    var isAvailable: Bool { controller != nil }

    var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var lastChecked: Date? { controller?.updater.lastUpdateCheckDate }

    private init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        // Sparkle changes this on the main thread.
        // (`.initial` fires inside this initialiser, so not through `shared`.)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    /// Starts Sparkle (and its scheduled checks) at launch.
    func start() {}

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
