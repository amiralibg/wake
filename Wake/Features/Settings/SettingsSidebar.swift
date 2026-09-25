import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    let onClose: () -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Settings (esc)")
            .accessibilityLabel("Close Settings")
            .padding(.leading, 6)
            .padding(.bottom, 12)

            searchField
                .padding(.bottom, 10)

            ForEach(SettingsSection.allCases.filter { $0.matches(query) }) { section in
                SidebarRow(section: section, isSelected: section == selection) {
                    selection = section
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .onChange(of: query) { _, query in
            // Jump to the first section that matches what's being searched for.
            if !selection.matches(query), let first = SettingsSection.allCases.first(where: { $0.matches(query) }) {
                selection = first
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.primary.opacity(0.07), in: .rect(cornerRadius: 7, style: .continuous))
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? .white.opacity(0.25) : section.tint, in: .rect(cornerRadius: 6, style: .continuous))
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
