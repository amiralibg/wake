import CoreGraphics
import Foundation

/// A device size for the responsive preview, in CSS pixels (points), portrait.
struct DevicePreset: Hashable, Identifiable {
    enum Kind: Hashable { case phone, tablet, custom }

    let name: String
    let size: CGSize
    let kind: Kind

    var id: String { name }

    static let phones: [DevicePreset] = [
        DevicePreset(name: "iPhone SE", size: CGSize(width: 375, height: 667), kind: .phone),
        DevicePreset(name: "iPhone 16", size: CGSize(width: 393, height: 852), kind: .phone),
        DevicePreset(name: "iPhone 16 Pro Max", size: CGSize(width: 440, height: 956), kind: .phone),
        DevicePreset(name: "Android · Pixel 9", size: CGSize(width: 412, height: 915), kind: .phone),
    ]

    static let tablets: [DevicePreset] = [
        DevicePreset(name: "iPad mini", size: CGSize(width: 744, height: 1133), kind: .tablet),
        DevicePreset(name: "iPad Air 11″", size: CGSize(width: 820, height: 1180), kind: .tablet),
        DevicePreset(name: "iPad Pro 13″", size: CGSize(width: 1032, height: 1376), kind: .tablet),
    ]

    static let all = phones + tablets

    static let defaultPhone = phones[1]
    static let defaultTablet = tablets[1]

    static func custom(_ size: CGSize) -> DevicePreset {
        DevicePreset(name: "Custom", size: size, kind: .custom)
    }

    /// Phones get a mobile user agent so sites serve their phone layout.
    /// iPads keep the desktop one: iPadOS Safari presents itself as a Mac by default.
    var userAgent: String? {
        switch kind {
        case .phone where name.hasPrefix("Android"):
            "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36"
        case .phone:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        case .tablet, .custom:
            nil
        }
    }

    /// "iPad mini · 744×1133" (plain digits, no grouping separators).
    var menuTitle: String {
        "\(name) · \(Int(size.width))×\(Int(size.height))"
    }

    var symbol: String {
        switch kind {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .custom: "rectangle.dashed"
        }
    }
}

/// What a responsive preview column shows: a device and its orientation.
struct DeviceFrame: Hashable {
    var preset: DevicePreset
    var isLandscape = false

    /// The CSS viewport the page lays out in.
    var viewport: CGSize {
        isLandscape ? CGSize(width: preset.size.height, height: preset.size.width) : preset.size
    }

    static let headerHeight: CGFloat = 44
    static let padding: CGFloat = 14
    static let minColumnWidth: CGFloat = 340

    /// Scale that fits the viewport into `available` without going above 100%.
    static func scale(for viewport: CGSize, in available: CGSize) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0 else { return 1 }
        return max(0.2, min(1, available.width / viewport.width, available.height / viewport.height))
    }

    /// Column width that shows the whole device at the largest scale the stage's
    /// height allows, so the preview is exact at 100% whenever it fits.
    func columnWidth(stageHeight: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let chrome = Self.headerHeight + Self.padding * 2
        let available = CGSize(width: maxWidth - Self.padding * 2, height: stageHeight - chrome)
        let scale = Self.scale(for: viewport, in: available)
        return min(maxWidth, max(Self.minColumnWidth, viewport.width * scale + Self.padding * 2))
    }
}
