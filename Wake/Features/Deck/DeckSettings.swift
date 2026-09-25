import Foundation
import Observation

enum SinkDelay: String, CaseIterable, Identifiable {
    case threeDays, sevenDays, fourteenDays, never

    var id: Self { self }

    var label: String {
        switch self {
        case .threeDays: "3 days"
        case .sevenDays: "7 days"
        case .fourteenDays: "14 days"
        case .never: "Never"
        }
    }

    /// `nil` means tabs never sink.
    var interval: TimeInterval? {
        switch self {
        case .threeDays: 3 * 86_400
        case .sevenDays: 7 * 86_400
        case .fourteenDays: 14 * 86_400
        case .never: nil
        }
    }
}

/// Deck behaviour. The Deck itself arrives in step 4; these values are read there.
@MainActor
@Observable
final class DeckSettings {
    var sinkAfter: SinkDelay { didSet { defaults.set(sinkAfter.rawValue, forKey: "deck.sinkAfter") } }
    var keepActiveAfloat: Bool { didSet { defaults.set(keepActiveAfloat, forKey: "deck.keepActiveAfloat") } }
    /// Reaching the bottom edge of the window raises the Deck island.
    var peeksFromBottomEdge: Bool { didSet { defaults.set(peeksFromBottomEdge, forKey: "deck.peekFromEdge") } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sinkAfter = SinkDelay(rawValue: defaults.string(forKey: "deck.sinkAfter") ?? "") ?? .sevenDays
        keepActiveAfloat = defaults.object(forKey: "deck.keepActiveAfloat") as? Bool ?? true
        peeksFromBottomEdge = defaults.object(forKey: "deck.peekFromEdge") as? Bool ?? true
    }
}
