import SwiftUI

/// DevTools as a trail column beside the page it inspects: Console and Network,
/// fed by the developer-mode page hooks.
///
/// Limitation: WebKit has no public API to embed Safari's Web Inspector in an app.
/// For elements, styles and the debugger, use Safari ▸ Develop ▸ Wake (pages are
/// marked inspectable).
struct DevToolsColumn: View {
    let target: BrowserPage?
    let onClose: () -> Void

    @Environment(AppearanceSettings.self) private var appearance
    @State private var tab: Tab = .console

    enum Tab: Hashable { case console, network }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let target {
                if !target.isDeveloperMode {
                    offNotice(target)
                } else {
                    switch tab {
                    case .console: ConsolePane(page: target)
                    case .network: NetworkPane(page: target)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: appearance.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous).stroke(.primary.opacity(0.1), lineWidth: 0.5))
        .clipShape(.rect(cornerRadius: appearance.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $tab) {
                Text(consoleLabel).tag(Tab.console)
                Text(networkLabel).tag(Tab.network)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
            if let log = target?.devtools {
                HMRBadge(state: log.hmr, lastUpdate: log.lastHotUpdate)
                Button {
                    tab == .console ? log.clearConsole() : log.clearNetwork()
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Clear")
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderless)
            .help("Close DevTools (⌥⌘I)")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private var consoleLabel: String {
        let errors = target?.devtools.errorCount ?? 0
        return errors > 0 ? "Console · \(errors) ⛔︎" : "Console"
    }

    private var networkLabel: String {
        let count = target?.devtools.network.count ?? 0
        return count > 0 ? "Network · \(count)" : "Network"
    }

    private func offNotice(_ target: BrowserPage) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
            Text("Developer mode is off for this page").font(.headline)
            Text("It's on automatically for localhost. Turn it on to capture the console and network.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280)
            Button("Turn On and Reload") {
                target.developerModeOverride = true
                target.reload()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// HMR connection state for the dev server's hot-reload socket.
struct HMRBadge: View {
    let state: DevToolsLog.HMR
    let lastUpdate: Date?

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .connected(let kind), .disconnected(let kind):
            let connected = if case .connected = state { true } else { false }
            HStack(spacing: 5) {
                Circle()
                    .fill(connected ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
                    .frame(width: 7, height: 7)
                Text(connected ? kind : "\(kind) offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .help(lastUpdate.map { "Last hot update \($0.formatted(.relative(presentation: .named)))" } ?? "Hot reload")
        }
    }
}
