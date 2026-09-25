import SwiftUI

/// Appears under the toolbar after ⌘D. The moment is already saved; this island
/// only adds the "why" and when it should come back. Return or Esc puts it away.
struct SaveMomentIsland: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(\.isZen) private var isZen

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let moment = browser.savedMoment {
                IslandContent(moment: moment)
                    .id(moment.id)
                    .padding(.top, isZen ? Metrics.stageInset : Metrics.toolbarHeight + 2)
                    .padding(.trailing, Metrics.toolbarPadding)
                    .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.chrome, value: browser.savedMoment?.id)
    }
}

private struct IslandContent: View {
    let moment: MomentRecord

    @Environment(BrowserModel.self) private var browser
    @State private var note = ""
    @State private var resurface: ResurfaceChoice = .nextWeek
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.tint)
                Text("Moment saved")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Button("Undo", action: browser.undoSaveMoment)
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
            }
            Text("\(moment.host) · \(moment.title)")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let selection = moment.selectedText {
                Text(selection)
                    .font(.system(size: 12.5))
                    .lineLimit(3)
                    .padding(.horizontal, 3)
                    .background(MomentFormat.highlight, in: .rect(cornerRadius: 3))
            }
            TextField("Why are you saving this?", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...3)
                .focused($noteFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.primary.opacity(0.07), in: .rect(cornerRadius: 8, style: .continuous))
                .onSubmit(done)
            HStack(spacing: 8) {
                Text("Bring it back")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("Bring it back", selection: $resurface) {
                    ForEach(ResurfaceChoice.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: .rect(cornerRadius: 16, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), vibrantContent: false)
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .onAppear {
            note = moment.note ?? ""
            noteFocused = true
        }
        // Esc and clicks elsewhere close the island too; keep what was typed.
        .onDisappear(perform: saveNote)
        .onChange(of: resurface) { _, choice in
            MomentStore.shared.update(moment) { $0.resurfaceAt = choice.date(from: moment.createdAt) }
        }
    }

    private func done() {
        saveNote()
        browser.finishSavingMoment()
    }

    private func saveNote() {
        // After Undo the moment is gone.
        guard MomentStore.shared.moment(id: moment.id) != nil else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard moment.note != value else { return }
        MomentStore.shared.update(moment) { $0.note = value }
    }
}
