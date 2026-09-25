import AppKit

/// Makes sure there's always a browser window.
///
/// Limitation: SwiftUI restores windows under a name built from the root view's
/// modifier chain. When that chain changes between builds, or on a first launch,
/// nothing restores and the WindowGroup opens no window. SwiftUI has no pre-macOS 15
/// API for "present a window at launch" (`defaultLaunchBehavior` is 15+), so we
/// trigger the File ▸ New Window command ourselves when no window is up.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MainActor.assumeIsolated { Self.openWindowIfNeeded() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.openWindowIfNeeded() }
        return true
    }

    @MainActor
    private static func openWindowIfNeeded() {
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        let fileMenu = NSApp.mainMenu?.items.first { $0.submenu?.items.contains { $0.keyEquivalent == "n" } == true }?.submenu
        guard let newWindow = fileMenu?.items.first(where: { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command }),
              let action = newWindow.action else { return }
        NSApp.sendAction(action, to: newWindow.target, from: newWindow)
    }
}
