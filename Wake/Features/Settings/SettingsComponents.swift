import SwiftUI

/// A rounded group of rows with hairline separators, like System Settings.
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            VStack(spacing: 0) { content }
                .background(.primary.opacity(0.035), in: .rect(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// Hairline between rows of a SettingsGroup.
struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}

/// Label on the left, control on the right. When the panel is too narrow for both,
/// the control drops below its label instead of pushing the panel wider.
struct SettingsRow<Control: View>: View {
    let label: String
    var detail: String?
    var anchor: SettingsEntry.ID?
    @ViewBuilder let control: Control

    init(label: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control()
    }

    /// A row from the search index: its label and description come from the entry
    /// (`detail` replaces the description when it depends on state), and search can
    /// scroll to it.
    init(_ id: SettingsEntry.ID, detail: String? = nil, @ViewBuilder control: () -> Control) {
        let entry = SettingsEntry.entry(id)
        assert(entry != nil, "No settings entry \(id)")
        self.label = entry?.label ?? id
        self.detail = detail ?? entry?.detail
        self.anchor = id
        self.control = control()
    }

    var body: some View {
        content.settingsAnchor(anchor)
    }

    private var content: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                labels
                    .frame(minWidth: 150, alignment: .leading)
                Spacer(minLength: 8)
                control
            }
            VStack(alignment: .leading, spacing: 10) {
                labels
                control
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 13))
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Native segmented picker sized to its content.
struct SettingsSegmented<Value: Hashable, Option: Identifiable>: View {
    @Binding var selection: Value
    let options: [Option]
    let value: (Option) -> Value
    let label: (Option) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { Text(label($0)).tag(value($0)) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

extension EnvironmentValues {
    /// The setting search or ⌘K just jumped to, outlined for a moment.
    @Entry var settingsHighlight: SettingsEntry.ID?
}

extension View {
    /// Lets search scroll to this view and outline it.
    @ViewBuilder func settingsAnchor(_ id: SettingsEntry.ID?) -> some View {
        if let id {
            modifier(SettingsAnchor(id: id))
        } else {
            self
        }
    }
}

private struct SettingsAnchor: ViewModifier {
    let id: SettingsEntry.ID
    @Environment(\.settingsHighlight) private var highlight

    func body(content: Content) -> some View {
        content
            .background {
                if highlight == id {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.tint.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.tint, lineWidth: 1.5))
                        .padding(2)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.35), value: highlight == id)
            .id(id)
    }
}
