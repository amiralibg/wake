import AppKit
import SwiftUI
import WebKit

/// Connects `shared/scripts/passwords.js` to the vault: the menu of saved logins
/// under a focused login field (↑/↓, ↩, Esc work while the field keeps focus), a
/// strong password for sign-up forms, and the "Save password?" island after a
/// sign-in.
@MainActor
@Observable
final class PasswordAutofill {
    static let shared = PasswordAutofill()

    enum MenuItem: Identifiable, Hashable {
        case login(SavedLogin)
        case generate(String)
        case manage

        var id: String {
            switch self {
            case .login(let login): login.id.uuidString
            case .generate: "generate"
            case .manage: "manage"
            }
        }
    }

    struct PendingSave: Identifiable {
        let id = UUID()
        let origin: String
        let host: String
        let username: String
        let password: String
        let isUpdate: Bool
        weak var window: NSWindow?
    }

    private(set) var menuItems: [MenuItem] = []
    private(set) var selection = 0
    private(set) var pendingSave: PendingSave?

    @ObservationIgnored private weak var menuPage: BrowserPage?
    @ObservationIgnored private var field = "password"
    @ObservationIgnored private var fieldRect = CGRect.zero
    @ObservationIgnored private var typed = ""
    @ObservationIgnored private var panel: AutofillPanel?
    @ObservationIgnored private var blurTask: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    /// A sign-in seen without a form submit (a button click, Enter): shown once the
    /// page moves on, so clicking "show password" doesn't ask to save.
    @ObservationIgnored private var candidate: (save: PendingSave, page: WeakPage, url: URL?, at: Date)?
    /// The account name from a username-only step (Google, Microsoft, Apple).
    @ObservationIgnored private var lastUsername: (value: String, site: String, at: Date)?

    private var vault: PasswordVault { .shared }

    // MARK: Messages from the page

    func receive(_ message: [String: Any], from page: BrowserPage) {
        switch message["event"] as? String {
        case "focus":
            blurTask?.cancel()
            field = message["field"] as? String ?? "password"
            fieldRect = Self.rect(message["rect"])
            typed = message["value"] as? String ?? ""
            showMenu(for: page)
        case "input":
            guard menuPage === page else { return }
            typed = message["value"] as? String ?? ""
            showMenu(for: page)
        case "move":
            guard menuPage === page else { return }
            fieldRect = Self.rect(message["rect"])
            positionPanel()
        case "blur":
            // A click on the menu itself comes with a blur first; let it land.
            blurTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, menuPage === page else { return }
                hideMenu()
            }
        case "key":
            guard menuPage === page else { return }
            handleKey(message["key"] as? String ?? "")
        case "username":
            guard let value = message["value"] as? String, !value.isEmpty, let host = page.url?.host() else { return }
            lastUsername = (value, PasswordVault.site(of: host), .now)
        case "submit":
            signedIn(message, on: page)
        default:
            break
        }
    }

    func pageNavigated(_ page: BrowserPage) {
        if menuPage === page { hideMenu() }
        if let candidate, candidate.page.value === page, page.url != candidate.url {
            self.candidate = nil
            if Date.now.timeIntervalSince(candidate.at) < 30 { present(candidate.save) }
        }
    }

    func pageClosed(_ page: BrowserPage) {
        if menuPage === page { hideMenu() }
        if candidate?.page.value === page { candidate = nil }
    }

    // MARK: Menu

    private func showMenu(for page: BrowserPage) {
        guard vault.autofills, let url = page.url, url.scheme == "https" || url.scheme == "http" else { return hideMenu() }
        var items: [MenuItem] = []
        if field == "newPassword" {
            items.append(.generate(PasswordGenerator.strong()))
        } else {
            let logins = vault.logins(for: url).filter {
                field != "username" || typed.isEmpty || $0.username.localizedCaseInsensitiveContains(typed)
            }
            items = logins.prefix(6).map(MenuItem.login)
            if !items.isEmpty { items.append(.manage) }
        }
        guard !items.isEmpty else { return hideMenu() }
        if menuItems.map(\.id) != items.map(\.id) { selection = 0 }
        menuItems = items
        if menuPage !== page {
            menuPage = page
            setScriptMenu(open: true, on: page)
        }
        positionPanel()
    }

    func hideMenu() {
        blurTask?.cancel()
        if let page = menuPage { setScriptMenu(open: false, on: page) }
        menuPage = nil
        menuItems = []
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    func hover(_ index: Int) { selection = index }

    private func handleKey(_ key: String) {
        let count = menuItems.count
        guard count > 0 else { return }
        switch key {
        case "down": selection = (selection + 1) % count
        case "up": selection = (selection - 1 + count) % count
        case "return": choose(menuItems[selection])
        case "escape", "tab": hideMenu()
        default: break
        }
    }

    func choose(_ item: MenuItem) {
        guard let page = menuPage else { return }
        let host = page.url?.host() ?? "this site"
        hideMenu()
        switch item {
        case .login(let login):
            Task {
                guard await vault.authenticate(reason: "fill your password for \(host)") else { return }
                _ = try? await page.webView.callAsyncJavaScript(
                    "return window.__wakePasswords ? window.__wakePasswords.fill(username, password) : false",
                    arguments: ["username": login.username, "password": login.password],
                    in: nil, contentWorld: WebScripts.world
                )
                vault.markUsed(login)
            }
        case .generate(let password):
            Task {
                _ = try? await page.webView.callAsyncJavaScript(
                    "return window.__wakePasswords ? window.__wakePasswords.fillNew(password) : 0",
                    arguments: ["password": password], in: nil, contentWorld: WebScripts.world
                )
            }
        case .manage:
            let browser = BrowserModel.model(for: page.webView.window) ?? BrowserModel.active
            browser?.showSettings(.passwords)
        }
    }

    private func setScriptMenu(open: Bool, on page: BrowserPage) {
        Task {
            _ = try? await page.webView.callAsyncJavaScript(
                "if (window.__wakePasswords) window.__wakePasswords.setMenu(open)",
                arguments: ["open": open], in: nil, contentWorld: WebScripts.world
            )
        }
    }

    /// Puts the menu under the field (above it when there's no room below), as a
    /// child window that doesn't take focus from the page.
    private func positionPanel() {
        guard let page = menuPage, let window = page.webView.window, !menuItems.isEmpty else { return }
        let webView = page.webView
        let scale = webView.pageZoom * webView.magnification
        var rect = CGRect(x: fieldRect.minX * scale, y: fieldRect.minY * scale,
                          width: fieldRect.width * scale, height: fieldRect.height * scale)
        if !webView.isFlipped { rect.origin.y = webView.bounds.height - rect.maxY }
        // The field scrolled out of the column: no menu floating over nothing.
        guard webView.bounds.intersects(rect) else { return hideMenu() }
        let screenRect = window.convertToScreen(webView.convert(rect, to: nil))

        let panel = panel ?? AutofillPanel(content: AutofillMenu(autofill: self))
        self.panel = panel
        let size = CGSize(width: max(screenRect.width, 300), height: AutofillMenu.height(for: menuItems))
        var origin = CGPoint(x: screenRect.minX, y: screenRect.minY - size.height - 4)
        if let screen = window.screen, origin.y < screen.visibleFrame.minY {
            origin.y = screenRect.maxY + 4
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    private static func rect(_ value: Any?) -> CGRect {
        guard let value = value as? [String: Any] else { return .zero }
        return CGRect(x: value["x"] as? Double ?? 0, y: value["y"] as? Double ?? 0,
                      width: value["w"] as? Double ?? 0, height: value["h"] as? Double ?? 0)
    }

    // MARK: Saving

    private func signedIn(_ message: [String: Any], on page: BrowserPage) {
        guard vault.offersToSave, let url = page.url, let origin = PasswordVault.origin(of: url), let host = url.host(),
              let password = message["password"] as? String, !password.isEmpty, !vault.isNeverSave(url) else { return }
        var username = (message["username"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if username.isEmpty, let last = lastUsername, last.site == PasswordVault.site(of: host), Date.now.timeIntervalSince(last.at) < 300 {
            username = last.value
        }
        let existing = vault.logins(for: url).first { PasswordVault.sameHost($0.host, host) && $0.username == username }
        if let existing, existing.password == password {
            vault.markUsed(existing)
            return
        }
        let save = PendingSave(origin: origin, host: host,
                               username: username, password: password, isUpdate: existing != nil, window: page.webView.window)
        if message["origin"] as? String == "submit" {
            present(save)
        } else {
            candidate = (save, WeakPage(value: page), page.url, .now)
        }
    }

    private func present(_ save: PendingSave) {
        withAnimation(.chrome) { pendingSave = save }
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            withAnimation(.chrome) { pendingSave = nil }
        }
    }

    func savePending() {
        guard let pending = pendingSave else { return }
        vault.save(origin: pending.origin, username: pending.username, password: pending.password)
        withAnimation(.chrome) { pendingSave = nil }
    }

    func dismissPending() {
        withAnimation(.chrome) { pendingSave = nil }
    }

    func neverForPending() {
        guard let pending = pendingSave else { return }
        vault.neverSave(pending.host)
        withAnimation(.chrome) { pendingSave = nil }
    }

    struct WeakPage {
        weak var value: BrowserPage?
    }
}

// MARK: - Menu panel

/// A borderless panel that never becomes key, so the page's field keeps focus
/// and typing while the menu is up still goes to the page.
private final class AutofillPanel: NSPanel {
    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .transient]
        contentView = FirstClickHostingView(rootView: content)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Clicks on a window that isn't key still reach the rows.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct AutofillMenu: View {
    let autofill: PasswordAutofill

    static let rowHeight: CGFloat = 40
    static func height(for items: [PasswordAutofill.MenuItem]) -> CGFloat {
        items.reduce(12) { $0 + ($1 == .manage ? 30 : rowHeight) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(autofill.menuItems.enumerated()), id: \.element.id) { index, item in
                row(item, selected: index == autofill.selection)
                    .onHover { if $0 { autofill.hover(index) } }
                    .onTapGesture { autofill.choose(item) }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: .rect(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.primary.opacity(0.12), lineWidth: 0.5))
    }

    @ViewBuilder private func row(_ item: PasswordAutofill.MenuItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            switch item {
            case .login(let login):
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(selected ? 0 : 0.08), in: .rect(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(login.username.isEmpty ? "No user name" : login.username)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Text(login.displayHost)
                        .font(.system(size: 11))
                        .opacity(0.7)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if selected { Text("↩").font(.system(size: 11, weight: .medium)).opacity(0.8) }
            case .generate(let password):
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Use strong password").font(.system(size: 12.5, weight: .medium))
                    Text(password).font(.system(size: 11, design: .monospaced)).opacity(0.75)
                }
                Spacer(minLength: 4)
            case .manage:
                Text("Manage passwords…")
                    .font(.system(size: 12))
                    .opacity(0.75)
                Spacer()
            }
        }
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(height: item == .manage ? 30 : Self.rowHeight)
        .background {
            if selected { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor) }
        }
        .contentShape(.rect)
    }
}

// MARK: - Save island

/// "Save password for github.com?" under the toolbar, after a sign-in. ⌘↩ saves,
/// Esc says not now; it goes away by itself after 45 seconds.
struct SavePasswordIsland: View {
    @Environment(BrowserModel.self) private var browser
    @Environment(\.isZen) private var isZen
    private let autofill = PasswordAutofill.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let pending = autofill.pendingSave, pending.window === browser.window {
                content(pending)
                    .padding(.top, isZen ? Metrics.stageInset : Metrics.toolbarHeight + 2)
                    .padding(.trailing, Metrics.toolbarPadding)
                    .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func content(_ pending: PasswordAutofill.PendingSave) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill").foregroundStyle(.tint)
                Text(pending.isUpdate ? "Update password for \(display(pending.host))?" : "Save password for \(display(pending.host))?")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(pending.username.isEmpty ? "No user name" : pending.username)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(String(repeating: "•", count: min(pending.password.count, 12)))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                if !pending.isUpdate {
                    Button("Never for This Site") { autofill.neverForPending() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                }
                Spacer(minLength: 8)
                Button("Not Now") { autofill.dismissPending() }
                Button(pending.isUpdate ? "Update" : "Save") { autofill.savePending() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("⌘↩")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 330)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55), in: .rect(cornerRadius: 16, style: .continuous))
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), vibrantContent: false)
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Save password")
    }

    private func display(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
