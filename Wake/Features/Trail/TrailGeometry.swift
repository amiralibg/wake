import CoreGraphics

/// Pure layout maths for the trail. Offsets are in "content" space: 0 means the
/// leading inset of the first column sits at the stage's left edge.
///
/// Default widths: one column fills the stage; with more, the stage is split into
/// `columnsPerScreen` (2 for Balanced), and anything beyond that scrolls.
/// A column the user resized keeps its own share of the stage, whatever its
/// neighbours do. A lone column always fills the stage.
struct TrailGeometry: Equatable {
    var stageWidth: CGFloat = 0
    var gap: CGFloat = 0
    var inset: CGFloat = 0
    private(set) var widths: [CGFloat] = []

    init() {}

    init(stageWidth: CGFloat, gap: CGFloat, inset: CGFloat, columnsPerScreen: CGFloat, customFractions: [CGFloat?]) {
        self.stageWidth = stageWidth
        self.gap = gap
        self.inset = inset
        let usable = max(0, stageWidth - inset * 2)
        let split = min(CGFloat(customFractions.count), columnsPerScreen)
        let standard = split > 0 ? (usable - (split - 1) * gap) / split : usable
        let minimum = min(Metrics.minColumnWidth, usable)
        let resizedMinimum = min(Metrics.minResizedColumnWidth, usable)
        if customFractions.count == 1 {
            widths = [usable]
            return
        }
        widths = customFractions.map { fraction in
            guard let fraction else { return min(usable, max(minimum, standard)) }
            return min(usable, max(resizedMinimum, fraction * usable))
        }
    }

    var count: Int { widths.count }

    var usableWidth: CGFloat { max(0, stageWidth - inset * 2) }

    var contentWidth: CGFloat {
        guard count > 0 else { return 0 }
        return inset * 2 + widths.reduce(0, +) + CGFloat(count - 1) * gap
    }

    func x(of index: Int) -> CGFloat {
        inset + widths.prefix(index).reduce(0, +) + CGFloat(index) * gap
    }

    func width(of index: Int) -> CGFloat {
        widths.indices.contains(index) ? widths[index] : 0
    }

    /// Columns that are on the stage at `offset`, or within `margin` of it (so a
    /// column about to slide in is already drawing).
    func indices(onStageAt offset: CGFloat, margin: CGFloat) -> Set<Int> {
        Set((0..<count).filter { index in
            let start = x(of: index) - offset
            return start + width(of: index) > -margin && start < stageWidth + margin
        })
    }

    private var maxOffset: CGFloat { max(0, contentWidth - stageWidth) }

    /// Centre the focused column (with `span - 1` companion columns after it, such as
    /// its DevTools), but never scroll past either end of the trail. When the group is
    /// wider than the stage, its start stays in view. A trail narrower than the stage
    /// is centred as a whole.
    func targetOffset(focusing index: Int, span: Int = 1) -> CGFloat {
        guard contentWidth > stageWidth else { return -(stageWidth - contentWidth) / 2 }
        let last = min(index + max(span, 1) - 1, count - 1)
        let start = x(of: index)
        let end = x(of: last) + width(of: last)
        let ideal = end - start > stageWidth - inset * 2
            ? start - inset
            : (start + end) / 2 - stageWidth / 2
        return min(max(ideal, 0), maxOffset)
    }

    /// A remembered offset kept within the trail. A trail narrower than the stage
    /// is centred instead.
    func clamped(_ offset: CGFloat) -> CGFloat {
        guard contentWidth > stageWidth else { return -(stageWidth - contentWidth) / 2 }
        return min(max(offset, 0), maxOffset)
    }

    func nearestIndex(to offset: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        return (0..<count).min { abs(targetOffset(focusing: $0) - offset) < abs(targetOffset(focusing: $1) - offset) } ?? 0
    }

    /// Resistance past either end while dragging.
    func rubberBanded(_ offset: CGFloat) -> CGFloat {
        let low = min(targetOffset(focusing: 0), 0)
        let high = max(targetOffset(focusing: max(count - 1, 0)), maxOffset)
        if offset < low { return low - rubber(low - offset) }
        if offset > high { return high + rubber(offset - high) }
        return offset
    }

    private func rubber(_ distance: CGFloat) -> CGFloat {
        let dimension = max(stageWidth, 1)
        return (1 - 1 / (distance * 0.55 / dimension + 1)) * dimension
    }
}
