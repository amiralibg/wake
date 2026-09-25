import SwiftUI

/// The centred ⌘K palette: address bar, search, and results in one place.
struct CommandPalette: View {
    @Bindable var model: PaletteModel
    let onChoose: (PaletteItem) -> Void
    let onDismiss: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            field
            if !model.sections.isEmpty {
                Divider().opacity(0.6)
                PaletteResultsList(model: model, onChoose: onChoose)
            }
        }
        .frame(width: 640)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), vibrantContent: false)
        .shadow(color: .black.opacity(0.22), radius: 40, y: 18)
        // Focus must be set after the palette is in the window; onAppear is too early
        // during the insertion transition, so the field would silently not get focus.
        .task {
            await Task.yield()
            isFieldFocused = true
        }
        .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(.tab) {
            if case .suggestion(let text) = model.selectedItem { model.query = text }
            return .handled
        }
    }

    private var field: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(model.target == .currentColumn ? "Go to… (replaces this page)" : "Search or enter address — opens a new column", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isFieldFocused)
                .onSubmit { if let item = model.selectedItem { onChoose(item) } }
            if model.isSearching {
                ProgressView().controlSize(.small)
            }
            KeyHint("esc")
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }
}

struct KeyHint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 5, style: .continuous))
    }
}
