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
    @ViewBuilder let control: Control

    var body: some View {
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
