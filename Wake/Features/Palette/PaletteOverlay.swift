import SwiftUI

/// Dims the page and floats the palette near the top third of the window.
struct PaletteOverlay: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        ZStack(alignment: .top) {
            if browser.isPaletteOpen {
                Color.black.opacity(0.14)
                    .contentShape(.rect)
                    .onTapGesture(perform: browser.hidePalette)
                    .transition(.opacity)

                CommandPalette(model: browser.palette, onChoose: browser.choose, onDismiss: browser.hidePalette)
                    .padding(.top, 120)
                    .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.chrome, value: browser.isPaletteOpen)
    }
}
