import AppKit
import WebKit

/// The web view every page column uses. Adds extensions' items (`contextMenus` /
/// `menus`) to the right-click menu, above Inspect Element as in Chrome.
final class BrowserWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let page = navigationDelegate as? BrowserPage else { return }
        let items = Extensions.menuItems(for: page)
        guard !items.isEmpty else { return }
        let inspect = menu.items.firstIndex { $0.identifier?.rawValue == "WKMenuItemIdentifierInspectElement" }
        var index = inspect ?? menu.items.count
        if index > 0, !menu.items[index - 1].isSeparatorItem {
            menu.insertItem(.separator(), at: index)
            index += 1
        }
        for item in items {
            menu.insertItem(item, at: index)
            index += 1
        }
        if inspect != nil { menu.insertItem(.separator(), at: index) }
    }
}
