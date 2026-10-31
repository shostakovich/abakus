import AppKit
import SwiftUI

/// Watches the window's Escape key and left mouse-downs for UI that never takes the focus, such as a callout.
struct WindowEventMonitor: NSViewRepresentable {
    /// A right click does nothing on the budget screen.
    static let events: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown]

    /// Whether the handler took the Escape key.
    var onEscape: (@MainActor () -> Bool)?
    /// The window point in this view's coordinates, top-left origin.
    let onMouseDown: @MainActor (CGPoint) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onEscape = onEscape
        view.onMouseDown = onMouseDown
    }

    final class MonitorView: NSView {
        var onEscape: (@MainActor () -> Bool)?
        var onMouseDown: @MainActor (CGPoint) -> Void = { _ in }
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: WindowEventMonitor.events) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            if event.type == .keyDown {
                return event.keyCode == CalloutDismissal.escapeKeyCode && onEscape?() == true
            }
            onMouseDown(convert(event.locationInWindow, from: nil))
            return false
        }
    }
}
