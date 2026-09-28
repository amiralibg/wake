import Foundation

/// Scripts for Pop Out: the element picker (in the source page) and the isolation
/// script that keeps a popped-out copy of the page showing only that element
/// (`shared/scripts/popout-*.js`).
enum PopOutScripts {
    /// Hover to outline an element, ↑/↓ to widen or narrow the choice, click to pick,
    /// Esc to cancel. Posts `popOutPick` with a CSS selector and the element's rect
    /// in document coordinates (CSS pixels).
    static func picker(handler: String) -> String {
        SharedScript.popOutPicker.source(["channel": handler])
    }

    static let stopPicker = "window.__wakePick && window.__wakePick.stop();"

    /// Runs in the popped-out copy: finds the element (waiting for pages that render
    /// late), hides fixed and sticky chrome around it, and keeps it scrolled to the
    /// top of a viewport exactly its height. Reports the element's size as it changes.
    static func isolate(selector: String, handler: String) -> String {
        SharedScript.popOutIsolate.source(["selector": selector, "channel": handler])
    }
}
