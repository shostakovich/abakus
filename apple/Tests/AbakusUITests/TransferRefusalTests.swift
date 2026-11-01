import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct TransferRefusalTests {
    @Test func aTransferToItsOwnAccountIsRefusedAndRefocusesThePayee() throws {
        let fixture = RegisterFixture()
        let (model, store) = fixture.spied(selection: .allAccounts)
        store.fail(with: BudgetError.transferToSameAccount)
        model.grid.beginNew()
        let editor = try #require(model.editor)
        editor.fieldClicked(.main(.payee))
        editor.paste("Transfer : Tagesgeld")
        editor.press(.tab)
        editor.fieldClicked(.main(.account))
        editor.retype("Tagesgeld")
        editor.press(.tab)
        #expect(editor.clone.accountId == fixture.tagesgeld)
        editor.fieldClicked(.main(.amount))
        editor.type("5")
        editor.activate(.save)
        #expect(store.transactionSaves.map(\.transaction.accountId) == [fixture.tagesgeld])
        #expect(store.transactionSaves.map(\.payeeName) == ["Transfer : Tagesgeld"])
        let dialog = try #require(editor.taskDialog)
        #expect(dialog.instruction == "Ein Konto kann nicht auf sich selbst umbuchen.")
        #expect(
            dialog.content
                == "Ändere zuerst das Konto oder das Gegenkonto dieser Umbuchung.")
        editor.answer(MessageChoice.close)
        #expect(editor.focus == .field(.main(.payee)))
        #expect(model.editor === editor)
    }

    @Test func aRefusedScheduledMoveShowsTheBudgetsText() throws {
        var fixture = RegisterFixture()
        fixture.addSchedule("S1", payee: nil, target: fixture.tagesgeld)
        let (model, store) = fixture.spied()
        store.fail(with: BudgetError.transferIntoMoveTarget("Tagesgeld"))
        model.scheduler.grid.rowClicked(
            try #require(model.scheduler.rows.first).transactionId, column: .payee, modifiers: [])
        model.scheduler.moveClicked(to: fixture.tagesgeld)
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Nicht alle diese Buchungen lassen sich nach „Tagesgeld“ verschieben.")
        #expect(dialog.content == BudgetError.transferIntoMoveTarget("Tagesgeld").errorDescription)
        #expect(model.notifiers.undoSlot == nil)
    }

    @Test func anUnexpectedErrorOfAScheduledMoveIsReported() throws {
        struct Unreadable: LocalizedError {
            var errorDescription: String? { "The budget could not be changed." }
        }
        var fixture = RegisterFixture()
        fixture.addSchedule("S1")
        let (model, store) = fixture.spied()
        store.fail(with: Unreadable())
        model.scheduler.grid.rowClicked("S1", column: .payee, modifiers: [])
        model.scheduler.moveClicked(to: fixture.karte)
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Abakus")
        #expect(dialog.content == "The budget could not be changed.")
        #expect(model.notifiers.undoSlot == nil)
    }
}
