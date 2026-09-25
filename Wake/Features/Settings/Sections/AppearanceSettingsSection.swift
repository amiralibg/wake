import SwiftUI

struct AppearanceSettingsSection: View {
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        @Bindable var appearance = appearance
        VStack(alignment: .leading, spacing: 16) {
            AppearancePreview()

            SettingsGroup {
                SettingsRow(label: "Theme") {
                    HStack(spacing: 14) {
                        ForEach(ThemePreference.allCases) { theme in
                            ThemeSwatch(theme: theme, isSelected: appearance.theme == theme) {
                                appearance.theme = theme
                            }
                        }
                    }
                }
                SettingsDivider()
                SettingsRow(label: "Accent color") {
                    HStack(spacing: 10) {
                        ForEach(AccentChoice.allCases) { accent in
                            AccentDot(accent: accent, isSelected: appearance.accent == accent) {
                                appearance.accent = accent
                            }
                        }
                    }
                }
                SettingsDivider()
                SettingsRow(label: "Glass") {
                    SettingsSegmented(selection: $appearance.glass, options: GlassStrength.allCases, value: { $0 }, label: \.label)
                }
            }

            SettingsGroup(title: "Trail layout") {
                SettingsRow(label: "Gap between pages") {
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
                SettingsRow(label: "Corner radius") {
                    SettingsSegmented(selection: $appearance.cornerRadius, options: CornerRadiusOption.allCases, value: \.rawValue, label: \.label)
                }
                SettingsDivider()
                SettingsRow(label: "Page width") {
                    SettingsSegmented(selection: $appearance.pageWidth, options: PageWidth.allCases, value: { $0 }, label: \.label)
                }
            }
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
