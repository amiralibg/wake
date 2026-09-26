import SwiftUI

struct SearchSettingsSection: View {
    @Environment(BrowsingSettings.self) private var browsing

    var body: some View {
        @Bindable var browsing = browsing
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Search engine") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Typed words in ⌘K and the address bar search here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    SearchEnginePicker(selection: $browsing.searchEngine)
                    if browsing.searchEngine == .custom {
                        CustomEngineField(template: $browsing.customSearchTemplate)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(14)
                .animation(.chrome, value: browsing.searchEngine)
            }
            SettingsGroup {
                SettingsRow(
                    label: "Search suggestions",
                    detail: "Suggestions from \(browsing.effectiveEngine.suggestionSource) while you type. Off, nothing leaves Wake until you press ↩."
                ) {
                    Toggle("", isOn: $browsing.showsSearchSuggestions)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            BraveKeyGroup()
        }
    }
}

/// Every engine as a card, the chosen one tinted.
struct SearchEnginePicker: View {
    @Binding var selection: SearchEngine
    var engines: [SearchEngine] = SearchEngine.allCases
    var minimumWidth: CGFloat = 180

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 8)], spacing: 8) {
            ForEach(engines) { engine in
                EngineCard(engine: engine, isSelected: selection == engine) { selection = engine }
            }
        }
    }
}

private struct EngineCard: View {
    let engine: SearchEngine
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                EngineIcon(engine: engine, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(engine.tagline)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.primary.opacity(isHovering ? 0.07 : 0.04)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? AnyShapeStyle(.tint.opacity(0.7)) : AnyShapeStyle(.primary.opacity(0.08)), lineWidth: isSelected ? 1.5 : 0.5)
            }
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.hover) { isHovering = hovering } }
        .animation(.hover, value: isSelected)
        .accessibilityLabel(engine.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The engine's favicon, or a symbol for a custom engine.
struct EngineIcon: View {
    let engine: SearchEngine
    var size: CGFloat = 20

    var body: some View {
        if engine == .custom {
            Image(systemName: "link")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(.primary.opacity(0.08), in: .rect(cornerRadius: size / 4, style: .continuous))
        } else {
            Favicon(url: engine.iconURL, host: engine.name, size: size)
        }
    }
}

private struct CustomEngineField: View {
    @Binding var template: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("https://example.com/search?q=%s", text: $template)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            Text(isValid ? "Searches go to \(URL(string: template)?.host() ?? "")." : "Use %s where the search terms go. Until then, DuckDuckGo is used.")
                .font(.system(size: 11))
                .foregroundStyle(isValid ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color(nsColor: .systemOrange)))
        }
    }

    private var isValid: Bool { SearchEngine.isValidTemplate(template) }
}

private struct BraveKeyGroup: View {
    @State private var key = SearchKeyStore.braveAPIKey ?? ""
    @State private var saved = false

    var body: some View {
        SettingsGroup(title: "Results inside ⌘K") {
            SettingsRow(
                label: "Brave Search API key",
                detail: "Optional. Shows real results in the palette without opening a page. Stored in your Keychain."
            ) {
                HStack(spacing: 8) {
                    SecureField("Paste key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit(save)
                    Button(saved ? "Saved" : "Save", action: save)
                        .disabled(saved)
                }
            }
            SettingsDivider()
            SettingsRow(label: "Get a free key") {
                Link("api-dashboard.search.brave.com", destination: URL(string: "https://api-dashboard.search.brave.com/")!)
                    .font(.system(size: 12))
            }
        }
        .onChange(of: key) { saved = false }
    }

    private func save() {
        SearchKeyStore.braveAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        saved = true
    }
}

extension SearchEngine {
    /// Who answers suggestion requests, for the settings copy.
    var suggestionSource: String {
        switch self {
        case .google: "Google"
        case .brave: "Brave"
        case .bing, .yahoo: "Bing"
        case .ecosia: "Ecosia"
        case .duckDuckGo, .startpage, .kagi, .perplexity, .custom: "DuckDuckGo"
        }
    }
}
