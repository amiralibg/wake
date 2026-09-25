import SwiftUI

struct PaletteResultsList: View {
    let model: PaletteModel
    let onChoose: (PaletteItem) -> Void

    var body: some View {
        let sections = model.sections
        let selectedID = model.selectedItem?.id
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                        }
                        ForEach(section.items) { item in
                            Button { onChoose(item) } label: {
                                PaletteRow(item: item, isSelected: item.id == selectedID)
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .onHover { hovering in
                                if hovering, let index = model.items.firstIndex(of: item) {
                                    model.selection = index
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id) }
            }
        }
    }
}
