import SwiftUI

/// File ▸ Import from Another Browser: pick a browser profile and what to bring over.
struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [BrowserProfile] = []
    @State private var selection: BrowserProfile.ID?
    @State private var options = BrowserImporter.Options()
    @State private var importer = BrowserImporter()

    private var selected: BrowserProfile? { profiles.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Import from Another Browser").font(.headline)
                Text("Copies what you choose into Wake. The other browser isn't changed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            switch importer.phase {
            case .idle: chooser
            case .running(let step): progress(step)
            case .finished(let report): summary(report)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            profiles = BrowserCatalog.profiles()
            selection = selection ?? profiles.first { $0.engine != .safari }?.id ?? profiles.first?.id
        }
    }

    // MARK: Choosing

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 2) {
                ForEach(profiles) { profile in
                    ProfileRow(profile: profile, isSelected: profile.id == selection) { selection = profile.id }
                }
            }
            .padding(4)
            .background(.primary.opacity(0.04), in: .rect(cornerRadius: 10, style: .continuous))

            if let selected, selected.engine == .safari, !BrowserCatalog.safariIsReadable {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("macOS keeps Safari's history and cookies private. To import them, give Wake Full Disk Access, then reopen this window.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        }
                        .controlSize(.small)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("History", isOn: $options.history)
                Toggle("Searches", isOn: $options.searches)
                Toggle(isOn: $options.cookies) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cookies")
                        Text(cookieNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Unavailable (Safari keeps it where no app can read it): shown off, not
                // greyed-out-but-ticked, which read as "will be imported".
                Toggle(isOn: selected?.supportsSiteData == false ? .constant(false) : $options.siteData) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Site storage")
                        Text("Local storage, so sites remember your settings.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(selected?.supportsSiteData == false)
            }
            .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    guard let selected else { return }
                    Task { await importer.run(selected, options: options) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil || !(options.history || options.searches || options.cookies || options.siteData))
            }
        }
    }

    private var cookieNote: String {
        guard let selected else { return "Keeps you signed in to sites." }
        switch selected.engine {
        case .chromium: return "Keeps you signed in. macOS asks before Wake can read \(selected.browser)'s cookie key."
        case .firefox: return "Keeps you signed in. Container-tab cookies stay behind."
        case .safari: return "Keeps you signed in."
        }
    }

    // MARK: Running

    private func progress(_ step: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(step).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 60)
    }

    private func summary(_ report: BrowserImporter.Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if report.options.history {
                    SummaryLine(symbol: "clock.arrow.circlepath", text: "\(report.pages.formatted()) new pages in History")
                }
                if report.options.searches {
                    SummaryLine(symbol: "magnifyingglass", text: "\(report.searches.formatted()) searches")
                }
                if report.options.cookies {
                    SummaryLine(symbol: "birthday.cake", text: "\(report.cookies.formatted()) cookies")
                }
                if report.options.siteData {
                    SummaryLine(symbol: "internaldrive", text: "Site storage for \(report.sites.formatted()) sites")
                }
            }
            ForEach(report.notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button("Import Another…") { importer.reset() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: BrowserProfile
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Group {
                    if let icon = profile.icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(.secondary).padding(3)
                    }
                }
                .frame(width: 24, height: 24)
                Text(profile.title).font(.system(size: 13))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isSelected ? AnyShapeStyle(.primary.opacity(0.08)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SummaryLine: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol).font(.callout)
    }
}
