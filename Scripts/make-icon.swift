// Draws Wake's app icon and writes the AppIcon asset set.
// Run from the repository root: swift Scripts/make-icon.swift
//
// The trail as the mark: three glass columns fading to the right like the wake
// behind a boat, over the orange / violet / teal wash of Wake's window backdrop.

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
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(bodyPath)
    context.setFillColor(color(0x1C2150))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()

    // Base: deep indigo to violet.
    let base = CGGradient(colorsSpace: space, colors: [color(0x1B1C5C), color(0x4A33C4)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(base, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 924, y: 924), options: [])

    // The backdrop's three glows.
    func glow(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32, _ alpha: CGFloat) {
        let gradient = CGGradient(colorsSpace: space, colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    glow(CGPoint(x: 150, y: 930), 470, 0xF59A5B, 0.8)    // orange, top left
    glow(CGPoint(x: 930, y: 700), 560, 0x7C5CFF, 0.75)   // violet, right
    glow(CGPoint(x: 520, y: 60), 520, 0x19B3A6, 0.80)    // teal, bottom

    // The wake: two swells rolling out from under the focused column and fading
    // as they trail off to the right.
    context.setLineCap(.round)
    for (index, alpha) in [0.55, 0.32].enumerated() {
        let y = 262 - CGFloat(index) * 50
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: 196, y: y + 18))
        wave.addCurve(to: CGPoint(x: 540, y: y + 10), control1: CGPoint(x: 300, y: y - 48), control2: CGPoint(x: 430, y: y + 64))
        wave.addCurve(to: CGPoint(x: 868, y: y + 4), control1: CGPoint(x: 650, y: y - 44), control2: CGPoint(x: 770, y: y + 48))
        context.saveGState()
        context.addPath(wave)
        context.setLineWidth(index == 0 ? 15 : 11)
        context.replacePathWithStrokedPath()
        context.clip()
        let fade = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, alpha), color(0xFFFFFF, alpha * 0.15)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(fade, start: CGPoint(x: 196, y: 0), end: CGPoint(x: 868, y: 0), options: [])
        context.restoreGState()
    }

    // The trail: the focused column, then two receding.
    struct Column { let rect: CGRect; let fill: CGFloat; let rim: CGFloat }
    let columns = [
        Column(rect: CGRect(x: 214, y: 316, width: 262, height: 452), fill: 0.96, rim: 1),
        Column(rect: CGRect(x: 502, y: 352, width: 206, height: 380), fill: 0.58, rim: 0.7),
        Column(rect: CGRect(x: 734, y: 386, width: 150, height: 312), fill: 0.30, rim: 0.5),
    ]
    for (index, column) in columns.enumerated() {
        let path = CGPath(roundedRect: column.rect, cornerWidth: 46, cornerHeight: 46, transform: nil)
        context.saveGState()
        if index == 0 {
            context.setShadow(offset: CGSize(width: 0, height: -22), blur: 50, color: color(0x0B0E2A, 0.55))
        }
        context.addPath(path)
        context.setFillColor(color(0xFFFFFF, column.fill))
        context.fillPath()
        context.restoreGState()

        context.addPath(path)
        context.setStrokeColor(color(0xFFFFFF, column.rim))
        context.setLineWidth(3)
        context.strokePath()
    }

    // A hint of a page in the focused column: a header and a few lines.
    let page = columns[0].rect
    let ink = color(0x3B2A9E, 0.9)
    context.setFillColor(ink)
    context.addPath(CGPath(roundedRect: CGRect(x: page.minX + 36, y: page.maxY - 86, width: 120, height: 26), cornerWidth: 13, cornerHeight: 13, transform: nil))
    context.fillPath()
    for (index, width) in [190.0, 160, 180, 120].enumerated() {
        let y = page.maxY - 150 - CGFloat(index) * 46
        context.setFillColor(color(0x3B2A9E, 0.22))
        context.addPath(CGPath(roundedRect: CGRect(x: page.minX + 36, y: y, width: width, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil))
        context.fillPath()
    }

    // Glass sheen across the top of the body.
    let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
    context.restoreGState()

    // Hairline rim.
    context.addPath(bodyPath)
    context.setStrokeColor(color(0xFFFFFF, 0.22))
    context.setLineWidth(3)
    context.strokePath()
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
