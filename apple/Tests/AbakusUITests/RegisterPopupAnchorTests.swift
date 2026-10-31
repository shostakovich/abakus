import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterPopupAnchorTests {
    @Test func splitLineErrorIconAnchorsItsPopup() throws {
        var fixture = RegisterFixture()
        let split = fixture.add(
            fixture.giro, -10, category: EntityID.splitCategory,
            subtransactions: [
                Subtransaction(
                    transactionId: "", amount: -4, categoryId: fixture.groceries
                ).transferring(to: fixture.tagesgeld),
                Subtransaction(transactionId: "", amount: -6, categoryId: fixture.groceries),
            ])
        let model = fixture.model()
        model.toggleSplit(split)
        let line = try #require(model.rows.first { $0.isSubtransaction && $0.errorLevel == .error })
        model.errorIconClicked(line)
        let popup = try #require(model.popup)
        #expect(RegisterRowView.anchorID(.errorState, row: line) == popup.anchor)
    }

    @Test func arrowKeysWaitWhileARowPopupIsOpen() throws {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, on: "2014-05-10")
        fixture.add(fixture.giro, -2, on: "2014-05-11")
        let model = fixture.model()
        let row = try #require(model.rows.first { $0.id == a })
        model.errorIconClicked(row)
        #expect(model.popup == .needsCategory(rowId: a))
        #expect(model.grid.navigationKeyPressed(.down, extending: false, caretOnly: false, pageRows: 1) == nil)
        model.grid.editSelected()
        #expect(model.selectedTransactionIds == [a])
        #expect(model.editor == nil)
    }
}
