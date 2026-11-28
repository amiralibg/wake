import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Passwords: options, then every saved login (locked behind Touch ID),
/// with reused and weak ones flagged, import from other browsers and CSV export.
struct PasswordsSettingsSection: View {
    @State private var vault = PasswordVault.shared
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var expanded: SavedLogin.ID?
    @State private var draft: SavedLogin?
    @State private var status: String?
    @State private var isImporting = false

    enum Filter: Hashable { case all, reused, weak }

    var body: some View {
        @Bindable var vault = vault
        VStack(alignment: .leading, spacing: 16) {
            if let notice = vault.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            SettingsGroup(title: "Options") {
                SettingsRow("passwordsOffer") {
                    Toggle("", isOn: $vault.offersToSave).toggleStyle(.switch).labelsHidden()
                }
                SettingsDivider()
                SettingsRow("passwordsAutofill") {
                    Toggle("", isOn: $vault.autofills).toggleStyle(.switch).labelsHidden()
                }
                SettingsDivider()
                SettingsRow("passwordsAuth") {
                    Toggle("", isOn: Binding(
                        get: { vault.requiresAuthentication },
                        set: { newValue in
                            // Turning the lock off is itself behind the lock.
                            if newValue { vault.requiresAuthentication = true } else {
                                Task { if await vault.authenticate(reason: "stop asking before filling passwords") { vault.requiresAuthentication = false } }
                            }
                        }
                    ))
                    .toggleStyle(.switch).labelsHidden()
                }
            }

            if vault.isUnlocked {
                unlockedContent
            } else {
                LockedCard { Task { _ = await vault.authenticate(reason: "show your saved passwords") } }
            }

            if !vault.neverSaveHosts.isEmpty {
                SettingsGroup(title: "Never saved") {
                    ForEach(Array(vault.neverSaveHosts.enumerated()), id: \.element) { index, host in
                        if index > 0 { SettingsDivider() }
                        HStack {
                            Text(host).font(.system(size: 13))
                            Spacer()
                            Button("Allow") { vault.allowSaving(host) }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                    }
                }
            }
        }
        .animation(.snappy, value: vault.isUnlocked)
    }

    // MARK: Unlocked

    @ViewBuilder private var unlockedContent: some View {
        let reused = vault.reusedIDs
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Search \(vault.logins.count) passwords", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))

                importMenu
                    .settingsAnchor("passwordsImport")
                Button("Export…", action: export)
                    .disabled(vault.logins.isEmpty)
                    .settingsAnchor("passwordsExport")
                Button {
                    draft = SavedLogin(origin: "https://", username: "", password: "")
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a password")
                .accessibilityLabel("Add a password")
            }

            HStack(spacing: 6) {
                chip("All", .all)
                chip("Reused \(reused.count)", .reused, warning: !reused.isEmpty)
                let weak = vault.logins.filter { PasswordVault.isWeak($0.password) }.count
                chip("Weak \(weak)", .weak, warning: weak > 0)
                Spacer()
                if isImporting { ProgressView().controlSize(.small) }
                if let status {
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            if let draft {
                SettingsGroup {
                    LoginEditor(login: draft, isNew: true) { saved in
                        if let saved { vault.save(origin: saved.origin, username: saved.username, password: saved.password) }
                        self.draft = nil
                    }
                }
            }

            let shown = filtered(reused: reused)
            SettingsGroup(title: vault.logins.isEmpty ? nil : "Saved passwords") {
                if shown.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, login in
                    if index > 0 { SettingsDivider() }
                    LoginRow(login: login, isReused: reused.contains(login.id), isExpanded: expanded == login.id) {
                        withAnimation(.snappy) { expanded = expanded == login.id ? nil : login.id }
                    }
                }
            }
            .settingsAnchor("passwordsList")
        }
    }

    private var emptyText: String {
        if vault.logins.isEmpty { return "No passwords yet. Sign in to a site and Wake offers to save it, or import from another browser." }
        if !query.isEmpty { return "No passwords match “\(query)”." }
        return filter == .reused ? "No password is used on more than one site." : "No weak passwords."
    }

    private func filtered(reused: Set<UUID>) -> [SavedLogin] {
        var logins = vault.logins
        switch filter {
        case .all: break
        case .reused: logins = logins.filter { reused.contains($0.id) }
        case .weak: logins = logins.filter { PasswordVault.isWeak($0.password) }
        }
        let words = SettingsSearch.tokens(query)
        if !words.isEmpty {
            logins = logins.filter { login in
                words.allSatisfy { login.host.localizedCaseInsensitiveContains($0) || login.username.localizedCaseInsensitiveContains($0) }
            }
        }
        return logins.sorted { $0.displayHost.localizedStandardCompare($1.displayHost) == .orderedAscending }
    }

    private func chip(_ title: String, _ value: Filter, warning: Bool = false) -> some View {
        let selected = filter == value
        return Button(title) { filter = value }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.07)), in: .capsule)
    }

    // MARK: Import and export

    private var importMenu: some View {
        Menu("Import") {
            let profiles = PasswordImport.chromiumProfiles()
            if !profiles.isEmpty {
                Section("From a browser") {
                    ForEach(profiles) { profile in
                        Button(profile.title) { importChromium(profile) }
                    }
                }
            }
            Section("From a file") {
                Button("CSV File (Safari, Firefox, 1Password, Bitwarden)…", action: importCSV)
            }
        }
        .fixedSize()
        .disabled(isImporting)
    }

    private func importChromium(_ profile: BrowserProfile) {
        isImporting = true
        status = nil
        Task {
            let result = await Task.detached { Result { try PasswordImport.chromium(profile) } }.value
            isImporting = false
            switch result {
            case .success(let logins):
                let added = vault.add(logins)
                status = "Imported \(added) of \(logins.count) from \(profile.browser)."
            case .failure(let error):
                status = error.localizedDescription
            }
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose a password export (CSV) from Safari, Firefox, Chrome, 1Password or Bitwarden."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let logins = try PasswordImport.csv(text, source: url.deletingPathExtension().lastPathComponent)
            let added = vault.add(logins)
            status = "Imported \(added) of \(logins.count) from \(url.lastPathComponent). You can delete the file now."
        } catch {
            status = error.localizedDescription
        }
    }

    private func export() {
        Task {
            guard await vault.authenticate(reason: "export your passwords") else { return }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Wake Passwords.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.message = "Anyone who can open this file can read your passwords. Delete it once you've imported it elsewhere."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try PasswordImport.csv(vault.logins).write(to: url, atomically: true, encoding: .utf8)
                status = "Exported \(vault.logins.count) passwords."
            } catch {
                status = "Couldn't write the file: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Rows

private struct LockedCard: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("Passwords are locked").font(.system(size: 13, weight: .semibold))
            Text("Unlock with Touch ID or your Mac's password to see and edit them.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Unlock", action: unlock)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.primary.opacity(0.035), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

private struct LoginRow: View {
    let login: SavedLogin
    let isReused: Bool
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Text(String(login.displayHost.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Self.color(for: login.displayHost), in: .rect(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(login.displayHost).font(.system(size: 13)).lineLimit(1)
                        Text(login.username.isEmpty ? "No user name" : login.username)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if isReused { badge("Reused", .orange) }
                    if PasswordVault.isWeak(login.password) { badge("Weak", .yellow) }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(login.displayHost), \(login.username)")

            if isExpanded {
                LoginEditor(login: login, isNew: false) { _ in toggle() }
                    .transition(.opacity)
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: .capsule)
    }

    /// A steady colour per site, for the letter tile.
    static func color(for host: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red, .brown, .cyan]
        let hash = host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return palette[hash % palette.count]
    }
}

/// Website, user name and password, editable; reveal and copy the password.
private struct LoginEditor: View {
    let login: SavedLogin
    let isNew: Bool
    /// The saved login, or nil when cancelled or deleted.
    let done: (SavedLogin?) -> Void

    @State private var website = ""
    @State private var username = ""
    @State private var password = ""
    @State private var reveals = false
    @State private var copied = false
    @State private var confirmingDelete = false
    private let vault = PasswordVault.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Website") { TextField("https://example.com", text: $website).textFieldStyle(.roundedBorder) }
            field("User name") { TextField("name@example.com", text: $username).textFieldStyle(.roundedBorder) }
            field("Password") {
                HStack(spacing: 6) {
                    Group {
                        if reveals {
                            TextField("Password", text: $password).font(.system(size: 12, design: .monospaced))
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button { reveals.toggle() } label: { Image(systemName: reveals ? "eye.slash" : "eye") }
                        .help(reveals ? "Hide" : "Show")
                    Button(action: copy) { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                        .help("Copy password")
                    Button { password = PasswordGenerator.strong(); reveals = true } label: { Image(systemName: "wand.and.stars") }
                        .help("Make a strong password")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    Text(usage).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { done(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || (!isNew && !isChanged))
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, isNew ? 12 : 0)
        .onAppear {
            website = login.origin
            username = login.username
            password = login.password
        }
        .confirmationDialog("Delete the password for \(login.displayHost)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                vault.delete(login)
                done(nil)
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .trailing)
            content()
        }
    }

    private var normalizedOrigin: String? {
        var address = website.trimmingCharacters(in: .whitespaces)
        if !address.contains("://") { address = "https://" + address }
        guard let url = URL(string: address), url.host() != nil else { return nil }
        return PasswordVault.origin(of: url)
    }

    private var isValid: Bool { normalizedOrigin != nil && !password.isEmpty }
    private var isChanged: Bool { normalizedOrigin != login.origin || username != login.username || password != login.password }

    private var usage: String {
        if let lastUsed = login.lastUsed { return "Last used \(lastUsed.formatted(.relative(presentation: .named)))" }
        return login.source.map { "Imported from \($0)" } ?? "Saved \(login.created.formatted(date: .abbreviated, time: .omitted))"
    }

    private func save() {
        guard let origin = normalizedOrigin else { return }
        var updated = login
        updated.origin = origin
        updated.username = username
        updated.password = password
        if !isNew { vault.update(updated) }
        done(updated)
    }

    /// Marked concealed, so clipboard managers that honour it don't keep a copy.
    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
