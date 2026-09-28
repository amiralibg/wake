import Foundation

/// Scripts run on demand: the component inspector and the JSON viewer.
enum DevOverlayScripts {
    /// Hover to see the component under the pointer (React, Vue, Svelte), its size and
    /// source file; click to open it in the editor; Esc to stop. Runs in the page world,
    /// because framework internals (`__reactFiber$…`, `__vueParentComponent`) live there.
    /// Installs `window.__wakeInspect` (`shared/scripts/component-inspector.js`).
    ///
    /// Limitation: React only records source files in development builds, and React 19
    /// dropped `_debugSource`, so there it shows the component name without a file.
    @MainActor static var inspector: String { SharedScript.componentInspector.source(["channel": DevScripts.handlerName]) }

    /// Replaces a raw JSON document with a formatted, collapsible tree.
    /// Returns true if the page was JSON.
    static var jsonViewer: String { SharedScript.jsonViewer.source() }
}
