import SwiftUI

/// The register's toolbar actions and key equivalents as menu bar commands.
public enum RegisterCommand: CaseIterable, Sendable {
    case addTransaction, search

    @MainActor public var title: String {
        switch self {
        case .addTransaction: RegisterViewModel.addTitle
        case .search: "Suchen"
        }
    }

    public var shortcut: KeyboardShortcut? {
        switch self {
        case .addTransaction: KeyboardShortcut("n", modifiers: .command)
        case .search: KeyboardShortcut("f", modifiers: .command)
        }
    }

    @MainActor public func isEnabled(in register: RegisterViewModel) -> Bool {
        switch self {
        case .addTransaction: register.canAddTransactions
        case .search: true
        }
    }

    /// Like the register's keys, a command waits while a dialog, popup or menu is open.
    @MainActor public func perform(in register: RegisterViewModel) {
        guard register.acceptsRegisterKeys, isEnabled(in: register) else { return }
        switch self {
        case .addTransaction: register.addTransactionClicked()
        case .search: register.search.focus()
        }
    }

    public static func matching(_ key: KeyEquivalent, modifiers: EventModifiers) -> RegisterCommand? {
        allCases.first { $0.shortcut?.key == key && $0.shortcut?.modifiers == modifiers }
    }
}

public struct RegisterCommands: Commands {
    let model: AppModel
    /// iPhone and iPad add a transaction from every screen, as their "+" does.
    let addsEverywhere: Bool
    let addingWaits: Bool

    public init(model: AppModel, addsEverywhere: Bool = false, addingWaits: Bool = false) {
        self.model = model
        self.addsEverywhere = addsEverywhere
        self.addingWaits = addingWaits
    }

    public var body: some Commands {
        CommandMenu("Buchungen") {
            let isShown = model.showsRegister
            command(.addTransaction, isShown: (isShown || addsEverywhere) && !addingWaits)
            Divider()
            command(.search, isShown: isShown)
        }
    }

    private func command(_ command: RegisterCommand, isShown: Bool) -> some View {
        let register = model.register
        return Button(command.title) { command.perform(in: register) }
            .keyboardShortcut(command.shortcut)
            .disabled(!isShown || !command.isEnabled(in: register))
    }
}

/// A register menu as SwiftUI menu items, for the menu bar.
package struct RegisterMenuItemsView: View {
    let items: [RegisterMenuItem]
    let perform: (RegisterMenuAction) -> Void

    package init(items: [RegisterMenuItem], perform: @escaping (RegisterMenuAction) -> Void) {
        self.items = items
        self.perform = perform
    }

    package var body: some View {
        ForEach(items) { item in
            switch item.kind {
            case .separator:
                Divider()
            case .title:
                Text(verbatim: item.title)
            case .action(let action):
                if item.isChecked {
                    Toggle(isOn: Binding(get: { true }, set: { _ in perform(action) })) { label(item) }
                        .disabled(!item.isEnabled)
                } else {
                    Button(role: item.isDestructive ? .destructive : nil) {
                        perform(action)
                    } label: {
                        label(item)
                    }
                    .disabled(!item.isEnabled)
                }
            case .submenu(let children):
                Menu {
                    RegisterMenuItemsView(items: children, perform: perform)
                } label: {
                    label(item)
                }
                .disabled(!item.isEnabled)
            }
        }
        .tint(nil)
    }

    @ViewBuilder
    private func label(_ item: RegisterMenuItem) -> some View {
        if let image = item.systemImage {
            Label(item.title, systemImage: image)
        } else {
            Text(item.title)
        }
        if let subtitle = item.subtitle { Text(subtitle) }
    }
}
