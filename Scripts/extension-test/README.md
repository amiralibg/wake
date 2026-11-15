# Extension test fixture

`wake-test-extension/` is a small Manifest V3 extension for checking Wake's extension support by hand:

- **Content script**: every page gets `data-wake-test-extension="injected"` on `<html>` and a purple pill at the bottom left.
- **Background + tabs**: the toolbar badge shows how many tabs (columns) the window has, and updates as columns open, close and get focus.
- **Popup**: shows the active tab's title, the tab count, and how many pages the content script ran on (`storage`).
- **Options**: the popup's button calls `runtime.openOptionsPage()`, which should open a column.

Add it with Settings ▸ Extensions ▸ Choose…, File ▸ Add Extension…, or by dropping the folder on Settings ▸ Extensions.
- **Right-click menu**: "Wake Test: count this page" (and "note this link" on links) sets the badge to `M<n>`.
- **Shortcuts**: ⌥⇧W opens the popup, ⌥⇧K puts `K<tabs>` in the badge. Both are listed on its card in Settings ▸ Extensions.
