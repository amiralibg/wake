import SwiftUI

/// Three slots — leading, centre, trailing — with the centre slot pinned to the
/// window's true centre. The leading slot gets whatever room is left on its side
/// and truncates; the centre shrinks only when the window is too narrow for both.
struct ToolbarLayout: Layout {
    var spacing: CGFloat = 12
    var minCenterWidth: CGFloat = 200

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 900, height: Metrics.toolbarHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let (leading, center, trailing) = (subviews[0], subviews[1], subviews[2])

        let trailingSize = trailing.sizeThatFits(.unspecified)
        let leadingMin = leading.sizeThatFits(ProposedViewSize(width: 0, height: bounds.height)).width
        let side = max(trailingSize.width, leadingMin) + spacing
        let centerIdeal = center.sizeThatFits(.unspecified).width
        let centerWidth = max(minCenterWidth, min(centerIdeal, bounds.width - side * 2))

        center.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: centerWidth, height: bounds.height)
        )
        trailing.place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: ProposedViewSize(trailingSize)
        )
        let leadingWidth = max(0, bounds.midX - centerWidth / 2 - spacing - bounds.minX)
        leading.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: leadingWidth, height: bounds.height)
        )
    }
}
