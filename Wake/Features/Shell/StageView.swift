import SwiftUI

/// The area below the toolbar: the trail, or a hint when it's empty.
struct StageView: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        ZStack {
            TrailView(
                trail: browser.trail,
                isInteractive: !browser.isPaletteOpen && !browser.isSettingsOpen && !browser.isDeckOpen,
                onPageScroll: browser.noteReadingScroll
            )
                .id(browser.thread.id)
            if browser.trail.columns.isEmpty {
                EmptyStage()
                    .transition(.opacity)
            }
        }
        // Room for the app capsule on the left (when it floats, it goes over the pages instead).
        .padding(.leading, browser.showsAppCapsule && !browser.capsuleFloats ? Metrics.capsuleWidth + 6 : 0)
        .animation(.trail, value: browser.trail.columns.isEmpty)
    }
}

private struct EmptyStage: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        VStack(spacing: 8) {
            Text("Wake")
                .font(.system(size: 34, weight: .semibold, design: .serif))
            Button("Press ⌘K to go somewhere") { browser.showPalette() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .opacity(browser.isPaletteOpen ? 0 : 1)
    }
}
