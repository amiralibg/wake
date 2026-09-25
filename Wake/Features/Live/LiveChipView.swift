import SwiftUI

/// A live chip as a small capsule: symbol and text in the chip's tone, and for
/// media a hairline of progress along the bottom.
struct LiveChipView: View {
    let chip: LiveChip

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: chip.symbol)
                .font(.system(size: 8.5, weight: .bold))
            Text(chip.text)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(chip.tone.foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(chip.tone.background, in: Capsule())
        .overlay(alignment: .bottomLeading) {
            if let progress = chip.progress {
                GeometryReader { proxy in
                    Capsule()
                        .fill(chip.tone.foreground)
                        .frame(width: max(2, proxy.size.width * progress), height: 1.5)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 1)
            }
        }
        .fixedSize()
        .help(chip.text)
    }
}

extension LiveChip.Tone {
    var foreground: AnyShapeStyle {
        switch self {
        case .accent: AnyShapeStyle(.tint)
        case .good: AnyShapeStyle(Color(nsColor: .systemGreen))
        case .bad: AnyShapeStyle(Color(nsColor: .systemRed))
        case .warning: AnyShapeStyle(Color(nsColor: .systemOrange))
        case .neutral: AnyShapeStyle(.secondary)
        }
    }

    var background: AnyShapeStyle {
        switch self {
        case .accent: AnyShapeStyle(.tint.opacity(0.14))
        case .good: AnyShapeStyle(Color(nsColor: .systemGreen).opacity(0.14))
        case .bad: AnyShapeStyle(Color(nsColor: .systemRed).opacity(0.14))
        case .warning: AnyShapeStyle(Color(nsColor: .systemOrange).opacity(0.16))
        case .neutral: AnyShapeStyle(.primary.opacity(0.07))
        }
    }

    /// Dot colour on trail chips (the window's tint for accent); neutral facts get no dot.
    var dot: AnyShapeStyle? {
        self == .neutral ? nil : foreground
    }
}
