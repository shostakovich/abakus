import AppKit
import SwiftUI

struct RegisterAnchorKey: PreferenceKey {
    static let defaultValue: [RegisterAnchorID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [RegisterAnchorID: Anchor<CGRect>], nextValue: () -> [RegisterAnchorID: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func registerAnchor(_ id: RegisterAnchorID, isActive: Bool = true) -> some View {
        anchorPreference(key: RegisterAnchorKey.self, value: .bounds) { isActive ? [id: $0] : [:] }
    }
}

@MainActor
final class RegisterMenuTarget: NSObject {
    private let perform: (RegisterMenuAction) -> Void

    init(perform: @escaping (RegisterMenuAction) -> Void) {
        self.perform = perform
    }

    @objc func choose(_ sender: NSMenuItem) {
        if let box = sender.representedObject as? ActionBox { perform(box.action) }
    }

    final class ActionBox: NSObject {
        let action: RegisterMenuAction

        init(_ action: RegisterMenuAction) {
            self.action = action
        }
    }

    func menu(_ items: [RegisterMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            switch item.kind {
            case .separator:
                menu.addItem(.separator())
            case .title:
                let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                entry.isEnabled = false
                menu.addItem(entry)
            case .action(let action):
                let entry = NSMenuItem(title: item.title, action: #selector(choose(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = ActionBox(action)
                entry.isEnabled = item.isEnabled
                entry.state = item.isChecked ? .on : .off
                menu.addItem(entry)
            case .submenu(let children):
                let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                entry.submenu = self.menu(children)
                entry.isEnabled = item.isEnabled
                menu.addItem(entry)
            }
        }
        return menu
    }
}

/// Shows `items` with their top-left corner at `point` in `view` (top-left origin) and returns once they close.
public struct MenuPresenter: Sendable {
    public typealias Present =
        @MainActor (
            _ items: [RegisterMenuItem], _ point: CGPoint, _ view: NSView,
            _ perform: @escaping @MainActor (RegisterMenuAction) -> Void
        ) -> Void

    let present: Present

    public init(_ present: @escaping Present) {
        self.present = present
    }

    public static let native = MenuPresenter { items, point, view, perform in
        let target = RegisterMenuTarget(perform: perform)
        withExtendedLifetime(target) {
            _ = target.menu(items).popUp(positioning: nil, at: point, in: view)
        }
    }
}

extension EnvironmentValues {
    @Entry public var menuPresenter = MenuPresenter.native
}

/// A zero-size view at the layer's origin, so it never takes a click.
struct PopUpMenu: NSViewRepresentable {
    let items: [RegisterMenuItem]?
    /// The menu's top-left corner in the layer.
    let location: CGPoint
    let perform: @MainActor (RegisterMenuAction) -> Void
    let dismiss: @MainActor () -> Void

    func makeNSView(context: Context) -> AnchoredMenuPresenter.OriginView {
        AnchoredMenuPresenter.OriginView()
    }

    func updateNSView(_ view: AnchoredMenuPresenter.OriginView, context: Context) {
        guard let items else {
            view.presentedId = nil
            return
        }
        guard view.presentedId == nil else { return }
        let id = UUID()
        view.presentedId = id
        let (location, perform, dismiss) = (location, perform, dismiss)
        let presenter = context.environment.menuPresenter
        DispatchQueue.main.async { [weak view] in
            guard let view, view.presentedId == id else { return }
            var chosen = false
            presenter.present(items, location, view) { action in
                chosen = true
                perform(action)
            }
            if !chosen { dismiss() }
        }
    }
}

/// Presents the requested menu below its anchor; a zero-size view at the register's origin, so it never takes a click.
struct AnchoredMenuPresenter: NSViewRepresentable {
    let request: RegisterMenuRequest?
    let location: CGPoint?
    let model: RegisterViewModel

    func makeNSView(context: Context) -> OriginView {
        OriginView()
    }

    func updateNSView(_ view: OriginView, context: Context) {
        guard let request, let location, view.presentedId != request.id else { return }
        view.presentedId = request.id
        let model = model
        let presenter = context.environment.menuPresenter
        DispatchQueue.main.async { [weak view] in
            guard let view, model.menuRequest?.id == request.id else { return }
            presenter.present(request.items, location, view) { model.performMenuAction($0) }
            if model.menuRequest?.id == request.id { model.menuDismissed() }
        }
    }

    final class OriginView: NSView {
        var presentedId: UUID?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
