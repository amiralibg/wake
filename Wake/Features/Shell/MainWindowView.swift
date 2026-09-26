import SwiftUI

struct MainWindowView: View {
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(DeckSettings.self) private var deck
    @Environment(DeveloperSettings.self) private var developer
    @State private var browser = BrowserModel()
    @AppStorage(OnboardingView.completedKey) private var onboardingCompleted = false

    var body: some View {
        ZStack(alignment: .top) {
            WindowBackdrop()
            VStack(spacing: 0) {
                if !browser.isZen {
                    WakeToolbar()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                StageView()
            }
            // Covered by the Moments library or the welcome tour: keep VoiceOver out of it too.
            .accessibilityHidden(browser.isMomentsOpen || !onboardingCompleted)
            AppPanel()
            if browser.showsAppCapsule, onboardingCompleted {
                AppCapsule()
                    .onHover { inside in browser.capsuleHovered(inside) }
                    .padding(.leading, 8)
                    // In Zen it tucks under the top edge, unless the floating toolbar is
                    // showing: then it sits below it rather than behind it.
                    .padding(.top, browser.isZen && !browser.isChromeRevealed ? Metrics.stageInset : Metrics.toolbarHeight + 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if browser.isZen {
                ZenChrome()
            }
            DeckLayer()
            SaveMomentIsland()
            MomentsLibrary()
            PaletteOverlay()
            SettingsOverlay()
            if !onboardingCompleted {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.45)) { onboardingCompleted = true }
                    if browser.trail.columns.isEmpty { browser.showPalette() }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.03)))
                .zIndex(10)
            }
        }
        .ignoresSafeArea()
        .background(WindowConfigurator(
            trafficLightsHidden: browser.isZen && !browser.isChromeRevealed && !browser.isMomentsOpen && onboardingCompleted,
            onClose: browser.windowWillClose,
            onWindow: { browser.window = $0 }
        ))
        // Lives on the root view: overlays that are empty while closed don't keep
        // their AppKit helper views in the window.
        // Reaching the bottom edge raises the Deck; in Zen, the top edge brings the toolbar.
        .onWindowEdgeHover(edges) { edge in
            switch edge {
            case .bottom: browser.peekDeck()
            case .top: browser.revealZenChrome()
            case .left: browser.revealCapsule()
            }
        }
        .onEscapeKey(isActive: browser.hasOverlay, perform: browser.dismissOverlays)
        .sheet(isPresented: $browser.isImportingBrowserData) { ImportSheet() }
        .animation(.chrome, value: browser.showsAppCapsule)
        .environment(browser)
        .environment(\.isZen, browser.isZen)
        .focusedSceneValue(\.browser, browser)
        .tint(appearance.accent.color)
        .navigationTitle(browser.page?.displayTitle ?? browser.thread.title)
        .animation(.trail, value: browser.isZen)
        .onAppear { if browser.trail.columns.isEmpty, onboardingCompleted { browser.showPalette() } }
        // Dev-server scanning is app-wide; starting it again is harmless.
        .task { MomentWatcher.shared.start() }
        .task(id: developer.scansPorts) {
            developer.scansPorts ? DevServerScanner.shared.start() : DevServerScanner.shared.stop()
        }
    }

    /// Window edges that reveal something: the Deck below; in Zen, the toolbar and apps.
    private var edges: Set<WindowEdge> {
        var edges: Set<WindowEdge> = browser.isZen ? [.top, .left] : []
        if browser.capsuleFloats { edges.insert(.left) }
        if deck.peeksFromBottomEdge { edges.insert(.bottom) }
        return edges
    }
}
