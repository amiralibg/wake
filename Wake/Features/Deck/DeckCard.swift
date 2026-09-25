import SwiftUI

/// A live card: favicon and title, a thumbnail of the page, one state chip, and a
/// footnote. Threads with several pages are drawn as a small stack.
struct DeckCard: View {
    let item: DeckItem
    let size: CGSize
    let isOpen: Bool

    @Environment(ThumbnailStore.self) private var thumbnails

    var body: some View {
        ZStack {
            if item.pageCount > 1 {
                ghost(offset: 12, inset: 20, opacity: 0.5)
                ghost(offset: 6, inset: 10, opacity: 0.75)
            }
            face
        }
        .frame(width: size.width, height: size.height)
        .saturation(item.isSunk ? 0.3 : (item.heat < 0.4 ? 0.7 : 1))
        .opacity(item.isSunk ? 0.8 : 1)
    }

    private var face: some View {
        VStack(spacing: 0) {
            header
            thumbnail
                .padding(.horizontal, isOpen ? 10 : 8)
                .padding(.top, isOpen ? 10 : 8)
            Text(item.footnote)
                .font(.system(size: isOpen ? 11 : 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, isOpen ? 12 : 9)
                .frame(height: isOpen ? 30 : 22)
        }
        .background(Color(nsColor: .textBackgroundColor), in: shape)
        .overlay {
            if item.isActive {
                shape.strokeBorder(.tint, lineWidth: 2.5)
            } else {
                shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(item.isActive ? 0.28 : 0.2), radius: item.isActive ? 22 : 14, y: item.isActive ? 14 : 8)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Favicon(url: URL(string: "https://\(item.host)/favicon.ico"), host: item.host, size: isOpen ? 14 : 12)
            Text(item.title)
                .font(.system(size: isOpen ? 12 : 11, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let chip = item.chip {
                ChipView(chip: chip)
            }
        }
        .padding(.horizontal, isOpen ? 12 : 9)
        .frame(height: isOpen ? 34 : 30)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    @ViewBuilder private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: isOpen ? 8 : 6, style: .continuous)
        if let image = thumbnails.image(for: item.threadID) {
            // The card decides the size; the snapshot fills it from the top and is cropped.
            // (A fill image on its own asks for its full height and stretches the card.)
            Color.clear
                .overlay(alignment: .top) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipShape(shape)
        } else {
            shape
                .fill(MonogramIcon.color(for: item.host).opacity(0.18))
                .overlay {
                    Favicon(url: URL(string: "https://\(item.host)/favicon.ico"), host: item.host, size: isOpen ? 28 : 20)
                        .opacity(0.8)
                }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isOpen ? 16 : 14, style: .continuous)
    }

    private func ghost(offset: CGFloat, inset: CGFloat, opacity: Double) -> some View {
        shape
            .fill(Color(nsColor: .textBackgroundColor).opacity(opacity))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .padding(.horizontal, inset / 2)
            .offset(y: -offset)
    }
}

private struct ChipView: View {
    let chip: DeckItem.Chip

    var body: some View {
        switch chip {
        case .playing:
            Label("Playing", systemImage: "speaker.wave.2.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.tint.opacity(0.14), in: Capsule())
        case .unsaved:
            Text("Unsaved")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.54, green: 0.35, blue: 0))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color(red: 1, green: 0.96, blue: 0.84), in: Capsule())
        case .live(let chip):
            LiveChipView(chip: chip)
        }
    }
}
