import SwiftUI

/// The glass island the peeking Deck stands in. The cards are drawn on top of it;
/// this is the island itself plus its footer line.
struct PeekIsland: View {
    let afloatCount: Int
    let sunkCount: Int
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text("Deck").font(.system(size: 12, weight: .semibold))
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onOpen) {
                    HStack(spacing: 3) {
                        Text("Open")
                        Text("⌘K").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Open the Deck")
            }
            .padding(.horizontal, DeckLayout.peekPadding + 2)
            .frame(height: DeckLayout.peekFooterHeight)
        }
        .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous), vibrantContent: false)
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
    }

    private var summary: String {
        sunkCount > 0 ? "\(afloatCount) afloat · \(sunkCount) sunk" : "\(afloatCount) afloat"
    }
}

/// The waterline in the open Deck: a floating island that cold cards sink behind.
struct WaterlineIsland: View {
    let sunkCount: Int
    let onLetGo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Below the waterline").font(.system(size: 13, weight: .semibold))
                Text(sunkSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if sunkCount > 0 {
                Text("Drag a card up to revive it")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Let them go", action: onLetGo)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .frame(height: DeckLayout.waterlineIslandHeight)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35), in: .rect(cornerRadius: 22, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), vibrantContent: false)
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private var sunkSummary: String {
        switch sunkCount {
        case 0: "Nothing has sunk yet."
        case 1: "1 tab you stopped using. Still searchable."
        default: "\(sunkCount) tabs you stopped using. Still searchable."
        }
    }
}
