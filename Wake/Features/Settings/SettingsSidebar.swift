import SwiftUI

/// Sections, and a search field that finds individual settings: results list the
/// matching rows with their section, ↑/↓ move through them (showing each one as you
/// go), ↩ settles on one, Esc clears the search.
struct SettingsSidebar: View {
    @Bindable var browser: BrowserModel

    @State private var selection = 0
    @FocusState private var isSearchFocused: Bool

    private var query: String { browser.settingsQuery }
    private var results: [SettingsEntry] { SettingsSearch.results(for: query, limit: 9) }

    var body: some View {
        let results = results
        VStack(alignment: .leading, spacing: 2) {
            Button(action: browser.hideSettings) {
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

            searchField(resultCount: results.count)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !query.isEmpty {
                        resultsList(results)
                    }
                    ForEach(sections(for: results)) { section in
                        SidebarRow(section: section, isSelected: section == browser.settingsSection && (query.isEmpty || results.isEmpty)) {
                            browser.settingsSection = section
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .task {
            // Settings opens ready to type into the search.
            await Task.yield()
            isSearchFocused = true
        }
        .onChange(of: query) {
            selection = 0
            show(self.results.first)
        }
    }

    private func searchField(resultCount: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search settings", text: $browser.settingsQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .onSubmit { choose(results.indices.contains(selection) ? results[selection] : nil) }
                .onKeyPress(.downArrow) { move(by: 1, count: resultCount) }
                .onKeyPress(.upArrow) { move(by: -1, count: resultCount) }
            if !query.isEmpty {
                Text("\(resultCount)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.primary.opacity(0.07), in: .rect(cornerRadius: 7, style: .continuous))
        .overlay {
            if isSearchFocused {
                RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.tint.opacity(0.5), lineWidth: 2.5)
            }
        }
    }

    @ViewBuilder private func resultsList(_ results: [SettingsEntry]) -> some View {
        if results.isEmpty {
            Text("No settings match “\(query)”.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        } else {
            Text("Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                ResultRow(entry: entry, query: query, isSelected: index == selection) {
                    selection = index
                    choose(entry)
                }
            }
            Divider().padding(.vertical, 8).padding(.horizontal, 6)
        }
    }

    /// While searching, only sections with a match (or whose name matches).
    private func sections(for results: [SettingsEntry]) -> [SettingsSection] {
        guard !query.isEmpty else { return SettingsSection.allCases }
        let withResults = Set(results.map(\.section))
        return SettingsSection.allCases.filter { withResults.contains($0) || $0.matches(query) }
    }

    private func move(by delta: Int, count: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        selection = (selection + delta + count) % count
        show(results[selection])
        return .handled
    }

    /// Shows a result's row without leaving the search field.
    private func show(_ entry: SettingsEntry?) {
        guard let entry else { return }
        browser.settingsSection = entry.section
        browser.settingsFocus = entry.id
    }

    /// ↩ or a click: show it and hand the keyboard to the content, search kept.
    private func choose(_ entry: SettingsEntry?) {
        guard let entry else { return }
        browser.settingsFocus = nil
        show(entry)
        isSearchFocused = false
    }
}

private struct ResultRow: View {
    let entry: SettingsEntry
    let query: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.label)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                Text(entry.path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.label), \(entry.path)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
