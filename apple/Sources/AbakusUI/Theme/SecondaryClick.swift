import AppKit
import SwiftUI

/// Covers its view but takes only secondary clicks (right or Control-click); every other event passes through.
struct SecondaryClickCatcher: NSViewRepresentable {
    let offset: CGSize
    let menu: @MainActor (CGPoint) -> [RegisterMenuItem]?
    let perform: @MainActor (RegisterMenuAction) -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.offset = offset
        view.menuItems = menu
        view.perform = perform
        view.presenter = context.environment.menuPresenter
    }

    final class CatcherView: NSView {
        var offset = CGSize(width: 1, height: 1)
        var menuItems: @MainActor (CGPoint) -> [RegisterMenuItem]? = { _ in nil }
        var perform: @MainActor (RegisterMenuAction) -> Void = { _ in }
        var presenter = MenuPresenter.native
        private var isHandingOn = false

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isHandingOn, let event = NSApp.currentEvent else { return nil }
            let isSecondary =
                event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return isSecondary ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            open(event)
        }

        override func mouseDown(with event: NSEvent) {
            open(event)
        }

        private func open(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let items = menuItems(point) else {
                isHandingOn = true
                window?.sendEvent(event)
                isHandingOn = false
                return
            }
            guard !items.isEmpty else { return }
            presenter.present(items, CGPoint(x: point.x + offset.width, y: point.y + offset.height), self, perform)
        }
    }
}

extension View {
    /// `menu` gets the click point (top-left origin); nil passes the click on, an empty menu takes it.
    func onSecondaryClick(
        offset: CGSize = CGSize(width: 1, height: 1),
        perform: @escaping @MainActor (RegisterMenuAction) -> Void = { _ in },
        menu: @escaping @MainActor (CGPoint) -> [RegisterMenuItem]?
    ) -> some View {
        overlay(SecondaryClickCatcher(offset: offset, menu: menu, perform: perform))
    }
}
