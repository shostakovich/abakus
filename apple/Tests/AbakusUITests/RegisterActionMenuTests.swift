import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterActionMenuTests {
    private func select(_ model: RegisterViewModel, _ ids: [String]) {
        model.clearSelection()
        for id in ids {
            model.rowClicked(model.rows.first { $0.id == id }!, column: nil, modifiers: .command)
        }
    }

    private func titles(_ items: [RegisterMenuItem]) -> [String] {
        items.map { $0.kind == .separator ? "-" : $0.title }
    }

    private func enabled(_ items: [RegisterMenuItem], _ title: String) -> Bool {
        items.item(titled: title)?.isEnabled ?? false
    }

    private func removing(_ ids: Set<String>, from budget: Budget) -> Budget {
        var budget = budget
        budget.transactions.removeAll { ids.contains($0.id) }
        return budget
    }

    @Test func menuListsTheElevenActionsInOrder() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1)
        let (model, _) = fixture.spied()
        select(model, [id])
        #expect(
            titles(model.transactionActionsMenu(withTitle: false)) == [
                "Als gebucht markieren", "Als vorgemerkt markieren", "-", "Bestätigen", "Ablehnen (löschen)", "-",
                "Kategorisieren als", "-", "Gleiche Empfänger umbenennen …", "Empfänger verwalten …", "-",
                "Wiederkehrend machen …", "In geplante Buchungen verschieben …", "-", "In Konto verschieben", "-",
                "Löschen",
            ])
    }

    @Test func contextMenuStartsWithTheSelectionTitle() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1)
        let (model, _) = fixture.spied()
        let items = model.contextMenu(for: model.rows.first { $0.id == id }!) ?? []
        #expect(items.first?.title == "1 ausgewählte Buchung:")
        #expect(items.first?.kind == .title)
        #expect(items[1].kind == .separator)
        #expect(model.selectedTransactionIds == [id])
        model.selectAll()
        #expect(model.contextMenu(for: model.rows[0])?.first?.title == "2 ausgewählte Buchungen:")
    }

    @Test func rightClickKeepsASelectionWithTheRowAndReplacesOneWithout() {
        var fixture = RegisterFixture()
        let first = fixture.add(fixture.giro, -1)
        let second = fixture.add(fixture.giro, -2)
        let third = fixture.add(fixture.giro, -3)
        let (model, _) = fixture.spied()
        select(model, [first, second])
        #expect(
            model.contextMenu(for: model.rows.first { $0.id == second }!)?.first?.title == "2 ausgewählte Buchungen:")
        #expect(Set(model.selectedTransactionIds) == [first, second])
        #expect(model.contextMenu(for: model.rows.first { $0.id == third }!)?.first?.title == "1 ausgewählte Buchung:")
        #expect(model.selectedTransactionIds == [third])
    }

    @Test func clearedItemsFollowTheSelectedStates() {
        var fixture = RegisterFixture()
        let uncleared = fixture.add(fixture.giro, -1)
        let cleared = fixture.add(fixture.giro, -2, cleared: .cleared)
        let (model, _) = fixture.spied()
        select(model, [uncleared])
        var menu = model.transactionActionsMenu(withTitle: false)
        #expect(enabled(menu, "Als gebucht markieren"))
        #expect(!enabled(menu, "Als vorgemerkt markieren"))
        select(model, [cleared])
        menu = model.transactionActionsMenu(withTitle: false)
        #expect(!enabled(menu, "Als gebucht markieren"))
        #expect(enabled(menu, "Als vorgemerkt markieren"))
    }

    @Test func markAsClearedSendsOnlyTheUnclearedRows() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, approved: false, source: .bank)
        let reconciled = fixture.add(fixture.giro, -2, cleared: .reconciled)
        let cleared = fixture.add(fixture.giro, -3, cleared: .cleared)
        let (model, store) = fixture.spied()
        select(model, [a, reconciled, cleared])
        model.performMenuAction(.markCleared)
        model.performMenuAction(.markUncleared)
        #expect(store.commands == [.setCleared([a], .cleared), .setCleared([cleared], .uncleared)])
    }

    @Test func approveAndRejectNeedUnapprovedRows() {
        var fixture = RegisterFixture()
        let plain = fixture.add(fixture.giro, -1, category: fixture.groceries)
        let imported = fixture.add(fixture.giro, -2, category: fixture.groceries, approved: false, source: .bank)
        let (model, store) = fixture.spied()
        select(model, [plain])
        #expect(!enabled(model.transactionActionsMenu(withTitle: false), "Bestätigen"))
        select(model, [plain, imported])
        #expect(enabled(model.transactionActionsMenu(withTitle: false), "Ablehnen (löschen)"))
        model.performMenuAction(.approve)
        #expect(store.commands == [.approveTransactions([imported])])
    }

    @Test func rejectDeletesOnlyTheUnapprovedRows() {
        var fixture = RegisterFixture()
        let plain = fixture.add(fixture.giro, -1, category: fixture.groceries)
        let imported = fixture.add(fixture.giro, -2, category: fixture.groceries, approved: false, source: .bank)
        let (model, store) = fixture.spied()
        select(model, [plain, imported])
        model.performMenuAction(.reject)
        #expect(store.commands == [.deleteTransactions([imported])])
        #expect(model.notifiers.undoSlot?.message == "Buchung gelöscht")
    }

    @Test func singleSelectionItems() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, payee: "REWE")
        let b = fixture.add(fixture.giro, -2, payee: "REWE")
        let transfer = fixture.add(fixture.giro, -3, target: fixture.tagesgeld)
        let (model, _) = fixture.spied()
        model.today = { day("2014-05-01") }
        select(model, [a])
        var menu = model.transactionActionsMenu(withTitle: false)
        #expect(enabled(menu, "Gleiche Empfänger umbenennen …"))
        #expect(enabled(menu, "Wiederkehrend machen …"))
        #expect(enabled(menu, "In geplante Buchungen verschieben …"))
        select(model, [a, b])
        menu = model.transactionActionsMenu(withTitle: false)
        #expect(!enabled(menu, "Gleiche Empfänger umbenennen …"))
        #expect(!enabled(menu, "Wiederkehrend machen …"))
        select(model, [transfer])
        #expect(!enabled(model.transactionActionsMenu(withTitle: false), "Gleiche Empfänger umbenennen …"))
    }

    @Test func moveToSchedulerNeedsAFutureDate() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1)
        let (model, _) = fixture.spied()
        model.today = { day("2014-06-01") }
        select(model, [id])
        #expect(!enabled(model.transactionActionsMenu(withTitle: false), "In geplante Buchungen verschieben …"))
    }

    @Test func categorizeSubmenusFollowTheCategoryListWithNoCategoryLast() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1)
        fixture.budget.categoryGroups.append(CategoryGroup(name: "Empty", position: 99))
        let (model, store) = fixture.spied()
        select(model, [id])
        let submenu = try #require(
            model.transactionActionsMenu(withTitle: false).item(titled: "Kategorisieren als")?.submenu)
        #expect(submenu.first?.title == "Einnahmen:")
        #expect(submenu.first?.submenu?.map(\.title) == ["Zu verteilen"])
        #expect(submenu.last?.title == "(Keine Kategorie)")
        #expect(submenu.item(titled: "Everyday Expenses:")?.submenu?.item(titled: "Groceries") != nil)
        #expect(submenu.item(titled: "Empty:") == nil)
        model.performMenuAction(.categorize(categoryId: fixture.groceries))
        #expect(store.commands == [.categorizeTransactions([id], categoryId: fixture.groceries)])
    }

    @Test func categorizeIsDisabledOffBudget() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.depot, -1)
        let (model, _) = fixture.spied(selection: .account(fixture.depot))
        select(model, [id])
        #expect(!enabled(model.transactionActionsMenu(withTitle: false), "Kategorisieren als"))
    }

    @Test func categorizingSplitsAsksFirst() throws {
        var fixture = RegisterFixture()
        let plain = fixture.add(fixture.giro, -1)
        let split = fixture.add(
            fixture.giro, -10, id: "SPLIT",
            subtransactions: [
                Subtransaction(transactionId: "SPLIT", amount: -4),
                Subtransaction(transactionId: "SPLIT", amount: -6),
            ])
        let (model, store) = fixture.spied()
        select(model, [plain, split])
        let selected = model.selectedTransactionIds
        model.performMenuAction(.categorize(categoryId: fixture.groceries))
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Aufteilungen werden nicht kategorisiert.")
        #expect(
            dialog.content
                == "Aufteilungen lassen sich nicht gemeinsam kategorisieren. Die 1 ausgewählten Aufteilungen werden "
                + "übersprungen.")
        #expect(dialog.buttons.map(\.title) == ["Abbrechen", "Trotzdem kategorisieren"])
        #expect(dialog.dismissal == AnyDialogChoice(CategorizeChoice.cancel))
        model.dialogs.presented.last?.answer(CategorizeChoice.cancel)
        #expect(!model.dialogs.isPresenting)
        #expect(store.commands.isEmpty)
        model.performMenuAction(.categorize(categoryId: fixture.groceries))
        model.dialogs.presented.last?.answer(CategorizeChoice.categorize)
        #expect(store.commands == [.categorizeTransactions(selected, categoryId: fixture.groceries)])
    }

    @Test func moveTargetsSkipTheShownAndClosedAccounts() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1)
        let index = fixture.budget.accounts.firstIndex { $0.id == fixture.karte }!
        fixture.budget.accounts[index].closed = true
        let (model, _) = fixture.spied()
        select(model, [id])
        let submenu = try #require(
            model.transactionActionsMenu(withTitle: false).item(titled: "In Konto verschieben")?.submenu)
        #expect(submenu.map(\.title) == ["Depot", "Tagesgeld"])
    }

    @Test func movingShowsTheUndoNotifierAndUndoPutsItBack() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1)
        let before = fixture.budget
        var moved = before
        moved.transactions[moved.transactions.firstIndex { $0.id == id }!].accountId = fixture.tagesgeld
        let (model, store) = fixture.spied()
        select(model, [id])
        store.budgetAfterNextCommand = moved
        model.performMenuAction(.moveToAccount(accountId: fixture.tagesgeld))
        #expect(store.commands == [.moveTransactions([id], toAccountId: fixture.tagesgeld)])
        #expect(model.notifiers.undoSlot?.message == "Buchung nach „Tagesgeld“ verschoben")
        #expect(model.notifiers.list.last?.link == "Widerrufen")
        #expect(model.selection.isEmpty)
        store.budgetAfterNextCommand = before
        model.notifiers.clicked(.undo)
        #expect(
            store.commands.last
                == .restoreMovedTransactions([
                    MovedTransaction(transactionId: id, accountId: fixture.giro, cleared: .uncleared)
                ]))
        #expect(model.notifiers.undoSlot == nil)
        #expect(model.selectedTransactionIds == [id])
    }

    @Test func movingATransferIntoItsTargetIsRefused() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, target: fixture.tagesgeld)
        let (model, store) = fixture.spied()
        select(model, [id])
        model.performMenuAction(.moveToAccount(accountId: fixture.tagesgeld))
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Nicht alle diese Buchungen lassen sich nach „Tagesgeld“ verschieben.")
        #expect(store.commands.isEmpty)
    }

    @Test func movingSeveralReconciledRowsIsRefused() throws {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, cleared: .reconciled)
        let b = fixture.add(fixture.giro, -2, cleared: .reconciled)
        let (model, store) = fixture.spied()
        select(model, [a, b])
        model.performMenuAction(.moveToAccount(accountId: fixture.tagesgeld))
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.content.hasPrefix("Mehrere dieser Buchungen sind abgeglichen."))
        #expect(store.commands.isEmpty)
    }

    @Test func movingOneReconciledRowAsksFirst() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, cleared: .reconciled)
        let (model, store) = fixture.spied()
        select(model, [id])
        model.performMenuAction(.moveToAccount(accountId: fixture.tagesgeld))
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.title == "Abgeglichene Buchung ändern")
        #expect(dialog.buttons.map(\.title) == ["Ändern", "Abbrechen"])
        #expect(store.commands.isEmpty)
        model.dialogs.presented.last?.answer(ReconciledChoice.change)
        #expect(store.commands == [.moveTransactions([id], toAccountId: fixture.tagesgeld)])
    }

    @Test func keepingAReconciledRowLeavesItWhereItIs() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, cleared: .reconciled)
        let (model, store) = fixture.spied()
        select(model, [id])
        model.performMenuAction(.moveToAccount(accountId: fixture.tagesgeld))
        let dialog = try #require(model.dialogs.presented.last)
        #expect(dialog.dialog.dismissal == AnyDialogChoice(ReconciledChoice.keep))
        dialog.answer(ReconciledChoice.keep)
        #expect(!model.dialogs.isPresenting)
        #expect(store.commands.isEmpty)
    }

    @Test func plainDeletesHappenWithoutConfirmationAndCanBeUndone() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1)
        let b = fixture.add(fixture.giro, -2)
        let before = fixture.budget
        let (model, store) = fixture.spied()
        select(model, [a, b])
        let selected = model.selectedTransactionIds
        store.budgetAfterNextCommand = removing([a, b], from: before)
        model.performMenuAction(.delete)
        #expect(!model.dialogs.isPresenting)
        #expect(store.commands == [.deleteTransactions(selected)])
        #expect(model.notifiers.undoSlot?.message == "2 Buchungen gelöscht")
        #expect(model.selection.isEmpty)
        store.budgetAfterNextCommand = before
        model.notifiers.undoClicked()
        let deleted = before.transactions.filter { [a, b].contains($0.id) }
        #expect(store.commands.last == .restoreTransactions(deleted, payees: []))
        #expect(Set(model.selectedTransactionIds) == [a, b])
    }

    @Test func theUndoSlotKeepsWhatTheDeleteTookAlong() throws {
        var fixture = RegisterFixture()
        let transfer = fixture.add(fixture.giro, -1, target: fixture.tagesgeld)
        let plain = fixture.add(fixture.giro, -2, payee: "Bäcker")
        let before = fixture.budget
        let counterpart = try #require(before.transactions.first { $0.transferTransactionId == transfer }).id
        let bakery = try #require(before.payee(named: "Bäcker"))
        var after = removing([transfer, counterpart, plain], from: before)
        after.payees.removeAll { $0.id == bakery.id }
        let (model, store) = fixture.spied()
        select(model, [transfer, plain])
        store.budgetAfterNextCommand = after
        model.deleteKeyPressed()
        model.dialogs.presented.last?.answer(DeleteChoice.delete)
        model.notifiers.undoClicked()
        let deleted = before.transactions.filter { [transfer, counterpart, plain].contains($0.id) }
        #expect(store.commands.last == .restoreTransactions(deleted, payees: [bakery]))
    }

    @Test func deletingAReconciledTransferWarns() throws {
        var fixture = RegisterFixture()
        let reconciled = fixture.add(fixture.giro, -1, cleared: .reconciled)
        let transfer = fixture.add(fixture.giro, -2, target: fixture.tagesgeld)
        let (model, store) = fixture.spied()
        select(model, [reconciled, transfer])
        let selected = model.selectedTransactionIds
        model.deleteKeyPressed()
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "2 Buchungen löschen?")
        #expect(
            dialog.content
                == "1 der ausgewählten Buchungen ist abgeglichen. Ohne sie stimmt der abgeglichene Saldo nicht "
                + "mehr.<br/><br/>1 der ausgewählten Buchungen ist eine Umbuchung. Ihre Gegenbuchung im anderen Konto "
                + "wird mitgelöscht.")
        #expect(dialog.buttons.map(\.title) == ["Abbrechen", "Löschen"])
        #expect(dialog.dismissal == AnyDialogChoice(DeleteChoice.cancel))
        model.dialogs.presented.last?.answer(DeleteChoice.cancel)
        #expect(store.commands.isEmpty)
        model.deleteKeyPressed()
        model.dialogs.presented.last?.answer(DeleteChoice.delete)
        #expect(store.commands == [.deleteTransactions(selected)])
    }

    @Test func transfersFromSplitsCannotBeDeletedHere() throws {
        var fixture = RegisterFixture()
        _ = fixture.add(
            fixture.tagesgeld, -10, id: "SPLIT",
            subtransactions: [
                Subtransaction(id: "A", transactionId: "SPLIT", amount: -4).transferring(to: fixture.giro),
                Subtransaction(transactionId: "SPLIT", amount: -6),
            ])
        let (model, store) = fixture.spied()
        let counterpart = model.store.budget.transactions.first { $0.transferSubtransactionId == "A" }!.id
        select(model, [counterpart])
        model.deleteKeyPressed()
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Nichts gelöscht.")
        #expect(store.commands.isEmpty)
    }

    @Test func aRefusedRenameShowsTheBudgetsMessage() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, payee: "rewe")
        let (model, store) = fixture.spied()
        select(model, [id])
        store.fail(with: BudgetError.transferPayeeName("Transfer : Giro"))
        model.performMenuAction(.renamePayee)
        model.renamePayeeConfirmed("Transfer : Giro")
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Ungültiger Empfängername")
        #expect(dialog.content.hasPrefix("„Transfer : Giro“ ist kein gültiger Empfängername."))
    }

    @Test func aFailedDeleteReportsTheErrorAndOffersNoUndo() throws {
        struct DiskFull: LocalizedError {
            var errorDescription: String? { "The disk is full." }
        }
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1)
        let (model, store) = fixture.spied()
        select(model, [id])
        store.fail(with: DiskFull())
        model.performMenuAction(.delete)
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Abakus")
        #expect(dialog.content == "The disk is full.")
        #expect(model.notifiers.undoSlot == nil)
    }

    @Test func undoNotifierGoesAwayOnTheNextClick() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries)
        let (model, _) = fixture.spied()
        select(model, [id])
        model.performMenuAction(.delete)
        #expect(model.notifiers.undoSlot != nil)
        model.notifiers.dismissUndo()
        #expect(model.notifiers.list.isEmpty)
    }

    @Test func makeRecurringSendsTheScheduleAndShowsTheCallout() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -9.99, payee: "Spotify")
        let (model, store) = fixture.spied()
        select(model, [id])
        model.performMenuAction(.makeRecurring)
        let scheduleId = try #require(model.lastScheduledTransactionId)
        #expect(store.commands == [.makeRecurring(transactionId: id, scheduleId: scheduleId, today: editDay)])
        #expect(model.popup == .scheduledCallout(.added))
    }

    @Test func moveToSchedulerOffersNoUndo() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -20, on: "2014-07-01")
        let (model, store) = fixture.spied()
        select(model, [id])
        model.performMenuAction(.moveToScheduler)
        let scheduleId = try #require(model.lastScheduledTransactionId)
        #expect(store.commands == [.moveToScheduler(transactionId: id, scheduleId: scheduleId)])
        #expect(model.notifiers.undoSlot == nil)
        #expect(model.popup == .scheduledCallout(.moved))
    }

    @Test func renamePayeeDialogRenamesThePayee() throws {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, payee: "rewe")
        let payeeId = try #require(fixture.budget.transaction(withId: a)?.payeeId)
        let (model, store) = fixture.spied()
        select(model, [a])
        model.performMenuAction(.renamePayee)
        let form = try #require(model.renamePayeeForm)
        #expect(form.currentName == "rewe")
        #expect(form.description.hasPrefix("Alle Buchungen mit „rewe“ bekommen den neuen Namen als Empfänger."))
        model.renamePayeeConfirmed(" REWE ")
        #expect(store.commands == [.renamePayee(payeeId: payeeId, name: "REWE")])
        #expect(model.renamePayeeForm == nil)
    }

    @Test func renamingToTheSameOrABlankNameSendsNothing() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, payee: "rewe")
        let (model, store) = fixture.spied()
        select(model, [a])
        for name in ["rewe", "  "] {
            model.performMenuAction(.renamePayee)
            model.renamePayeeConfirmed(name)
        }
        #expect(store.commands.isEmpty)
        #expect(model.renamePayeeForm == nil)
    }

    @Test func payeeSettingsOpensForTheSelectedPayee() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, payee: "Aral")
        let (model, _) = fixture.spied()
        var opened: [String?] = []
        model.onEditPayees = { opened.append($0) }
        select(model, [id])
        model.performMenuAction(.payeeSettings)
        #expect(opened == ["Aral"])
    }

    @Test func theColumnMenuOpensBelowItsButtonAndCloses() {
        let (model, _) = RegisterFixture().spied()
        model.columnOptionsClicked()
        #expect(model.menuRequest?.anchor == .columnTab)
        #expect(model.menuRequest?.items.first?.title == "Status")
        model.menuDismissed()
        #expect(model.menuRequest == nil)
    }
}
