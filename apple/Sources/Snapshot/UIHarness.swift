import AbakusCore
import AbakusUI
import AppKit
import Foundation

@MainActor
struct UIHarness {
    enum State: String, CaseIterable {
        case recStatementDialog = "rec-statement-dialog"
        case recFooter = "rec-footer"
        case schedPane = "sched-pane"
        case schedEmpty = "sched-empty"
        case schedEdit = "sched-edit"
        case schedCustom = "sched-custom"
        case accountAdd = "account-add"
        case accountEdit = "account-edit"
        case accountClose = "account-close"
        case closedAccounts = "closed-accounts"
        case closedAccount = "closed-account"
        case kasse
        case signIn = "sign-in"
        case payeeSettings = "payee-settings"
        case payeeSettingsMulti = "payee-settings-multi"
        case payeeSettingsEmpty = "payee-settings-empty"
        case payeeSettingsCategory = "payee-settings-category"
    }

    let model: AppModel
    let edit: EditHarness

    private var register: RegisterViewModel { model.register }
    private var store: BudgetStore { model.store }

    func run(_ state: State) throws {
        edit.settle()
        switch state {
        case .recStatementDialog:
            try selectAccount("Kreditkarte")
            register.reconciliation.reconcileClicked()
            try require(register.reconciliation.statementForm).amountText = "250"
        case .recFooter:
            try selectAccount("Girokonto")
            register.reconciliation.reconcileClicked()
            let form = try require(register.reconciliation.statementForm)
            form.amountText = "1.000,00"
            register.reconciliation.begin(form)
            edit.settle()
            let uncleared = register.transactions.filter { $0.cleared == .uncleared }.prefix(2).map(\.id)
            try store.perform(.setCleared(uncleared, .cleared))
        case .schedPane:
            try selectAccount("Girokonto")
            try addSchedules()
            register.scheduledToggleClicked()
        case .schedEmpty:
            try selectAccount("Tagesgeld")
            register.performMenuAction(.toggleScheduler)
        case .schedEdit, .schedCustom:
            try selectAccount("Girokonto")
            try addSchedules()
            edit.settle()
            let repeats: Repeat = state == .schedEdit ? .monthly : .every(1, .week)
            let id = try require(register.scheduler.scheduledTransactions.first { $0.repeats == repeats }).id
            register.scheduler.beginEditing(id)
            if state == .schedCustom {
                edit.settle()
                let editor = try require(register.scheduler.editor)
                editor.repeatCountChosen(2)
            }
        case .accountAdd:
            model.accounts.addAccountClicked()
            let form = try require(model.accounts.addForm)
            form.name = "Haushaltskasse"
            form.balanceText = "150,00"
            form.type = .cash
        case .accountEdit:
            let account = try require(store.budget.account(named: "Tagesgeld"))
            model.accounts.editAccountRequested(account.id)
        case .accountClose:
            try selectAccount("Tagesgeld")
            model.accounts.editAccountRequested(try require(store.budget.account(named: "Tagesgeld")).id)
            edit.settle()
            model.accounts.closeAccountClicked()
        case .closedAccounts:
            model.sidebar.select(.allAccounts)
            edit.settle()
            register.performMenuAction(.closedAccounts)
        case .closedAccount:
            model.sidebar.select(.allAccounts)
            edit.settle()
            register.closedAccountChosen(try require(store.budget.account(named: "Altes Sparbuch")).id)
        case .kasse:
            try selectAccount("Spliit")
        case .signIn:
            break
        case .payeeSettings:
            try selectAccount("Girokonto")
            let rewe = try require(store.budget.payee(named: "REWE")).id
            try store.perform(
                .setPayeeRenameConditions(
                    payeeId: rewe,
                    [
                        PayeeRenameCondition(operator: .startsWith, text: "REWE Markt"),
                        PayeeRenameCondition(operator: .contains, text: "REWE SAGT DANKE"),
                    ]))
            try store.perform(.setPayeesHidden([try require(store.budget.payee(named: "Telekom")).id], true))
            model.openPayeeSettings(payeeName: "REWE")
        case .payeeSettingsMulti:
            try selectAccount("Girokonto")
            model.openPayeeSettings(payeeName: "Aral")
            let dialog = try require(model.payeeSettings)
            let added = try ["REWE", "Stadtwerke"].map { try require(store.budget.payee(named: $0)).id }
            dialog.selectionChanged(to: Set(dialog.selection + added))
        case .payeeSettingsEmpty:
            model.openPayeeSettings(payeeName: nil)
        case .payeeSettingsCategory:
            try selectAccount("Girokonto")
            model.openPayeeSettings(payeeName: "Aral")
            let dialog = try require(model.payeeSettings)
            edit.settle()
            dialog.categoryTextChanged("🛒 All")
        }
        edit.settle()
    }

    private func selectAccount(_ name: String) throws {
        let account = try require(store.budget.account(named: name))
        model.sidebar.select(.account(account.id))
        edit.settle()
    }

    private func addSchedules() throws {
        let budget = store.budget
        let giro = try require(budget.account(named: "Girokonto")).id
        let groceries = try require(budget.category(fullName: "🛒 Alltag: 🛒 Lebensmittel")).id
        let today = DateWithoutTime.today()
        let schedules: [(Transaction, Repeat, String?)] = [
            (
                Transaction(
                    accountId: giro, date: today.addingDays(3), categoryId: groceries, memo: "Gemüsekiste",
                    amount: -24.90),
                .every(1, .week), "Gemüsekiste Hof Sonnenwiese"
            ),
            (
                Transaction(accountId: giro, date: today.addingDays(9), memo: "Sparrate", amount: -200),
                .every(2, .week), nil
            ),
        ]
        for (transaction, repeats, payee) in schedules {
            var scheduled = transaction
            if payee == nil, let target = budget.account(named: "Tagesgeld") {
                scheduled.transfer(to: target.id)
            }
            try store.perform(
                .saveScheduledTransaction(
                    ScheduledSave(transaction: scheduled, repeats: repeats, payeeName: payee, isNew: true)))
        }
    }

    private func require<T>(_ value: T?) throws -> T {
        guard let value else { throw SnapshotError.render }
        return value
    }
}
