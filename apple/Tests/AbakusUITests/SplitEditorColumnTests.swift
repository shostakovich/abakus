import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct SplitEditorColumnTests {
    @Test func aScheduledSplitHasNoSubFrequencyField() throws {
        var fixture = RegisterFixture()
        let transaction = Transaction(
            id: "S1", accountId: fixture.giro, date: day("2014-06-02"), categoryId: EntityID.splitCategory,
            amount: -25,
            subtransactions: [
                Subtransaction(transactionId: "S1", amount: -20, categoryId: fixture.groceries),
                Subtransaction(transactionId: "S1", amount: -5, categoryId: fixture.groceries),
            ])
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, frequency: .monthly, payeeName: "Rent", isNew: true)))
        let model = fixture.model()
        model.scheduler.beginEditing("S1")
        let editor = try #require(model.scheduler.editor)
        let layout = model.scheduler.columnLayout(gridWidth: 900)
        #expect(
            SplitEditorView.fieldFrames(layout.frames, editor: editor).map(\.column)
                == [.payee, .category, .memo, .amount])
    }
}
