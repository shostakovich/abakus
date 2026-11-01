import SwiftUI

/// The register's toolbar actions and key equivalents as menu bar commands.
public enum RegisterCommand: CaseIterable, Sendable {
    case addTransaction, makeTransfer, approve, toggleCleared, search, timeframe, showReconciled

    @MainActor public var title: String {
        switch self {
        case .addTransaction: RegisterViewModel.addTitle
        case .makeTransfer: RegisterViewModel.transferTitle
        case .approve: "Bestätigen"
        case .toggleCleared: "Gebucht umschalten"
        case .search: "Suchen"
        case .timeframe: "Zeitraum …"
        case .showReconciled: "Abgeglichene Buchungen zeigen"
        }
    }

    public var shortcut: KeyboardShortcut? {
        switch self {
        case .addTransaction: KeyboardShortcut("n", modifiers: .command)
        case .approve: KeyboardShortcut("k", modifiers: .command)
        case .toggleCleared: KeyboardShortcut("c", modifiers: [.command, .shift])
        case .search: KeyboardShortcut("f", modifiers: .command)
        case .makeTransfer, .timeframe, .showReconciled: nil
        }
    }

    @MainActor public func isEnabled(in register: RegisterViewModel) -> Bool {
        switch self {
        case .addTransaction: register.canAddTransactions
        case .makeTransfer: register.canAddTransactions && register.showsTransferButton
        case .approve: register.hasSelection
        case .toggleCleared: register.hasSelection || register.editor != nil
        case .search: true
        case .timeframe: !register.isReconciling
        case .showReconciled: !register.isReconciling && register.isReconciledFilterEnabled
        }
    }

    /// Like the register's keys, a command waits while a dialog, popup or menu is open.
    @MainActor public func perform(in register: RegisterViewModel) {
        guard register.acceptsRegisterKeys, isEnabled(in: register) else { return }
        switch self {
        case .addTransaction: register.addTransactionClicked()
        case .makeTransfer: register.makeTransferClicked()
        case .approve: register.approveKeyPressed()
        case .toggleCleared: register.toggleClearedKeyPressed()
        case .search: register.search.focus()
        case .timeframe: register.search.dateSelectorClicked()
        case .showReconciled: register.setShowingReconciled(!register.isShowingReconciled)
        }
    }

    public static func matching(_ key: KeyEquivalent, modifiers: EventModifiers) -> RegisterCommand? {
        allCases.first { $0.shortcut?.key == key && $0.shortcut?.modifiers == modifiers }
    }
}

public struct RegisterCommands: Commands {
    let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandMenu("Buchungen") {
            let register = model.register
            let isShown = model.showsRegister
            command(.addTransaction, isShown: isShown)
            command(.makeTransfer, isShown: isShown)
            Divider()
            Menu(register.actionButtonTitle.trimmingCharacters(in: .whitespaces)) {
                if isShown && register.hasSelection {
                    RegisterMenuItemsView(
                        items: register.transactionActionsMenu(withTitle: false),
                        perform: register.editTransactionsCommandChosen)
                }
            }
            .disabled(!isShown || !register.hasSelection)
            command(.approve, isShown: isShown)
            command(.toggleCleared, isShown: isShown)
            Divider()
            command(.search, isShown: isShown)
            command(.timeframe, isShown: isShown)
            Toggle(
                RegisterCommand.showReconciled.title,
                isOn: Binding(
                    get: { register.isShowingReconciled },
                    set: { _ in RegisterCommand.showReconciled.perform(in: register) })
            )
            .disabled(!isShown || !RegisterCommand.showReconciled.isEnabled(in: register))
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
struct RegisterMenuItemsView: View {
    let items: [RegisterMenuItem]
    let perform: (RegisterMenuAction) -> Void

    var body: some View {
        ForEach(items) { item in
            switch item.kind {
            case .separator:
                Divider()
            case .title:
                Text(verbatim: item.title)
            case .action(let action):
                if item.isChecked {
                    Toggle(item.title, isOn: Binding(get: { true }, set: { _ in perform(action) }))
                        .disabled(!item.isEnabled)
                } else {
                    Button(item.title) { perform(action) }.disabled(!item.isEnabled)
                }
            case .submenu(let children):
                Menu(item.title) {
                    RegisterMenuItemsView(items: children, perform: perform)
                }
                .disabled(!item.isEnabled)
            }
        }
    }
}
