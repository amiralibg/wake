import SwiftUI

/// A responsive preview: the page laid out at a real device's CSS size (width and
/// height), shown whole. When the device is taller than the stage it's scaled down
/// with page zoom, which keeps the CSS viewport at the device size, so media
/// queries, `innerWidth` and `innerHeight` all match the device.
struct DevicePreviewColumn: View {
    let page: BrowserPage
    let onClose: () -> Void

    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        if let device = page.device {
            VStack(spacing: 0) {
                DevicePreviewHeader(page: page, device: device, onClose: onClose)
                Divider()
                GeometryReader { proxy in
                    let available = CGSize(
                        width: proxy.size.width - DeviceFrame.padding * 2,
                        height: proxy.size.height - DeviceFrame.padding * 2
                    )
                    let scale = DeviceFrame.scale(for: device.viewport, in: available)
                    let radius = (device.preset.kind == .phone ? 38 : 20) * scale
                    PageWebView(page: page, cornerRadius: radius)
                        .frame(width: device.viewport.width * scale, height: device.viewport.height * scale)
                        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: radius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.primary.opacity(0.18), lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .onChange(of: scale, initial: true) { _, scale in page.setZoom(scale) }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: appearance.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous).stroke(.primary.opacity(0.1), lineWidth: 0.5))
            .clipShape(.rect(cornerRadius: appearance.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        }
    }
}

/// Device picker, exact size (editable), rotate, scale, reload and close.
private struct DevicePreviewHeader: View {
    let page: BrowserPage
    let device: DeviceFrame
    let onClose: () -> Void

    @State private var width = ""
    @State private var height = ""

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                DevicePresetButtons { preset in
                    page.device = DeviceFrame(preset: preset, isLandscape: device.isLandscape)
                }
            } label: {
                Label(device.preset.name, systemImage: device.preset.symbol)
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Device")

            HStack(spacing: 3) {
                sizeField($width)
                Text("×").foregroundStyle(.secondary)
                sizeField($height)
            }
            .font(.system(size: 11.5).monospacedDigit())

            Button {
                page.device?.isLandscape.toggle()
            } label: {
                Image(systemName: "rotate.right").font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Rotate")

            Spacer(minLength: 0)

            Text(page.zoom, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .help(page.zoom < 0.999 ? "Scaled to fit the column; the page still lays out at the full device size" : "Actual size")
            Button(action: page.reload) {
                Image(systemName: "arrow.clockwise").font(.system(size: 11.5))
            }
            .buttonStyle(.borderless)
            .help("Reload preview")
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderless)
            .help("Close preview")
        }
        .padding(.horizontal, 12)
        .frame(height: DeviceFrame.headerHeight)
        .onChange(of: device.viewport, initial: true) { _, size in
            width = "\(Int(size.width))"
            height = "\(Int(size.height))"
        }
    }

    private func sizeField(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .frame(width: 40)
            .padding(.vertical, 3)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: 5, style: .continuous))
            .onSubmit(applyCustomSize)
            .help("Type a width or height and press Return")
    }

    /// Typed sizes are in the current orientation.
    private func applyCustomSize() {
        guard let w = Double(width), let h = Double(height), w >= 200, h >= 200, w <= 3000, h <= 3000 else {
            width = "\(Int(device.viewport.width))"
            height = "\(Int(device.viewport.height))"
            return
        }
        let size = CGSize(width: w, height: h)
        guard size != device.viewport else { return }
        page.device = DeviceFrame(preset: .custom(size))
    }
}
