import AppKit
import SwiftUI

/// A local dev server in the app capsule: framework glyph, port, and a dot that's
/// green while it answers.
struct DevServerIcon: View {
    let server: DevServer
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: server.framework.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(verbatim: "\(server.port)")
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint.gradient, in: .rect(cornerRadius: 8, style: .continuous))
            .opacity(server.isRunning ? 1 : 0.45)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(server.isRunning ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                    .offset(x: 2.5, y: -2.5)
            }
            .scaleEffect(isHovering ? 1.08 : 1)
            .padding(2.5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.hover) { isHovering = hovering } }
        .help("\(server.framework.rawValue) · localhost:\(server.port)\(server.isRunning ? "" : " (stopped)")\n\(server.title)")
        .contextMenu {
            Button("Open") { action() }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(server.url.absoluteString, forType: .string)
            }
        }
        .accessibilityLabel("\(server.framework.rawValue) on port \(server.port), \(server.isRunning ? "running" : "stopped")")
    }

    private var tint: Color {
        switch server.framework {
        case .vite: Color(red: 0.49, green: 0.33, blue: 0.95)
        case .next: Color(white: 0.12)
        case .storybook: Color(red: 1, green: 0.28, blue: 0.52)
        case .angular: Color(red: 0.85, green: 0.1, blue: 0.2)
        case .django: Color(red: 0.05, green: 0.36, blue: 0.23)
        case .rails: Color(red: 0.8, green: 0.1, blue: 0.1)
        case .express, .unknown: Color(nsColor: .systemGray)
        }
    }
}
