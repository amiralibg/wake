import SwiftUI

/// "Add “Dark Reader”?": what the extension is, what it will be able to do, and the
/// parts of it Wake can't run. Also says why an install couldn't go ahead.
struct ExtensionInstallSheet: View {
    let prompt: ExtensionInstallPrompt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch prompt {
            case .request(let request): RequestView(request: request, dismiss: { dismiss() })
            case .alreadyInstalled(let name):
                MessageView(symbol: "checkmark.circle.fill", tint: .green, title: "“\(name)” is already installed", detail: "Find it in Settings ▸ Extensions.", dismiss: { dismiss() })
            case .failed(let reason):
                MessageView(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Couldn't add the extension", detail: reason, dismiss: { dismiss() })
            }
        }
        .frame(width: 420)
    }
}

private struct RequestView: View {
    let request: ExtensionInstallRequest
    let dismiss: () -> Void
    @State private var confirmed = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ExtensionGlyph(image: request.icon, side: 64)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                    .padding(.top, 4)
                Text("Add “\(request.name)”?")
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text([request.version.isEmpty ? nil : "Version \(request.version)", request.origin, "Manifest V\(request.manifestVersion)"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if !request.summary.isEmpty {
                    Text(request.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 14) {
                section("It will be able to") {
                    if request.access.isEmpty {
                        line(symbol: "checkmark.shield", text: "Run without access to your pages or data", tint: .green)
                    } else {
                        ForEach(request.access) { access in
                            line(symbol: access.symbol, text: access.text, tint: access.isBroad ? .orange : .secondary, emphasised: access.isBroad)
                        }
                    }
                }
                if !request.unsupported.isEmpty {
                    section("Won't work in Wake yet") {
                        ForEach(request.unsupported, id: \.self) { text in
                            line(symbol: "minus.circle", text: text, tint: .secondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: .rect(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 0.5))
            .padding(.horizontal, 20)

            HStack {
                Text("Only add extensions you trust.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Extension") {
                    confirmed = true
                    if #available(macOS 15.4, *) { ExtensionLibrary.shared.confirmInstall(request.id) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(20)
        }
        .onDisappear {
            if !confirmed, #available(macOS 15.4, *) { ExtensionLibrary.shared.cancelInstall(request.id) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func line(symbol: String, text: String, tint: Color, emphasised: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13, weight: emphasised ? .medium : .regular))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MessageView: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("OK", action: dismiss)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padding(.top, 6)
        }
        .padding(28)
    }
}
