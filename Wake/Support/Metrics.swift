import CoreGraphics

enum Metrics {
    static let toolbarHeight: CGFloat = 56
    static let toolbarPadding: CGFloat = 16
    /// Space reserved at the leading edge of the toolbar for the traffic lights.
    static let trafficLightsWidth: CGFloat = 64
    static let capsuleHeight: CGFloat = 32
    /// The vertical app capsule on the left.
    static let capsuleWidth: CGFloat = 42
    static let stageInset: CGFloat = 12
    static let minColumnWidth: CGFloat = 420
    /// How narrow a column can be dragged.
    static let minResizedColumnWidth: CGFloat = 300
}
