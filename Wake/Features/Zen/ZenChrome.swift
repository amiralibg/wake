import SwiftUI

extension EnvironmentValues {
    /// Zen hides all chrome; only pages remain.
    @Entry var isZen = false
}

/// In Zen mode the toolbar lives off-screen. Touching the top edge of the window
/// floats its islands in over the pages; they tuck away once the pointer leaves.
struct ZenChrome: View {
    @Environment(BrowserModel.self) private var browser
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if browser.isChromeRevealed {
                WakeToolbar(isFloating: true)
                    .onHover { inside in inside ? cancelHide() : scheduleHide() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .animation(.chrome, value: browser.isChromeRevealed)
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func scheduleHide() {
        cancelHide()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, !browser.isPaletteOpen else { return }
            browser.isChromeRevealed = false
        }
    }
}
