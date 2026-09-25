import AppKit
import SwiftUI

/// The panel's content: a slim glass header (title, source, Live dot, pin, close)
/// over the element itself.
struct PopOutView: View {
    let popOut: PopOut

    var body: some View {
        VStack(spacing: 0) {
            PopOutHeader(popOut: popOut)
                .frame(height: PopOut.headerHeight)
            ElementView(popOut: popOut)
                .frame(width: popOut.contentSize.width, height: popOut.contentSize.height)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay {
                    switch popOut.state {
                    case .loading:
                        ProgressView().controlSize(.small)
                    case .lost:
                        VStack(spacing: 6) {
                            Text("Couldn't find the element").font(.system(size: 12, weight: .semibold))
                            Button("Try Again", action: popOut.reload).controlSize(.small)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: .rect(cornerRadius: 10))
                    case .live:
                        EmptyView()
                    }
                }
        }
        .background(PanelBackdrop())
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.primary.opacity(0.14), lineWidth: 0.5))
    }
}

private struct PopOutHeader: View {
    let popOut: PopOut

    var body: some View {
        HStack(spacing: 8) {
            LiveDot(state: popOut.state)
            VStack(alignment: .leading, spacing: 0) {
                Text(popOut.pick.label.isEmpty ? popOut.pick.title : popOut.pick.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text(popOut.host)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HeaderButton(symbol: popOut.isPinned ? "pin.fill" : "pin", label: popOut.isPinned ? "Unpin: stay on this Space" : "Pin: show on every Space and over full-screen apps") {
                popOut.isPinned.toggle()
            }
            HeaderButton(symbol: "xmark", label: "Close") { popOut.onClose() }
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .help(popOut.pick.url.absoluteString)
    }
}

private struct LiveDot: View {
    let state: PopOut.State
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(state == .live && pulse ? 0.45 : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
                }
            Text(state == .live ? "Live" : state == .loading ? "Loading" : "Lost")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .live: Color(nsColor: .systemGreen)
        case .loading: Color(nsColor: .systemOrange)
        case .lost: Color(nsColor: .systemRed)
        }
    }
}

private struct HeaderButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The popped-out web view, laid out at the source page's width and offset so only
/// the element's box shows.
private struct ElementView: NSViewRepresentable {
    let popOut: PopOut

    func makeNSView(context: Context) -> ClipView {
        let view = ClipView()
        view.addSubview(popOut.webView)
        return view
    }

    func updateNSView(_ view: ClipView, context: Context) {
        let scale = popOut.scale
        popOut.webView.pageZoom = scale
        popOut.webView.frame = NSRect(
            x: -popOut.rect.minX * scale,
            y: 0,
            width: popOut.pick.layoutWidth * scale,
            height: popOut.rect.height * scale
        )
    }

    final class ClipView: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
    }
}

/// Behind-window glass for the panel, following light and dark mode.
private struct PanelBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
