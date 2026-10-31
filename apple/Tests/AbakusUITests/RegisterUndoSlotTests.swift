import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterUndoSlotTests {
    private func select(_ model: RegisterViewModel, _ ids: [String]) {
        model.clearSelection()
        for id in ids { model.rowClicked(model.rows.first { $0.id == id }!, column: nil, modifiers: .command) }
    }

    @Test func undoingAMoveSendsTheAccountAndTheReconciledStatusBack() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, cleared: .reconciled, target: fixture.karte)
        let (model, store) = fixture.spied()
        select(model, [id])
        model.performMove([id], to: fixture.tagesgeld)
        model.notifiers.undoClicked()
        #expect(
            store.commands == [
                .moveTransactions([id], toAccountId: fixture.tagesgeld),
                .restoreMovedTransactions([
                    MovedTransaction(transactionId: id, accountId: fixture.giro, cleared: .reconciled)
                ]),
            ])
    }

    @Test func anyLaterChangeOfTheBudgetDropsTheUndoSlot() {
        var fixture = RegisterFixture()
        let deleted = fixture.add(fixture.giro, -1, category: fixture.groceries)
        fixture.add(fixture.giro, -2, category: fixture.groceries)
        let (model, store) = fixture.spied()
        select(model, [deleted])
        model.performMenuAction(.delete)
        #expect(model.notifiers.undoSlot != nil)
        store.budget.transactions[0].memo = "changed"
        #expect(model.notifiers.undoSlot == nil)
        #expect(!model.notifiers.list.contains { $0.kind == .undo })
        model.notifiers.undoClicked()
        #expect(store.commands == [.deleteTransactions([deleted])])
    }

    @Test func recordingTheUndoSlotScalesWithTheChange() {
        var fixture = RegisterFixture()
        fixture.budget.transactions += (0..<4000).map { index in
            Transaction(id: "T\(index)", accountId: fixture.giro, date: day("2014-05-10"), amount: -1)
        }
        let model = fixture.model()
        let start = ContinuousClock.now
        model.performDelete((0..<10).map { "T\($0)" })
        #expect(ContinuousClock.now - start < .milliseconds(200))
        #expect(model.notifiers.undoSlot?.message == "10 Buchungen gelöscht")
    }

    @Test func theIncomeCheckBelongsToOneVisit() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, _) = fixture.spied(appliesCommands: true)
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Zu verteilen")
        editor.press(.tab)
        editor.activate(.done)
        #expect(model.incomeCheck?.transactionId == id)
        model.navigation.selection = .account(fixture.tagesgeld)
        model.navigation.selection = .account(fixture.giro)
        #expect(model.incomeCheck == nil)
    }
}
