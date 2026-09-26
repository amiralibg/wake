import SwiftUI

/// Shows column mode is on: where you are in the trail and the keys that work.
struct ColumnModeIsland: View {
    @Environment(BrowserModel.self) private var browser

    var body: some View {
        ZStack(alignment: .bottom) {
            if browser.isColumnModeActive {
                IslandContent(trail: browser.trail)
                    .padding(.bottom, Metrics.stageInset + 18)
                    .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

private struct IslandContent: View {
    let trail: TrailModel

    private let hints: [(keys: String, label: String)] = [
        ("h l", "focus"),
        ("H L", "move"),
        ("1–9", "jump"),
        ("< > =", "width"),
        ("x", "close"),
        ("esc", "done"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            position
            Divider().frame(height: 16)
            HStack(spacing: 10) {
                ForEach(hints, id: \.keys) { hint in
                    HStack(spacing: 5) {
                        Text(hint.keys)
                            .fixedSize()
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.primary.opacity(0.08), in: .rect(cornerRadius: 4, style: .continuous))
                        Text(hint.label)
                            .fixedSize()
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: Capsule())
        .glassSurface(Capsule(), vibrantContent: false)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Column mode, column \(trail.focusedIndex + 1) of \(trail.columns.count)")
    }

    /// One dot per column, the focused one drawn long; a count once they'd crowd.
    @ViewBuilder private var position: some View {
        if trail.columns.count <= 12 {
            HStack(spacing: 4) {
                ForEach(Array(trail.columns.enumerated()), id: \.element.id) { index, _ in
                    Capsule()
                        .fill(index == trail.focusedIndex ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.25)))
                        .frame(width: index == trail.focusedIndex ? 14 : 5, height: 5)
                }
            }
            .animation(.trail, value: trail.focusedIndex)
        } else {
            Text("\(trail.focusedIndex + 1) / \(trail.columns.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}
