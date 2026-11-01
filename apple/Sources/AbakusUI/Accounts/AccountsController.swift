import AbakusCore
import Foundation
import Observation

enum BalanceSignChoice: Hashable, Sendable {
    case correct, fix
}

@MainActor
@Observable
public final class AccountsController {
    public let store: any BudgetStoring
    public let navigation: NavigationState
    public let dialogs: DialogStack
    @ObservationIgnored weak var sidebar: SidebarViewModel?
    @ObservationIgnored weak var register: RegisterViewModel?
    public internal(set) var addForm: AddAccountForm?
    public internal(set) var editForm: EditAccountForm?
    public internal(set) var balanceForm: AdjustBalanceForm?
    @ObservationIgnored var today: () -> DateWithoutTime = { .today() }

    init(store: any BudgetStoring, navigation: NavigationState, dialogs: DialogStack = DialogStack()) {
        self.store = store
        self.navigation = navigation
        self.dialogs = dialogs
        today = store.today
    }

    var formatter: BudgetFormatter { BudgetFormatter(metaData: store.budget.budgetMetaData) }

    public var isPresenting: Bool { addForm != nil || editForm != nil || balanceForm != nil }

    public func addAccountClicked() {
        guard addForm == nil else { return }
        addForm = AddAccountForm(
            name: uniqueName("Neues Konto"), balanceText: formatter.currencySimple(0), date: today())
    }

    /// The prefix, then " 2", " 3", … while an account (or Alle Konten) has the name.
    func uniqueName(_ prefix: String) -> String {
        let taken = Set(
            store.budget.accounts.map { $0.name.lowercased() } + [Account.allAccountsName.lowercased()])
        var candidate = prefix
        var counter = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(prefix) \(counter)"
            counter += 1
        }
        return candidate
    }

    /// Tracking accounts may hold debts, so only budget accounts ask about a negative balance.
    static func isUnexpectedlyNegative(_ amount: Decimal, in type: AccountKind) -> Bool {
        type.isBudgetAccount && amount < 0
    }

    public func addCancelled() {
        addForm = nil
    }

    public func createAccountClicked() {
        guard let form = addForm, let type = form.type else { return }
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
        if Self.isUnexpectedlyNegative(amount, in: type) {
            let text = formatter.currency(amount)
            dialogs.ask(
                TaskDialog<BalanceSignChoice>(
                    instruction: "Soll der Anfangssaldo negativ sein? (\(text))",
                    content: "Du hast <b>\(text)</b> eingegeben, aber diese Kontoart hat normalerweise einen "
                        + "positiven Saldo.",
                    buttons: [
                        .init(.correct, title: "Der Betrag stimmt"),
                        .init(.fix, title: "Korrigieren", isDefault: true),
                    ],
                    dismissal: .fix)
            ) { [weak self] answer in
                guard let self, answer.choice == .correct, let form = addForm, let type = form.type else { return }
                create(form, type: type, amount: amount)
            }
            return
        }
        create(form, type: type, amount: amount)
    }

    private func create(_ form: AddAccountForm, type: AccountKind, amount: Decimal) {
        let new = NewAccount(name: form.name, kind: type, startingBalance: amount, startDate: form.date)
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
    private func applyEdits(_ form: EditAccountForm) -> Bool {
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
        try? store.perform(.editAccount(account))
        return true
    }

    public func adjustBalanceClicked() {
        guard let form = editForm, let account = store.budget.account(withId: form.accountId) else { return }
        editForm = nil
        let working = store.budget.balances(forAccount: account.id).working
        balanceForm = AdjustBalanceForm(
            account: account, hasTransactions: !store.budget.transactions(inAccount: account.id).isEmpty,
            workingBalanceText: formatter.currency(working), amountText: formatter.currencySimple(working))
    }

    public func isClosed(_ form: EditAccountForm) -> Bool {
        store.budget.account(withId: form.accountId)?.closed ?? false
    }

    /// The closed state flips first, then the Done logic runs; the callout closes either way.
    public func closeOrReopenClicked() {
        guard let form = editForm, var account = store.budget.account(withId: form.accountId) else { return }
        editForm = nil
        let neighbour = !account.closed && navigation.selection == .account(account.id) ? neighbour(of: account) : nil
        account.closed.toggle()
        try? store.perform(.editAccount(account))
        applyEdits(form)
        if let neighbour { select(neighbour) }
    }

    /// The nearest open account of the same group, then of the other open group.
    private func neighbour(of account: Account) -> SidebarSelection {
        let collapsed = sidebar?.collapsedGroups ?? []
        let ownGroup: SidebarGroup = account.onBudget ? .budgetAccounts : .offBudgetAccounts
        let otherGroup: SidebarGroup = account.onBudget ? .offBudgetAccounts : .budgetAccounts
        for group in [ownGroup, otherGroup] where !collapsed.contains(group) {
            var candidates = store.budget.accounts(in: group)
            // The tracking group lies below the budget group.
            let index = candidates.firstIndex { $0.id == account.id } ?? (account.onBudget ? 0 : candidates.count)
            candidates.removeAll { $0.id == account.id }
            if let next = candidates.indices.contains(index) ? candidates[index] : candidates.last {
                return .account(next.id)
            }
        }
        return .allAccounts
    }

    private func select(_ selection: SidebarSelection) {
        if let sidebar {
            sidebar.select(selection)
        } else {
            navigation.selection = selection
        }
    }

    public func balanceCancelled() {
        balanceForm = nil
    }

    public func adjustClicked() {
        guard let form = balanceForm, let account = store.budget.account(withId: form.accountId) else { return }
        guard let value = formatter.parseBalance(form.amountText) else {
            dialogs.show(.invalidBalance(form.amountText))
            return
        }
        if Self.isUnexpectedlyNegative(value, in: account.kind) {
            confirmAdjustment(
                to: value, instruction: "Soll der Saldo negativ sein?",
                content: "Du hast \(formatter.currency(value)) eingegeben, aber diese Kontoart hat normalerweise "
                    + "einen positiven Saldo.")
            return
        }
        adjust(form, to: value)
    }

    private func confirmAdjustment(to value: Decimal, instruction: String, content: String) {
        dialogs.ask(
            TaskDialog<BalanceSignChoice>(
                instruction: instruction, content: content,
                buttons: [
                    .init(.fix, title: "Korrigieren"),
                    .init(.correct, title: "Der Betrag stimmt", isDefault: true),
                ],
                dismissal: .fix)
        ) { [weak self] answer in
            guard let self, answer.choice == .correct, let form = balanceForm else { return }
            adjust(form, to: value)
        }
    }

    private func adjust(_ form: AdjustBalanceForm, to value: Decimal) {
        let before = store.budget
        try? store.perform(
            .adjustBalance(BalanceAdjustment(accountId: form.accountId, workingBalance: value, today: today())))
        balanceForm = nil
        let budget = store.budget
        guard let account = budget.account(withId: form.accountId),
            let adjustment = budget.transactions(inAccount: account.id).first(where: {
                before.transaction(withId: $0.id) != $0
            })
        else { return }
        register?.showAdjustment(
            RegisterAdjustmentHelp(
                transactionId: adjustment.id, message: adjustmentMessage(adjustment, in: account)))
    }

    /// What the callout on the new adjustment row says.
    private func adjustmentMessage(_ transaction: Transaction, in account: Account) -> String {
        let budget = store.budget
        let isStart = budget.transactions(inAccount: account.id).count == 1
        let category = budget.categoryDisplayName(transaction.categoryId)
        switch (isStart, category.isEmpty, account.onBudget) {
        case (true, false, _): return "Der Anfangssaldo ist als „\(category)“ gebucht."
        case (true, true, true):
            return "Der Anfangssaldo ist ohne Kategorie gebucht."
        case (true, true, false):
            return "Der Anfangssaldo ist ohne Kategorie gebucht, weil ein Trackingkonto keine braucht."
        case (false, false, _): return "Die Saldoanpassung ist als „\(category)“ gebucht."
        case (false, true, true):
            return "Die Saldoanpassung ist ohne Kategorie gebucht."
        case (false, true, false):
            return "Die Saldoanpassung ist ohne Kategorie gebucht, weil ein Trackingkonto keine braucht."
        }
    }

    private func message(for error: Error) -> String {
        (error as? BudgetError)?.errorDescription ?? error.localizedDescription
    }
}
