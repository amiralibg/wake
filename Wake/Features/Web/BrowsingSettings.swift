import Foundation
import Observation

/// How browsing behaves: where links open, what comes back at launch.
/// Shared, because the trail reads it deep inside page callbacks.
@MainActor
@Observable
final class BrowsingSettings {
    static let shared = BrowsingSettings()

    /// On: a clicked link opens as a new column (the trail). Off: it replaces the page.
    var linksOpenInNewColumn: Bool { didSet { defaults.set(linksOpenInNewColumn, forKey: "browsing.linksInNewColumn") } }
    /// On: a new window resumes your most recent thread. Off: it starts empty.
    var restoresLastThread: Bool { didSet { defaults.set(restoresLastThread, forKey: "browsing.restoreThread") } }
    /// On: the app capsule stays out of the way and slides in at the left edge,
    /// like it does in Zen. Off: it keeps a slim strip beside the pages.
    var capsuleHidesAtEdge: Bool { didSet { defaults.set(capsuleHidesAtEdge, forKey: "browsing.capsuleHides") } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        linksOpenInNewColumn = defaults.object(forKey: "browsing.linksInNewColumn") as? Bool ?? true
        restoresLastThread = defaults.object(forKey: "browsing.restoreThread") as? Bool ?? true
        capsuleHidesAtEdge = defaults.bool(forKey: "browsing.capsuleHides")
    }
}
