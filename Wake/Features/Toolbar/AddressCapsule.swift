import SwiftUI

/// Shows where you are; clicking it (or ⌘L) lets you type an address for this column.
/// For a page in a configured project, a switcher on the left moves the same path
/// and query between local, staging and production.
struct AddressCapsule: View {
    let page: BrowserPage?
    let onActivate: () -> Void
    var onSwitchEnvironment: (DevEnvironment) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            if let project, let current = currentEnvironment, project.origins.count > 1 {
                EnvironmentSwitcher(project: project, current: current, onSwitch: onSwitchEnvironment)
                    .padding(.leading, 5)
            }
            Button(action: onActivate) {
                HStack(spacing: 8) {
                    Image(systemName: page?.isSecure == true ? "lock.fill" : "magnifyingglass")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(page?.url == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    Text("⌘L")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: Metrics.capsuleHeight)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 220, idealWidth: 400, maxWidth: 400)
        .glassSurface(Capsule(), interactive: true)
        .help(page?.url?.absoluteString ?? "Search or enter address")
    }

    private var project: DevProject? {
        DevProjectStore.shared.project(for: page?.url)
    }

    private var currentEnvironment: DevEnvironment? {
        guard let url = page?.url else { return nil }
        return project?.environment(of: url)
    }

    private var label: String {
        guard let page, page.url != nil else { return "Search or enter address" }
        return page.host
    }
}

private struct EnvironmentSwitcher: View {
    let project: DevProject
    let current: DevEnvironment
    let onSwitch: (DevEnvironment) -> Void

    var body: some View {
        Menu {
            ForEach(DevEnvironment.allCases.filter { project.origins[$0] != nil }) { environment in
                Button {
                    onSwitch(environment)
                } label: {
                    if environment == current {
                        Label(environment.label, systemImage: "checkmark")
                    } else {
                        Text(environment.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(current.color).frame(width: 6, height: 6)
                Text(current.label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(current.color.opacity(0.16), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(project.name): switch environment, keeping the path")
    }
}

extension DevEnvironment {
    var color: Color {
        switch self {
        case .local: Color(nsColor: .systemGreen)
        case .staging: Color(nsColor: .systemOrange)
        case .production: Color(nsColor: .systemRed)
        }
    }
}
