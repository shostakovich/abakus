import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct LedTransactionTests {
    private func ledByKasse(_ fixture: inout RegisterFixture, approved: Bool = true) -> String {
        let id = fixture.add(fixture.giro, -30, payee: "Kasse", memo: "Pizza", approved: approved, source: .kasse)
        let index = fixture.budget.transactions.firstIndex { $0.id == id }!
        fixture.budget.transactions[index].ledBy = .kasse
        return id
    }

    private func editor(of id: String, in model: RegisterViewModel, column: RegisterColumn) throws
        -> TransactionEditor
    {
        let row = try #require(model.rows.first { $0.id == id })
        model.rowClicked(row, column: column, modifiers: [])
        model.rowClicked(row, column: column, modifiers: [])
        return try #require(model.editor)
    }

    @Test func editingALedTransactionChangesOnlyItsCategoryAndMemo() throws {
        var fixture = RegisterFixture()
        let id = ledByKasse(&fixture)
        let model = fixture.model()
        let editor = try editor(of: id, in: model, column: .amount)

        for column in [EditorColumn.account, .date, .payee, .amount] {
            #expect(editor.isLocked(.main(column)))
            #expect(!editor.tabOrder.contains(.field(.main(column))))
        }
        #expect(editor.lockReason == "Wird von der Kasse geführt.")
        #expect(editor.focusedField == .main(.category))
        editor.fieldClicked(.main(.date))
        #expect(editor.focusedField == .main(.category))

        editor.retype("Groceries")
        editor.press(.tab)
        #expect(editor.focusedField == .main(.memo))
        editor.retype("Pizza mit Anna")
        editor.activate(.done)

        let saved = try #require(model.store.budget.transaction(withId: id))
        #expect(saved.categoryId == fixture.groceries)
        #expect(saved.memo == "Pizza mit Anna")
        #expect(saved.amount == -30)
        #expect(saved.date == day("2014-05-10"))
        #expect(saved.accountId == fixture.giro)
        #expect(model.store.budget.payeeName(of: saved) == "Kasse")
    }

    @Test func aLedTransactionCannotBeSplit() throws {
        var fixture = RegisterFixture()
        let id = ledByKasse(&fixture)
        let model = fixture.model()
        let editor = try editor(of: id, in: model, column: .category)
        #expect(editor.dropDown?.items.contains { $0.kind == .split } == false)
        editor.retype(DefaultCategories.splitCategoryName)
        editor.press(.tab)
        #expect(!editor.isSplitMode)
        #expect(editor.taskDialog?.instruction == "Diese Buchung wird von der Kasse geführt.")
    }

    @Test func anUnapprovedLedTransactionOffersNoDelete() throws {
        var fixture = RegisterFixture()
        let id = ledByKasse(&fixture, approved: false)
        let model = fixture.model()
        let editor = try editor(of: id, in: model, column: .memo)
        #expect(editor.buttons == [.approveAndFindNext, .approve, .cancel])
    }

    @Test func theRegisterOffersNeitherDeletingNorMovingALedTransaction() throws {
        var fixture = RegisterFixture()
        let id = ledByKasse(&fixture, approved: false)
        let index = fixture.budget.transactions.firstIndex { $0.id == id }!
        fixture.budget.transactions[index].date = day("2014-06-10")
        let model = fixture.model()
        let row = try #require(model.rows.first { $0.id == id })
        let menu = try #require(model.contextMenu(for: row))
        #expect(menu.item(titled: "Löschen")?.isEnabled == false)
        #expect(menu.item(titled: "Ablehnen (löschen)")?.isEnabled == false)
        #expect(menu.item(titled: "In Konto verschieben")?.isEnabled == false)
        #expect(menu.item(titled: "In geplante Buchungen verschieben …")?.isEnabled == false)
        #expect(menu.item(titled: "Bestätigen")?.isEnabled == true)

        model.deleteKeyPressed()
        #expect(model.store.budget.transaction(withId: id) != nil)
        #expect(model.dialogs.presented.last?.dialog.instruction == "Nichts gelöscht.")
    }

    @Test func deletingAndMovingASelectionLeaveTheLedTransactionsOut() throws {
        var fixture = RegisterFixture()
        let led = ledByKasse(&fixture)
        let own = fixture.add(fixture.giro, -5, payee: "Bäcker")
        let model = fixture.model()
        model.updateSelection { $0.select(led) }
        model.updateSelection { $0.toggle(own) }
        let menu = model.transactionActionsMenu(withTitle: false)
        #expect(menu.item(titled: "Löschen")?.isEnabled == true)

        model.performMenuAction(.moveToAccount(accountId: fixture.karte))
        #expect(model.store.budget.transaction(withId: own)?.accountId == fixture.karte)
        #expect(model.store.budget.transaction(withId: led)?.accountId == fixture.giro)
        #expect(model.notifiers.undoSlot?.message == "Buchung nach „Karte“ verschoben")
    }

    @Test func deletingASelectionWithALedTransactionSaysWhatStays() throws {
        var fixture = RegisterFixture()
        let led = ledByKasse(&fixture)
        let own = fixture.add(fixture.giro, -5, payee: "Bäcker")
        let model = fixture.model()
        model.deleteTransactions([led, own])
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(
            dialog.content
                == "1 der ausgewählten Buchungen wird von der Kasse geführt und nicht gelöscht.")
        model.dialogs.presented.last?.answer(DeleteChoice.delete, isChecked: false)
        #expect(model.store.budget.transaction(withId: own) == nil)
        #expect(model.store.budget.transaction(withId: led) != nil)
    }
}
