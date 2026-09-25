import SwiftUI

/// One page in the trail. Every column is the same size; the focused one only has a
/// deeper shadow, and the others are very slightly dimmed. The first click on an
/// unfocused column focuses it.
struct TrailColumn: View {
    let page: BrowserPage
    let isFocused: Bool
    let onFocus: () -> Void
    let onClose: () -> Void

    var body: some View {
        if page.isDevTools {
            // A tool beside its page: usable without taking focus from the page.
            DevToolsColumn(target: page.inspectedPage, onClose: onClose)
        } else if page.device != nil {
            DevicePreviewColumn(page: page, onClose: onClose)
        } else {
            PageCard(page: page, isFocused: isFocused, onClose: onClose)
                .overlay {
                    if !isFocused {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture(perform: onFocus)
                    }
                }
                .opacity(isFocused ? 1 : 0.92)
                .animation(.trail, value: isFocused)
        }
    }
}
