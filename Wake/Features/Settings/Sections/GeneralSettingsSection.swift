import SwiftUI

struct GeneralSettingsSection: View {
    @Environment(BrowsingSettings.self) private var browsing
    @Environment(BrowserModel.self) private var browser
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = true

    var body: some View {
        @Bindable var browsing = browsing
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Browsing") {
                SettingsRow("linksOpen", detail: "⌘-click opens a column in the background; ⌥-click stays on the page.") {
                    Picker("", selection: $browsing.linksOpenInNewColumn) {
                        Text("In a new column").tag(true)
                        Text("In the same page").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow("newColumnPage") {
                    TextField("Search and the Deck", text: $browsing.newColumnPage)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                SettingsDivider()
                SettingsRow("resumeThread", detail: "New windows pick up where you left off.") {
                    Toggle("", isOn: $browsing.restoresLastThread)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow("shiftScroll", detail: "With a mouse wheel. Off, ⇧-scroll scrolls the page sideways.") {
                    Toggle("", isOn: $browsing.shiftScrollMovesColumns)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow("capsule", detail: "The capsule on the left. Hidden, it slides in when the pointer reaches the window's left edge.") {
                    Picker("", selection: $browsing.capsuleHidesAtEdge) {
                        Text("Always shown").tag(false)
                        Text("At left edge").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SiteWidthsGroup()
            UpdatesGroup()
            SettingsGroup {
                SettingsRow("welcomeTour", detail: "The trail, your look, search and shortcuts, one screen each.") {
                    Button("Show Welcome Tour") {
                        browser.hideSettings()
                        withAnimation(.easeInOut(duration: 0.45)) { onboardingCompleted = false }
                    }
                }
            }
            SettingsGroup {
                SettingsRow(label: "Keyboard shortcuts", detail: "See and change every shortcut, and turn on column mode (⌃W).") {
                    Button("Open Shortcuts") { browser.settingsSection = .shortcuts }
                }
            }
        }
    }
}

/// Minimum column widths by address pattern.
private struct SiteWidthsGroup: View {
    @State private var rules = SiteWidthRules.shared

    var body: some View {
        SettingsGroup(title: "Site widths") {
            SettingsRow(
                "siteWidths",
                detail: "For sites that need room. * matches anything: github.com/* covers all of GitHub. To add the site you're on, choose View ▸ Keep This Width on This Site."
            ) {
                Button("Add Site") { rules.add() }
            }
            ForEach($rules.rules) { $rule in
                SettingsDivider()
                HStack(spacing: 10) {
                    TextField("example.com/*", text: $rule.pattern)
                        .textFieldStyle(.roundedBorder)
                    TextField("Width", value: $rule.minWidth, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("pt").foregroundStyle(.secondary)
                    Button {
                        rules.remove(rule)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                    .accessibilityLabel("Remove \(rule.pattern)")
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
            }
        }
    }
}

/// Wake's version and Sparkle's update settings.
private struct UpdatesGroup: View {
    @State private var updater = AppUpdater.shared

    var body: some View {
        SettingsGroup(title: "Updates") {
            SettingsRow(label: "Wake \(updater.version)", detail: detail) {
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            .settingsAnchor("updates")
            if updater.isAvailable {
                SettingsDivider()
                SettingsRow("autoUpdate", detail: "Once a day. You choose when to install.") {
                    Toggle("", isOn: $updater.automaticallyChecks)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }

    private var detail: String {
        guard updater.isAvailable else { return "Updates are off in this build: it has no update signing key." }
        guard let last = updater.lastChecked else { return "New versions come from GitHub releases." }
        return "Last checked \(last.formatted(.relative(presentation: .named)))."
    }
}
