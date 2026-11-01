import AbakusCore
import AbakusUI
import AppKit
import Foundation

/// Opens the reconciliation, scheduler and account states through the view models before rendering.
@MainActor
struct UIHarness {
    enum State: String, CaseIterable {
        case recStatementDialog = "rec-statement-dialog"
        case recFooter = "rec-footer"
        case schedPane = "sched-pane"
        case schedEdit = "sched-edit"
        case accountAdd = "account-add"
        case accountEdit = "account-edit"
        case accountAdjusted = "account-adjusted"
        case accountBalance = "account-balance"
        case accountBalanceCheck = "account-balance-check"
        case renamePayee = "rename-payee"
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
        case .schedEdit:
            try selectAccount("Girokonto")
            try addSchedules()
            register.scheduledToggleClicked()
            edit.settle()
            let id = try require(register.scheduler.scheduledTransactions.first { $0.frequency == .monthly }).id
            register.scheduler.beginEditing(id, column: .memo)
            edit.settle()
            let editor = try require(register.scheduler.editor)
            editor.frequencyClicked()
        case .accountAdd:
            model.accounts.addAccountClicked()
            let form = try require(model.accounts.addForm)
            form.name = "Haushaltskasse"
            form.balanceText = "150,00"
            form.type = .cash
        case .accountEdit:
            let account = try require(store.budget.account(named: "Tagesgeld"))
            model.accounts.editAccountRequested(account.id)
        case .accountAdjusted:
            try selectAccount("Tagesgeld")
            model.accounts.editAccountRequested(try require(store.budget.account(named: "Girokonto")).id)
            model.accounts.adjustBalanceClicked()
            try require(model.accounts.balanceForm).amountText = "2.500,00"
            model.accounts.adjustClicked()
        case .accountBalance, .accountBalanceCheck:
            try selectAccount("Girokonto")
            model.accounts.editAccountRequested(try require(store.budget.account(named: "Girokonto")).id)
            model.accounts.adjustBalanceClicked()
            if state == .accountBalanceCheck {
                try require(model.accounts.balanceForm).amountText = "-25,00"
                edit.settle()
                model.accounts.adjustClicked()
            }
        case .renamePayee:
            try selectAccount("Girokonto")
            register.rowClicked(try require(register.rows.first { $0.payee == "REWE" }), column: nil, modifiers: [])
            register.performMenuAction(.renamePayee)
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
        let schedules: [(Transaction, ScheduledTransactionFrequency, String?)] = [
            (
                Transaction(
                    accountId: giro, date: today.addingDays(3), categoryId: groceries, memo: "Gemüsekiste",
                    amount: -24.90),
                .weekly, "Gemüsekiste Hof Sonnenwiese"
            ),
            (
                Transaction(accountId: giro, date: today.addingDays(9), memo: "Sparrate", amount: -200),
                .twiceAMonth, nil
            ),
        ]
        for (transaction, frequency, payee) in schedules {
            var scheduled = transaction
            if payee == nil, let target = budget.account(named: "Tagesgeld") {
                scheduled.transfer(to: target.id)
            }
            try store.perform(
                .saveScheduledTransaction(
                    ScheduledSave(transaction: scheduled, frequency: frequency, payeeName: payee, isNew: true)))
        }
    }

    private func require<T>(_ value: T?) throws -> T {
        guard let value else { throw SnapshotError.render }
        return value
    }
}
