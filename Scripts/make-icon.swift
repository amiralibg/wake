// Draws Wake's app icon and writes the AppIcon asset set.
// Run from the repository root: swift Scripts/make-icon.swift
//
// The mark: a page moving forward and leaving its own wake, slimmer and fainter
// copies of itself trailing behind. That's the trail of columns and the name at
// once. Two colours, nothing else.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: "Wake/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Everything is drawn in a 1024-point space and scaled to the target size.
func drawIcon(in context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // macOS icon grid: an 824-point body with a soft shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.3))
    context.addPath(bodyPath)
    context.setFillColor(color(0x2A44F0))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    // One colour, with just enough depth to not look printed.
    let ground = CGGradient(colorsSpace: space, colors: [color(0x3D5BFF), color(0x1F32D6)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(ground, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // The page, and behind it its wake: slimmer, fainter slices of itself.
    let top: CGFloat = 736, height: CGFloat = 448
    let gap: CGFloat = 24
    let parts: [(width: CGFloat, alpha: CGFloat)] = [(18, 0.18), (40, 0.34), (72, 0.58), (256, 1)]
    let total = parts.map(\.width).reduce(0, +) + gap * CGFloat(parts.count - 1)
    var x = 512 - total / 2
    for part in parts {
        let rect = CGRect(x: x, y: top - height, width: part.width, height: height)
        let radius = min(part.width / 2, 58)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(color(0xFFFFFF, part.alpha))
        context.fillPath()
        x += part.width + gap
    }
    context.restoreGState()
}

func render(size: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(in: context)
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: pixels).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(output.path)")
