import SwiftUI

struct DeckSettingsSection: View {
    @Environment(DeckSettings.self) private var deck

    var body: some View {
        @Bindable var deck = deck
        SettingsGroup {
            SettingsRow("sinkAfter", detail: "Untouched tabs sink below the waterline. They stay searchable.") {
                SettingsSegmented(selection: $deck.sinkAfter, options: SinkDelay.allCases, value: { $0 }, label: \.label)
            }
            SettingsDivider()
            SettingsRow("keepAfloat") {
                Toggle("", isOn: $deck.keepActiveAfloat)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow("bottomEdge", detail: "Move the pointer to the bottom of the window to see your threads. ⌘K always opens it.") {
                Toggle("", isOn: $deck.peeksFromBottomEdge)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}
