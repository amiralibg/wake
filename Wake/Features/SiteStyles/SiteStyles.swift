import Observation
import SwiftUI
import WebKit

/// Your own CSS for a site (Settings ▸ Appearance ▸ Site styles), like Arc's Boosts
/// without the extension: a readable width, a font you like, a hidden banner.
struct SiteStyle: Codable, Identifiable, Hashable {
    var id = UUID()
    /// "github.com" covers its subdomains too.
    var site: String
    var css: String
    var isEnabled = true
}

/// Keeps the styles and puts them into pages through `shared/scripts/site-styles.js`.
/// New pages get them at document start, so there's no flash; open pages are
/// updated in place when a style changes.
@MainActor
@Observable
final class SiteStyles {
    static let shared = SiteStyles()

    private(set) var styles: [SiteStyle] = []
    /// Whether anything changed since launch, after which pages made earlier
    /// (whose script carries the launch-time list) are updated on every load.
    @ObservationIgnored private var changedSinceLaunch = false

    private static let key = "siteStyles"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([SiteStyle].self, from: data) {
            styles = stored
        }
    }

    /// The list the page script takes.
    var payload: [[String: String]] {
        styles.filter(\.isEnabled).map { ["site": $0.site, "css": $0.css] }
    }

    func style(for url: URL?) -> SiteStyle? {
        guard let host = url?.host()?.lowercased() else { return nil }
        return styles.first { host == $0.site || host.hasSuffix("." + $0.site) }
    }

    func save(_ style: SiteStyle) {
        var style = style
        style.site = Self.normalize(style.site)
        guard !style.site.isEmpty else { return }
        if let index = styles.firstIndex(where: { $0.id == style.id }) {
            styles[index] = style
        } else {
            styles.append(style)
        }
        persist()
    }

    func delete(_ style: SiteStyle) {
        styles.removeAll { $0.id == style.id }
        persist()
    }

    func setEnabled(_ enabled: Bool, for style: SiteStyle) {
        guard let index = styles.firstIndex(where: { $0.id == style.id }) else { return }
        styles[index].isEnabled = enabled
        persist()
    }

    /// After a navigation, pages whose script predates a change get the current list.
    func pageNavigated(_ page: BrowserPage) {
        guard changedSinceLaunch else { return }
        apply(to: page)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(styles) { UserDefaults.standard.set(data, forKey: Self.key) }
        changedSinceLaunch = true
        for page in BrowserModel.everyPage { apply(to: page) }
    }

    private func apply(to page: BrowserPage) {
        let styles = payload
        Task {
            _ = try? await page.webView.callAsyncJavaScript(
                "if (window.__wakeStyles) window.__wakeStyles.apply(styles)",
                arguments: ["styles": styles], in: nil, contentWorld: WebScripts.world
            )
        }
    }

    static func normalize(_ text: String) -> String {
        var site = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let url = URL(string: site.contains("://") ? site : "https://" + site), let host = url.host() { site = host }
        return site.hasPrefix("www.") ? String(site.dropFirst(4)) : site
    }

    /// Ready-made pieces for the editor.
    static let snippets: [(title: String, css: String)] = [
        ("Readable width", "main, article { max-width: 760px !important; margin-inline: auto !important; }"),
        ("System font", "body, p, li, td, input, textarea { font-family: -apple-system, system-ui, sans-serif !important; }"),
        ("Bigger text", "html { font-size: 112% !important; }"),
        ("No sticky headers", "header, nav, [class*=\"sticky\"], [class*=\"Sticky\"] { position: static !important; }"),
        ("No animations", "*, *::before, *::after { animation: none !important; transition: none !important; }"),
    ]
}

/// Adds or edits one site's style. Opened from Settings or ⌘K ▸ Style This Site.
struct SiteStyleEditor: View {
    @State var style: SiteStyle
    let isNew: Bool
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New site style" : "Style for \(style.site)")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 8) {
                Text("Site").foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                TextField("example.com", text: $style.site).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 6) {
                Text("Add").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(SiteStyles.snippets, id: \.title) { snippet in
                    Button(snippet.title) {
                        style.css += (style.css.isEmpty || style.css.hasSuffix("\n") ? "" : "\n") + snippet.css + "\n"
                    }
                    .controlSize(.small)
                }
            }
            CodeTextEditor(text: $style.css)
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.15), lineWidth: 0.5))
            Text("Applies to the site and its subdomains, on top of the page's own styles. Use !important to win over them.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        SiteStyles.shared.delete(style)
                        done()
                    }
                }
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    SiteStyles.shared.save(style)
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(SiteStyles.normalize(style.site).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
