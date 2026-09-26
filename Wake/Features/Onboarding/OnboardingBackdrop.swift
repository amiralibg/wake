import SwiftUI

/// The stage behind onboarding: dark water with a wake (the app icon's idea)
/// trailing a point of light that travels across as you go through the steps. Each
/// step change drops a ring into the water from the bow, and the pointer disturbs the
/// surface under it. Drawn by `WakeWaterView`; with Reduce Motion the water holds still.
struct OnboardingBackdrop: View, Animatable {
    let accent: Color
    /// 0…1 across the steps: the bow travels with it. Animatable, so a step change
    /// glides the bow instead of jumping it.
    var progress: Double
    /// Changes when the step does: time for a drop.
    let dropID: Int

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let ink = Color(red: 0.055, green: 0.051, blue: 0.047)

    var body: some View {
        WakeWaterView(accent: accent, progress: progress, dropID: dropID, isStill: reduceMotion)
            .background(Self.ink)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// A headline whose words rise out of a blur one after another.
struct RevealText: View {
    let text: String
    var size: CGFloat = 56
    var weight: Font.Weight = .semibold
    var delay: Double = 0

    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        HStack(alignment: .firstTextBaseline, spacing: size * 0.24) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(size: size, weight: weight, design: .default))
                    .tracking(-size * 0.028)
                    .opacity(isShown ? 1 : 0)
                    .blur(radius: isShown || reduceMotion ? 0 : 12)
                    .offset(y: isShown || reduceMotion ? 0 : size * 0.35)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.7, dampingFraction: 0.82).delay(delay + Double(index) * 0.07),
                        value: isShown
                    )
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
        .onAppear { isShown = true }
    }
}

/// Fades and lifts content in after the headline.
struct Arrive: ViewModifier {
    let delay: Double
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.6, dampingFraction: 0.86).delay(delay), value: isShown)
            .onAppear { isShown = true }
    }
}

extension View {
    func arrive(after delay: Double) -> some View { modifier(Arrive(delay: delay)) }
}
