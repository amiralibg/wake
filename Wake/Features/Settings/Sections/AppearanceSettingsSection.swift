import SwiftUI

struct AppearanceSettingsSection: View {
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        @Bindable var appearance = appearance
        VStack(alignment: .leading, spacing: 16) {
            AppearancePreview()

            ThemePresetPicker()
                .settingsAnchor("themePreset")

            SettingsGroup {
                SettingsRow("theme") {
                    HStack(spacing: 14) {
                        ForEach(ThemePreference.allCases) { theme in
                            ThemeSwatch(theme: theme, isSelected: appearance.theme == theme) {
                                appearance.theme = theme
                            }
                        }
                    }
                }
                SettingsDivider()
                SettingsRow("accent") {
                    HStack(spacing: 10) {
                        ForEach(AccentChoice.allCases) { accent in
                            AccentDot(accent: accent, isSelected: appearance.accent == accent) {
                                appearance.accent = accent
                            }
                        }
                    }
                }
                SettingsDivider()
                SettingsRow("glass") {
                    SettingsSegmented(selection: $appearance.glass, options: GlassStrength.allCases, value: { $0 }, label: \.label)
                        .disabled(appearance.backdrop == .solid)
                }
                SettingsDivider()
                SettingsRow("backdrop", detail: appearance.backdrop == .solid ? "No blur behind the window: lightest on the GPU and battery." : nil) {
                    SettingsSegmented(selection: $appearance.backdrop, options: BackdropStyle.allCases, value: { $0 }, label: \.label)
                }
                SettingsDivider()
                SettingsRow("motion") {
                    SettingsSegmented(selection: $appearance.motion, options: MotionStyle.allCases, value: { $0 }, label: \.label)
                }
            }

            SettingsGroup(title: "Trail layout") {
                SettingsRow("gap") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            gapPresets
                            gapSlider
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            gapPresets
                            gapSlider
                        }
                    }
                }
                SettingsDivider()
                SettingsRow("cardStyle") {
                    SettingsSegmented(selection: $appearance.cardStyle, options: CardStyle.allCases, value: { $0 }, label: \.label)
                }
                SettingsDivider()
                SettingsRow("cornerRadius") {
                    SettingsSegmented(selection: $appearance.cornerRadius, options: CornerRadiusOption.allCases, value: \.rawValue, label: \.label)
                }
                SettingsDivider()
                SettingsRow("pageWidth") {
                    SettingsSegmented(selection: $appearance.pageWidth, options: PageWidth.allCases, value: { $0 }, label: \.label)
                }
            }

            ToolbarButtonsGroup()
            SiteStylesGroup()
        }
    }
}

private extension AppearanceSettingsSection {
    var gapPresets: some View {
        @Bindable var appearance = appearance
        return SettingsSegmented(selection: $appearance.gap, options: GapPreset.allCases, value: \.rawValue, label: \.label)
    }

    var gapSlider: some View {
        @Bindable var appearance = appearance
        return HStack(spacing: 8) {
            Slider(value: $appearance.gap, in: 0...48, step: 2)
                .controlSize(.small)
                .frame(width: 90)
                .accessibilityLabel("Gap in points")
            Text("\(Int(appearance.gap)) px")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: ThemePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(bar).frame(width: 36, height: 6)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(panel)
                }
                .padding(6)
                .frame(width: 74, height: 46)
                .background(background, in: .rect(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.2)), lineWidth: isSelected ? 2 : 0.5)
                }
                Text(theme.label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: AnyShapeStyle {
        switch theme {
        case .light: AnyShapeStyle(Color(white: 0.91))
        case .dark: AnyShapeStyle(Color(white: 0.17))
        case .auto: AnyShapeStyle(LinearGradient(colors: [Color(white: 0.91), Color(white: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var bar: Color { theme == .dark ? Color(white: 0.28) : .white }
    private var panel: Color {
        switch theme {
        case .light: .white
        case .dark, .auto: Color(white: 0.23)
        }
    }
}

private struct AccentDot: View {
    let accent: AccentChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(accent.color)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.5))
                .padding(3)
                .overlay {
                    if isSelected { Circle().stroke(accent.color, lineWidth: 1.5) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(accent.label)
        .accessibilityLabel(accent.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Complete looks, one click each.
private struct ThemePresetPicker: View {
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Look").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if appearance.preset == nil {
                    Text("Custom").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 2)
            HStack(spacing: 10) {
                ForEach(ThemePreset.allCases) { preset in
                    Button {
                        withAnimation(.smooth) { appearance.apply(preset) }
                    } label: {
                        VStack(spacing: 5) {
                            PresetSwatch(preset: preset)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(appearance.preset == preset ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.15)),
                                                      lineWidth: appearance.preset == preset ? 2 : 0.5)
                                }
                            Text(preset.label)
                                .font(.system(size: 11, weight: appearance.preset == preset ? .semibold : .regular))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.label) look")
                    .accessibilityAddTraits(appearance.preset == preset ? .isSelected : [])
                }
            }
        }
    }
}

/// A tiny window in the preset's colours: backdrop, two cards, the focused one ringed or shadowed.
private struct PresetSwatch: View {
    let preset: ThemePreset

    var body: some View {
        let dark = preset.theme == .dark
        let ground: Color = dark ? Color(white: 0.13) : Color(white: 0.9)
        let card: Color = dark ? Color(white: 0.24) : .white
        ZStack {
            ground
            if preset.backdrop == .gradient || preset.backdrop == .tinted {
                LinearGradient(colors: [preset.accent.color.opacity(0.45), preset.accent.color.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            HStack(spacing: max(2, preset.gap / 5)) {
                RoundedRectangle(cornerRadius: preset.cornerRadius / 4, style: .continuous)
                    .fill(card)
                    .shadow(color: .black.opacity(preset.cardStyle == .floating ? 0.3 : 0), radius: 3, y: 2)
                    .overlay {
                        if preset.cardStyle != .floating {
                            RoundedRectangle(cornerRadius: preset.cornerRadius / 4, style: .continuous).stroke(preset.accent.color, lineWidth: 1.2)
                        }
                    }
                RoundedRectangle(cornerRadius: preset.cornerRadius / 4, style: .continuous).fill(card.opacity(0.8))
            }
            .padding(7)
        }
        .frame(width: 84, height: 54)
        .clipShape(.rect(cornerRadius: 9, style: .continuous))
    }
}

/// Which buttons the toolbar's actions island shows.
private struct ToolbarButtonsGroup: View {
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        SettingsGroup(title: "Toolbar") {
            SettingsRow("toolbarButtons", detail: appearance.toolbarButtons.isEmpty ? "No buttons: the island is hidden. Every action still has its shortcut and ⌘K." : nil) {
                Button("Reset") { appearance.toolbarButtons = ToolbarButton.defaults }
                    .disabled(appearance.toolbarButtons == ToolbarButton.defaults)
            }
            FlowChips(items: ToolbarButton.allCases) { button in
                let on = appearance.toolbarButtons.contains(button)
                Button {
                    withAnimation(.snappy) { appearance.toggle(button) }
                } label: {
                    Label(button.label, systemImage: button.symbol)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.07)), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

/// Wrapping row of chips.
private struct FlowChips<Item: Hashable, Chip: View>: View {
    let items: [Item]
    @ViewBuilder let chip: (Item) -> Chip

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { chip($0) }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: [Int] = []
        var x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append((current, y, x - spacing, height))
                y += height + spacing
                current = []
                x = 0
                height = 0
            }
            current.append(index)
            x += size.width + spacing
            height = max(height, size.height)
        }
        if !current.isEmpty { rows.append((current, y, x - spacing, height)) }
        return rows
    }
}

/// Settings ▸ Appearance ▸ Site styles.
private struct SiteStylesGroup: View {
    @Environment(BrowserModel.self) private var browser
    @State private var styles = SiteStyles.shared

    var body: some View {
        SettingsGroup(title: "Site styles") {
            SettingsRow("siteStyles") {
                Button("Add Site…") { browser.siteStyleDraft = SiteStyle(site: "", css: "") }
            }
            ForEach(styles.styles) { style in
                SettingsDivider()
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(get: { style.isEnabled }, set: { styles.setEnabled($0, for: style) }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(style.site).font(.system(size: 13))
                        Text(style.css.split(separator: "\n").first.map(String.init) ?? "Empty")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Edit") { browser.siteStyleDraft = style }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
            }
        }
        .settingsAnchor("siteStylesGroup")
    }
}
