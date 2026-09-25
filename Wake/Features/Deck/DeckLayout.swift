import CoreGraphics

/// Where each card sits. The active card takes the centre; the rest alternate right,
/// left, right… by heat, sitting higher the hotter they are.
///
/// - hidden: cards wait below the window edge.
/// - peek: small cards stand in a row inside a glass island sized to fit them.
/// - open: large cards fan up over the frosted page; sunk ones sit behind the waterline.
struct DeckLayout {
    struct Placement: Equatable {
        /// Card centre, horizontally, relative to the window's centre.
        var x: CGFloat
        /// Distance from the window's bottom edge to the card's bottom edge.
        var bottom: CGFloat
        var rotation: Double
        var zIndex: Double
    }

    enum State { case hidden, peek, open }

    static let margin: CGFloat = 12
    static let peekFooterHeight: CGFloat = 30
    /// Inset between the island's edge and its cards.
    static let peekPadding: CGFloat = 14
    /// Room above a card for the stack of pages behind it.
    static let stackAllowance: CGFloat = 12
    static let waterlineIslandHeight: CGFloat = 64

    let state: State
    let width: CGFloat

    var cardSize: CGSize {
        state == .open ? CGSize(width: 250, height: 180) : CGSize(width: 150, height: 108)
    }

    /// Orders afloat items for the fan: active first, then by heat.
    static func fanOrder(_ items: [DeckItem]) -> [DeckItem] {
        items.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.heat > rhs.heat
        }
    }

    /// The island hugs its row of cards.
    func peekIslandSize(count: Int) -> CGSize {
        let row = CGFloat(max(count - 1, 0)) * peekSpacing(count: count) + cardSize.width
        return CGSize(
            width: max(260, row + Self.peekPadding * 2),
            height: Self.peekPadding + Self.stackAllowance + cardSize.height + 6 + Self.peekFooterHeight
        )
    }

    /// Side by side with a small gap; overlapping only when the window is too narrow.
    private func peekSpacing(count: Int) -> CGFloat {
        let fit = (width - 48 - Self.peekPadding * 2 - cardSize.width) / CGFloat(max(count - 1, 1))
        return min(cardSize.width + 10, max(28, fit))
    }

    /// `rank` 0 is the centre; 1 goes right, 2 left, 3 further right…
    func placement(rank: Int, heat: Double, count: Int) -> Placement {
        let ring = (rank + 1) / 2
        let side: CGFloat = rank == 0 ? 0 : (rank % 2 == 1 ? 1 : -1)
        switch state {
        case .open:
            let rings = max(1, count / 2)
            let spacing = min(165, (width / 2 - cardSize.width / 2 - 20) / CGFloat(rings))
            let waterlineTop = Self.margin + Self.waterlineIslandHeight
            return Placement(
                x: side * CGFloat(ring) * spacing,
                bottom: waterlineTop + 14 + heat * 150 - CGFloat(ring) * 12,
                rotation: Double(side) * min(12, Double(ring) * 4),
                zIndex: Double(100 - ring)
            )
        case .peek, .hidden:
            // A plain row, hottest first, centred in the island.
            let x = (CGFloat(rank) - CGFloat(count - 1) / 2) * peekSpacing(count: count)
            let base = Self.margin + Self.peekFooterHeight + 6
            return Placement(
                x: x,
                bottom: state == .peek ? base : -cardSize.height - 60,
                rotation: 0,
                zIndex: Double(100 - rank)
            )
        }
    }

    /// Sunk cards: a row centred behind the waterline island, just their tops showing.
    /// They only surface when the Deck is open.
    func sunkPlacement(index: Int, count: Int) -> Placement {
        let usable = max(0, width - cardSize.width - 120)
        let step = count > 1 ? min(cardSize.width * 0.75, usable / CGFloat(count - 1)) : 0
        let x = -step * CGFloat(count - 1) / 2 + CGFloat(index) * step
        let wobble = [-6.0, 3, -2, 5, -4, 6][index % 6]
        let bottom: CGFloat = state == .open
            ? Self.margin + Self.waterlineIslandHeight - cardSize.height * 0.5
            : -cardSize.height - 60
        return Placement(x: x, bottom: bottom, rotation: wobble, zIndex: Double(index))
    }
}
