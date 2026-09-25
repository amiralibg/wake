import SwiftUI

struct DeckSettingsSection: View {
    @Environment(DeckSettings.self) private var deck

    var body: some View {
        @Bindable var deck = deck
        SettingsGroup {
            SettingsRow(label: "Sink tabs after", detail: "Untouched tabs sink below the waterline. They stay searchable.") {
                SettingsSegmented(selection: $deck.sinkAfter, options: SinkDelay.allCases, value: { $0 }, label: \.label)
            }
            SettingsDivider()
            SettingsRow(label: "Keep playing and unsaved tabs afloat") {
                Toggle("", isOn: $deck.keepActiveAfloat)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Show the Deck from the bottom edge", detail: "Move the pointer to the bottom of the window to see your threads. ⌘K always opens it.") {
                Toggle("", isOn: $deck.peeksFromBottomEdge)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}
