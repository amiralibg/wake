import AppKit
import Observation
import SwiftUI

/// The tour's import choice. Owned by `OnboardingView` rather than the step, so an
/// import keeps running, and its summary stays, when you move on while it works.
@MainActor
@Observable
final class OnboardingImport {
    let importer = BrowserImporter()
    var options = BrowserImporter.Options()
    var selection: BrowserProfile.ID?
    private(set) var profiles: [BrowserProfile] = []
    private(set) var safariIsReadable = BrowserCatalog.safariIsReadable
    /// The browser the last import came from, for the summary.
    private(set) var source: String?

    var selected: BrowserProfile? { profiles.first { $0.id == selection } }

    /// Browser names in display order, each once: installed browsers first, Safari last
    /// (it's always listed, and needs Full Disk Access before it can be read).
    var browsers: [String] {
        var seen = Set<String>()
        return profiles.map(\.browser).filter { seen.insert($0).inserted }
    }

    func profiles(of browser: String) -> [BrowserProfile] { profiles.filter { $0.browser == browser } }

    var isIdle: Bool { if case .idle = importer.phase { true } else { false } }

    /// The selection can be imported right now: the tour's primary button says Import.
    var canStart: Bool {
        guard isIdle, let selected, options.history || options.searches || options.cookies || (options.siteData && selected.supportsSiteData) else { return false }
        return selected.engine != .safari || safariIsReadable
    }

    var report: BrowserImporter.Report? {
        if case .finished(let report) = importer.phase { report } else { nil }
    }

    func refresh() {
        safariIsReadable = BrowserCatalog.safariIsReadable
        let found = BrowserCatalog.profiles()
        profiles = found.filter { $0.engine != .safari } + found.filter { $0.engine == .safari }
        if selected == nil {
            selection = profiles.first { $0.engine != .safari }?.id ?? profiles.first?.id
        }
    }

    func select(browser: String) {
        guard isIdle, selected?.browser != browser else { return }
        selection = profiles(of: browser).first?.id
    }

    func start() {
        guard canStart, let selected else { return }
        source = selected.browser
        let options = options
        Task { await importer.run(selected, options: options) }
    }
}

struct ImportStep: View {
    let imports: OnboardingImport

    var body: some View {
        @Bindable var imports = imports
        StepLayout(
            eyebrow: "Switching over",
            title: "Bring your browser along.",
            detail: "Import your history, searches and sign-ins from the browser you use now. It isn't changed, and you can do this later from File ▸ Import."
        ) {
            VStack(spacing: 22) {
                BrowserGrid(imports: imports)
                if let selected = imports.selected, imports.profiles(of: selected.browser).count > 1 {
                    Picker("Profile", selection: $imports.selection) {
                        ForEach(imports.profiles(of: selected.browser)) { profile in
                            Text(profile.profileName ?? "Default").tag(Optional(profile.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(!imports.isIdle)
                }
                phase
                    .frame(minHeight: 76, alignment: .top)
            }
        }
        .onAppear { imports.refresh() }
        // Coming back from System Settings after granting Full Disk Access.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            imports.refresh()
        }
    }

    @ViewBuilder private var phase: some View {
        switch imports.importer.phase {
        case .idle: choices
        case .running(let step):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(step).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            }
            .frame(height: 40)
        case .finished(let report): ImportSummary(report: report, source: imports.source ?? "") { imports.importer.reset() }
        }
    }

    @ViewBuilder private var choices: some View {
        @Bindable var imports = imports
        if let selected = imports.selected, selected.engine == .safari, !imports.safariIsReadable {
            VStack(spacing: 10) {
                Label("macOS keeps Safari's history and cookies private. Give Wake Full Disk Access to import them.", systemImage: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .controlSize(.small)
            }
        } else if let selected = imports.selected {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    IncludeChip(title: "History", isOn: $imports.options.history)
                    IncludeChip(title: "Searches", isOn: $imports.options.searches)
                    IncludeChip(title: "Sign-ins", isOn: $imports.options.cookies)
                    IncludeChip(title: "Site settings", isOn: $imports.options.siteData, isAvailable: selected.supportsSiteData)
                }
                if case .chromium = selected.engine, imports.options.cookies {
                    Text("macOS will ask before Wake can read \(selected.browser)'s cookie key.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
}

/// One card per installed browser, in centred rows of even length (never one left
/// alone on the last row).
private struct BrowserGrid: View {
    let imports: OnboardingImport

    var body: some View {
        let browsers = imports.browsers
        let rows = max(1, (browsers.count + 5) / 6)
        let perRow = max(1, (browsers.count + rows - 1) / rows)
        VStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: browsers.count, by: perRow)), id: \.self) { start in
                HStack(spacing: 12) {
                    ForEach(browsers[start..<min(start + perRow, browsers.count)], id: \.self) { browser in
                        BrowserCard(
                            profile: imports.profiles(of: browser)[0],
                            caption: caption(for: browser),
                            isSelected: imports.selected?.browser == browser
                        ) { withAnimation(.hover) { imports.select(browser: browser) } }
                    }
                }
            }
        }
        .disabled(!imports.isIdle)
    }

    private func caption(for browser: String) -> String? {
        let profiles = imports.profiles(of: browser)
        if profiles.first?.engine == .safari, !imports.safariIsReadable { return "Needs access" }
        return profiles.count > 1 ? "\(profiles.count) profiles" : nil
    }
}

private struct BrowserCard: View {
    let profile: BrowserProfile
    let caption: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let icon = profile.icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "globe").resizable().scaledToFit().padding(6).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 44, height: 44)
                Text(profile.browser)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Text(caption ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(width: 116, height: 112)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.white.opacity(isHovering ? 0.08 : 0.05)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.1)), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(.hover) { isHovering = hovering } }
        .accessibilityLabel([profile.browser, caption].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// What comes over, as pills you switch on and off.
private struct IncludeChip: View {
    let title: String
    @Binding var isOn: Bool
    var isAvailable = true

    var body: some View {
        let included = isOn && isAvailable
        Button { isOn.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(included ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.4)))
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(included ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.white.opacity(0.06)), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(included ? 0 : 0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.4)
        .help(isAvailable ? "" : "Safari keeps site storage where no other app can read it")
        .accessibilityValue(included ? "On" : "Off")
    }
}

private struct ImportSummary: View {
    let report: BrowserImporter.Report
    let source: String
    let importAnother: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label(headline, systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            ForEach(report.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
            }
            Button("Import another browser", action: importAnother)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tint)
                .frame(minHeight: 28)
                .contentShape(.rect)
        }
    }

    private var headline: String {
        var parts: [String] = []
        if report.options.history { parts.append("\(report.pages.formatted()) pages") }
        if report.options.searches { parts.append("\(report.searches.formatted()) searches") }
        if report.options.cookies { parts.append("\(report.cookies.formatted()) cookies") }
        if report.options.siteData, report.sites > 0 { parts.append("settings for \(report.sites.formatted()) sites") }
        guard !parts.isEmpty else { return "Done." }
        return "Brought over \(ListFormatter.localizedString(byJoining: parts)) from \(source)."
    }
}
