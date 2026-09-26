import SwiftUI

/// First-launch welcome: what the trail is, how Wake should look, where searches go,
/// and the shortcuts worth knowing. Choices apply live and are the real settings.
/// Shown again from Settings ▸ General ▸ Welcome tour.
struct OnboardingView: View {
    static let completedKey = "onboarding.completed"

    let onFinish: () -> Void

    @Environment(AppearanceSettings.self) private var appearance
    @State private var step: Step = .welcome
    @State private var isForward = true
    @FocusState private var isFocused: Bool

    enum Step: Int, CaseIterable {
        case welcome, trail, look, search, shortcuts, ready

        var progress: Double { Double(rawValue) / Double(Self.allCases.count - 1) }
    }

    /// Covered or hidden: the tour's animations pause.
    @State private var isWindowVisible = true

    var body: some View {
        ZStack {
            OnboardingBackdrop(accent: appearance.accent.color, progress: step.progress, dropID: step.rawValue)
                .animation(.easeInOut(duration: 1.2), value: step)
            VStack(spacing: 0) {
                topBar
                ScaleToFit {
                    content
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .offset(x: isForward ? 60 : -60).combined(with: .opacity),
                            removal: .offset(x: isForward ? -60 : 60).combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
            .padding(.horizontal, 48)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.isWindowVisible, isWindowVisible)
        .background(WindowVisibilityReader(isVisible: $isWindowVisible))
        .tint(appearance.accent.color)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.return) { advance(); return .handled }
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.leftArrow) { back(); return .handled }
        .onKeyPress(.escape) { onFinish(); return .handled }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            if step != .ready {
                Button("Skip tour", action: onFinish)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(minHeight: 32)
                    .contentShape(.rect)
                    .help("Skip (Esc)")
            }
        }
        .frame(height: 32)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .trail: TrailStep()
        case .look: LookStep()
        case .search: SearchStep()
        case .shortcuts: ShortcutsStep()
        case .ready: ReadyStep()
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button("Back", action: back)
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 80, height: 44, alignment: .leading)
                .contentShape(.rect)
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Spacer()
            ProgressDots(step: step) { target in go(to: target) }
            Spacer()
            Button(action: advance) {
                Text(primaryTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(minWidth: 80, minHeight: 44)
                    .background(appearance.accent.color, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .help("Continue (↩)")
        }
        .frame(maxWidth: 720)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .ready: "Start browsing"
        default: "Continue"
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            onFinish()
            return
        }
        go(to: next)
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    private func go(to target: Step) {
        guard target != step else { return }
        isForward = target.rawValue > step.rawValue
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { step = target }
    }
}

/// Lays the step out at its natural size and shrinks it to fit a small window,
/// so nothing truncates or clips; a large window never scales it up.
private struct ScaleToFit<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        GeometryReader { container in
            let scale = naturalHeight > 0 ? min(1, container.size.height / naturalHeight) : 1
            content
                .frame(width: min(container.size.width / max(scale, 0.01), 900))
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { naturalHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in naturalHeight = height }
                })
                .scaleEffect(scale)
                .frame(width: container.size.width, height: container.size.height)
        }
    }
}

/// Scales down a touch while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ProgressDots: View {
    let step: OnboardingView.Step
    let onSelect: (OnboardingView.Step) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingView.Step.allCases, id: \.self) { candidate in
                Button { onSelect(candidate) } label: {
                    Capsule()
                        .fill(candidate == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(candidate.rawValue < step.rawValue ? 0.5 : 0.18)))
                        .frame(width: candidate == step ? 28 : 8, height: 8)
                        .frame(height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(candidate.rawValue + 1) of \(OnboardingView.Step.allCases.count)")
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
    }
}

// MARK: Steps

/// Shared layout: an eyebrow, a big headline, a line of body copy, then the step's own content.
private struct StepLayout<Content: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.tint)
                    .arrive(after: 0)
                RevealText(text: title, size: 44, delay: 0.05)
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
                    .arrive(after: 0.25)
            }
            content
                .arrive(after: 0.4)
        }
        .frame(maxWidth: 760)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 36) {
            PageWake()
                .frame(height: 210)
            VStack(spacing: 14) {
                RevealText(text: "Browse in a wake.", size: 72, weight: .bold, delay: 0.35)
                Text("Wake is a Mac browser where every link opens as a column beside the page you came from. Your path stays in view, and nothing hides in a tab bar.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 540)
                    .arrive(after: 0.8)
            }
        }
    }
}

/// The icon's idea at hero size: a page, and the wake of pages trailing behind it.
private struct PageWake: View {
    @State private var isShown = false
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isWindowVisible) private var isWindowVisible

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isWindowVisible)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach((0..<5).reversed(), id: \.self) { index in
                    let depth = Double(index)
                    MiniPage(accent: appearance.accent.color, isLead: index == 0)
                        .frame(width: 150, height: 196)
                        .scaleEffect(1 - depth * 0.08)
                        .opacity(isShown ? 1 - depth * 0.19 : 0)
                        .offset(
                            x: isShown ? -depth * 74 + 150 : 360,
                            y: sin(t * 1.1 - depth * 0.6) * (3 + depth * 1.5)
                        )
                        .rotation3DEffect(.degrees(isShown ? -8 - depth * 3 : -30), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .animation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.9, dampingFraction: 0.78).delay(0.08 * (5 - depth)), value: isShown)
                        .zIndex(-depth)
                }
            }
        }
        .onAppear { isShown = true }
        .accessibilityHidden(true)
    }
}

private struct MiniPage: View {
    let accent: Color
    var isLead = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(white: isLead ? 0.97 : 0.9))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isLead ? accent.opacity(0.85) : Color(white: 0.8))
                        .frame(height: 58)
                    ForEach(0..<5) { line in
                        Capsule()
                            .fill(Color(white: 0.8))
                            .frame(height: 6)
                            .padding(.trailing, line == 4 ? 50 : 0)
                    }
                }
                .padding(12)
            }
            .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
    }
}

private struct TrailStep: View {
    @Environment(BrowsingSettings.self) private var browsing

    var body: some View {
        @Bindable var browsing = browsing
        StepLayout(
            eyebrow: "The trail",
            title: "Links open beside you.",
            detail: "Click a link and it slides in as a new column. Go deeper and the trail scrolls; step back with ⌘[ and every page is still there."
        ) {
            VStack(spacing: 26) {
                TrailDemo()
                    .frame(height: 170)
                HStack(spacing: 10) {
                    Hint(keys: "click", text: "New column")
                    Hint(keys: "⌘ click", text: "In the background")
                    Hint(keys: "⌥ click", text: "Stay on the page")
                }
                Picker("Clicked links open", selection: $browsing.linksOpenInNewColumn) {
                    Text("In a new column").tag(true)
                    Text("In the same page").tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }
}

/// Columns arriving one after another, like following links.
private struct TrailDemo: View {
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PhaseAnimator([0, 1, 2, 3], trigger: reduceMotion) { count in
            HStack(spacing: 10) {
                ForEach(0..<3) { index in
                    MiniPage(accent: appearance.accent.color, isLead: index == max(0, count - 1))
                        .frame(width: 120, height: 158)
                        .opacity(index < max(1, count) ? 1 : 0)
                        .offset(x: index < max(1, count) ? 0 : 50)
                        .scaleEffect(index == max(0, count - 1) ? 1 : 0.96)
                }
            }
        } animation: { count in
            reduceMotion ? nil : (count == 0 ? .easeInOut(duration: 0.5).delay(1.2) : .spring(response: 0.55, dampingFraction: 0.82).delay(0.9))
        }
        .accessibilityLabel("Animation: pages opening as columns")
    }
}

private struct Hint: View {
    let keys: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(.white.opacity(0.12), in: .rect(cornerRadius: 8, style: .continuous))
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.white.opacity(0.05), in: Capsule())
    }
}

private struct LookStep: View {
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        StepLayout(
            eyebrow: "Make it yours",
            title: "Pick a look.",
            detail: "Chrome floats as glass above your pages and only shows up when you need it. Change any of this later in Settings."
        ) {
            VStack(spacing: 28) {
                HStack(spacing: 16) {
                    ForEach([ThemePreference.auto, .light, .dark]) { theme in
                        ThemeCard(theme: theme, isSelected: appearance.theme == theme) {
                            withAnimation(.chrome) { appearance.theme = theme }
                        }
                    }
                }
                HStack(spacing: 14) {
                    ForEach(AccentChoice.allCases) { accent in
                        Button {
                            withAnimation(.chrome) { appearance.accent = accent }
                        } label: {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 26, height: 26)
                                .padding(4)
                                .overlay {
                                    if appearance.accent == accent {
                                        Circle().stroke(.white, lineWidth: 2)
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(accent.label)
                        .accessibilityAddTraits(appearance.accent == accent ? .isSelected : [])
                    }
                }
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: ThemePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                preview
                    .frame(width: 150, height: 96)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.14)), lineWidth: isSelected ? 2.5 : 1)
                    }
                Text(theme.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.65))
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(theme.label) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        switch theme {
        case .light: sample(background: Color(white: 0.93), page: .white, bar: Color(white: 0.82))
        case .dark: sample(background: Color(white: 0.16), page: Color(white: 0.24), bar: Color(white: 0.34))
        case .auto:
            HStack(spacing: 0) {
                sample(background: Color(white: 0.93), page: .white, bar: Color(white: 0.82))
                sample(background: Color(white: 0.16), page: Color(white: 0.24), bar: Color(white: 0.34))
            }
        }
    }

    private func sample(background: Color, page: Color, bar: Color) -> some View {
        ZStack(alignment: .top) {
            background
            VStack(spacing: 6) {
                Capsule().fill(bar).frame(width: 44, height: 8)
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(page)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(page)
                }
            }
            .padding(10)
        }
    }
}

private struct SearchStep: View {
    @Environment(BrowsingSettings.self) private var browsing

    var body: some View {
        @Bindable var browsing = browsing
        StepLayout(
            eyebrow: "Search",
            title: "Search your way.",
            detail: "Type anything into ⌘K. Addresses open, and everything else goes to the engine you choose here."
        ) {
            VStack(spacing: 18) {
                SearchEnginePicker(selection: $browsing.searchEngine, engines: SearchEngine.allCases.filter { $0 != .custom }, minimumWidth: 170)
                    .frame(maxWidth: 640)
                Toggle("Show suggestions while I type", isOn: $browsing.showsSearchSuggestions)
                    .toggleStyle(.switch)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}

private struct ShortcutsStep: View {
    private let shortcuts: [(keys: [String], title: String, detail: String)] = [
        (["⌘", "K"], "Deck & search", "Every thread, live, plus search"),
        (["⌘", "T"], "New column", "Open a page beside this one"),
        (["⌘", "D"], "Save a moment", "Scroll spot, selection and why"),
        (["⌘", "\\"], "Zen", "Hide everything but the pages"),
        (["⌥", "⌘", "I"], "DevTools", "Elements, console, network…"),
        (["⌘", "W"], "Close column", "Never the window while pages remain"),
    ]

    var body: some View {
        StepLayout(
            eyebrow: "Shortcuts",
            title: "Six keys to remember.",
            detail: "Wake keeps its chrome out of the way, so the keyboard does the work. The full list lives in Settings ▸ General."
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    ShortcutCard(keys: shortcut.keys, title: shortcut.title, detail: shortcut.detail, index: index)
                }
            }
            .frame(maxWidth: 720)
        }
    }
}

/// A keycap row that presses itself in turn, so the grid reads like someone typing.
private struct ShortcutCard: View {
    let keys: [String]
    let title: String
    let detail: String
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isWindowVisible) private var isWindowVisible

    var body: some View {
        HStack(spacing: 14) {
            // A key changes every 0.6 s; redrawing more often than that is wasted work.
            TimelineView(.animation(minimumInterval: 0.6, paused: reduceMotion || !isWindowVisible)) { timeline in
                let cycle = reduceMotion ? 1 : (timeline.date.timeIntervalSinceReferenceDate / 0.6).truncatingRemainder(dividingBy: 6)
                let pressed = !reduceMotion && Int(cycle) == index
                HStack(spacing: 4) {
                    ForEach(keys, id: \.self) { key in
                        Keycap(label: key, isPressed: pressed)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(keys.joined()) \(title): \(detail)")
    }
}

private struct Keycap: View {
    let label: String
    let isPressed: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, 2)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPressed ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.12)))
            }
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .offset(y: isPressed ? 1.5 : 0)
            .scaleEffect(isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: isPressed)
    }
}

private struct ReadyStep: View {
    @Environment(BrowsingSettings.self) private var browsing
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                ForEach(0..<3) { ring in
                    Ripple(delay: Double(ring) * 0.5)
                }
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 120, height: 120)
                    .arrive(after: 0.1)
            }
            .frame(height: 220)
            VStack(spacing: 14) {
                RevealText(text: "You’re all set.", size: 64, weight: .bold, delay: 0.2)
                Text("\(browsing.searchName) for search, \(appearance.theme == .auto ? "matching your Mac" : appearance.theme.label.lowercased() + " mode"), and a trail that remembers where you've been. Press ↩ to start.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
                    .arrive(after: 0.55)
            }
        }
    }
}

/// A ring spreading out from the icon, like a wake in still water.
private struct Ripple: View {
    let delay: Double
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(.tint.opacity(isAnimating ? 0 : 0.6), lineWidth: 1.5)
            .frame(width: 120, height: 120)
            .scaleEffect(isAnimating ? 2.6 : 0.9)
            .opacity(reduceMotion ? 0 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(delay)) { isAnimating = true }
            }
    }
}
