import AppKit
import SwiftUI

/// Window toolbar items live outside the register's view tree, so their anchors come from the views themselves.
@MainActor
final class ToolbarAnchors {
    private var views: [RegisterAnchorID: WeakView] = [:]

    private struct WeakView {
        weak var view: NSView?
    }

    func register(_ view: NSView, as id: RegisterAnchorID) {
        views[id] = WeakView(view: view)
    }

    /// The item's frame in its window's content view, top-left origin like SwiftUI's global space.
    func frame(of id: RegisterAnchorID) -> CGRect? {
        guard let view = views[id]?.view, let content = view.window?.contentView else { return nil }
        let frame = content.convert(view.convert(view.bounds, to: nil), from: nil)
        guard !content.isFlipped else { return frame }
        return CGRect(x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Frames relative to a view whose global frame starts at `origin`.
    func frames(relativeTo origin: CGPoint) -> [RegisterAnchorID: CGRect] {
        var frames: [RegisterAnchorID: CGRect] = [:]
        for id in views.keys {
            frames[id] = frame(of: id)?.offsetBy(dx: -origin.x, dy: -origin.y)
        }
        return frames
    }
}

private struct ToolbarAnchorView: NSViewRepresentable {
    let id: RegisterAnchorID
    let anchors: ToolbarAnchors

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        anchors.register(view, as: id)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchors.register(nsView, as: id)
    }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension View {
    func toolbarAnchor(_ id: RegisterAnchorID, in anchors: ToolbarAnchors) -> some View {
        background(ToolbarAnchorView(id: id, anchors: anchors))
    }
}
