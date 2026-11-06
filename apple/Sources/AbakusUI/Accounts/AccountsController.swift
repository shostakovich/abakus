import AbakusCore
import Foundation
import Observation

enum BalanceSignChoice: Hashable, Sendable {
    case correct, fix
}

enum CloseAccountChoice: Hashable, Sendable {
    case cancel, close
}

@MainActor
@Observable
public final class AccountsController {
    public let store: any BudgetStoring
    public let navigation: NavigationState
    public let dialogs: DialogStack
    @ObservationIgnored weak var sidebar: SidebarViewModel?
    public internal(set) var addForm: AddAccountForm?
    public internal(set) var editForm: EditAccountForm?
    @ObservationIgnored var today: () -> DateWithoutTime = { .today() }

    init(store: any BudgetStoring, navigation: NavigationState, dialogs: DialogStack = DialogStack()) {
        self.store = store
        self.navigation = navigation
        self.dialogs = dialogs
        today = store.today
    }

    package var formatter: BudgetFormatter { BudgetFormatter(metaData: store.budget.budgetMetaData) }

    public var isPresenting: Bool { addForm != nil || editForm != nil }

    public func addAccountClicked() {
        guard addForm == nil else { return }
        addForm = AddAccountForm(balanceText: formatter.currencySimple(0))
    }

    /// Tracking accounts may hold debts, so only budget accounts ask about a negative balance.
    static func isUnexpectedlyNegative(_ amount: Decimal, in type: AccountKind) -> Bool {
        type.isBudgetAccount && amount < 0
    }

    public func addCancelled() {
        addForm = nil
    }

    public func createAccountClicked() {
        guard let form = addForm else { return }
        let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try store.budget.validateAccountName(name)
        } catch {
            dialogs.show(.message("Bitte einen anderen Kontonamen wählen.", message(for: error)))
            return
        }
        var amount: Decimal = 0
        if !form.balanceText.isEmpty {
            guard let parsed = formatter.parseBalance(form.balanceText) else {
                dialogs.show(.invalidBalance(form.balanceText, bold: true))
                return
            }
            amount = parsed
        }
        guard Self.isUnexpectedlyNegative(amount, in: form.type) else {
            create(form, amount: amount)
            return
        }
        let text = formatter.currency(amount)
        dialogs.ask(
            TaskDialog<BalanceSignChoice>(
                instruction: "Soll der Saldo negativ sein? (\(text))",
                content: "Du hast <b>\(text)</b> eingegeben, aber diese Kontoart hat normalerweise einen "
                    + "positiven Saldo.",
                buttons: [
                    .init(.correct, title: "Der Betrag stimmt"),
                    .init(.fix, title: "Korrigieren", isDefault: true),
                ],
                dismissal: .fix)
        ) { [weak self] answer in
            guard let self, answer.choice == .correct, let form = addForm else { return }
            create(form, amount: amount)
        }
    }

    private func create(_ form: AddAccountForm, amount: Decimal) {
        let new = NewAccount(name: form.name, kind: form.type, startingBalance: amount, startDate: today())
        do {
            try store.perform(.addAccount(new))
        } catch {
            dialogs.show(.message("Bitte einen anderen Kontonamen wählen.", message(for: error)))
            return
        }
        addForm = nil
        select(.account(new.id))
    }

    public func editAccountRequested(_ accountId: String) {
        guard editForm == nil, let account = store.budget.account(withId: accountId) else { return }
        sidebar?.reveal(.account(accountId))
        editForm = EditAccountForm(account: account)
    }

    public func editCancelled() {
        editForm = nil
    }

    public func editDoneClicked() {
        guard let form = editForm else { return }
        if applyEdits(form) { editForm = nil }
    }

    /// Done: the name is validated only when it differs from the current one ignoring case.
    @discardableResult
    private func applyEdits(_ form: EditAccountForm, closing: Bool = false) -> Bool {
        guard var account = store.budget.account(withId: form.accountId) else { return true }
        if form.name.lowercased() != account.name.lowercased() {
            let trimmed = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                try store.budget.validateAccountName(trimmed, excluding: account.id)
            } catch BudgetError.emptyAccountName {
                dialogs.show(.message("Bitte einen Kontonamen eingeben.", "Der Kontoname darf nicht leer sein."))
                return false
            } catch BudgetError.duplicateAccountName {
                dialogs.show(
                    .message(
                        "Bitte einen anderen Kontonamen wählen.", "Es gibt schon ein Konto „\(trimmed)“."))
                return false
            } catch {
                dialogs.show(.message("Bitte einen anderen Kontonamen wählen.", message(for: error)))
                return false
            }
        }
        account.name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.kind = form.type
        if closing { account.closed = true }
        try? store.perform(.editAccount(account))
        return true
    }

    /// Asks once; the closed account stays on screen with its banner.
    public func closeAccountClicked() {
        guard let form = editForm, form.canClose, let account = store.budget.account(withId: form.accountId)
        else { return }
        let balance = store.budget.balances(forAccount: account.id).working
        dialogs.ask(
            TaskDialog<CloseAccountChoice>(
                instruction: "Konto „\(account.name)“ schließen?",
                content: balance == 0
                    ? "Du kannst es später wieder öffnen."
                    : "Es hat noch einen Saldo von <b>\(formatter.currency(balance))</b>.",
                buttons: [.init(.cancel, title: "Abbrechen"), .init(.close, title: "Schließen", isDefault: true)],
                dismissal: .cancel)
        ) { [weak self] answer in
            guard let self, answer.choice == .close, let form = editForm, form.accountId == account.id else { return }
            if applyEdits(form, closing: true) { editForm = nil }
        }
    }

    private func select(_ selection: SidebarSelection) {
        if let sidebar {
            sidebar.select(selection)
        } else {
            navigation.selection = selection
        }
    }

    private func message(for error: Error) -> String {
        (error as? BudgetError)?.errorDescription ?? error.localizedDescription
    }
}
