import AppKit
import SwiftUI

/// Empty toolbar space that drags the window and zooms on double-click,
/// since the titlebar is replaced by our own toolbar. Floating panels, which
/// have no size to zoom to, turn the double-click off.
struct WindowDragArea: NSViewRepresentable {
    var zoomsOnDoubleClick = true

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.zoomsOnDoubleClick = zoomsOnDoubleClick
    }

    final class DragView: NSView {
        var zoomsOnDoubleClick = true

        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 && zoomsOnDoubleClick {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}
