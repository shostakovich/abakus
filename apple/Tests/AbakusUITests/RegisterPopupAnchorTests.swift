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
        let column = RegisterRowView.statusColumn(for: line, in: model.visibleColumns)
        #expect(column == .category)
        #expect(RegisterRowView.anchorID(.category, row: line, statusColumn: column) == popup.anchor)
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

    private func row(_ model: RegisterViewModel, _ id: String) throws -> RegisterRow {
        try #require(model.rows.first { $0.id == id })
    }

    @Test func aTransactionWaitingForApprovalShowsItsCheckInTheStatusColumn() throws {
        var fixture = RegisterFixture()
        let waiting = fixture.add(fixture.giro, -3, category: fixture.groceries, approved: false, source: .bank)
        let missing = fixture.add(fixture.giro, -4)
        let model = fixture.model()
        let columns = model.visibleColumns
        let waitingRow = try row(model, waiting)
        #expect(RegisterRowView.statusColumn(for: waitingRow, in: columns) == .cleared)
        #expect(RegisterRowView.anchorID(.cleared, row: waitingRow, statusColumn: .cleared) == .error(waiting))
        #expect(RegisterRowView.anchorID(.category, row: waitingRow, statusColumn: .cleared) == nil)
        #expect(RegisterRowView.statusColumn(for: try row(model, missing), in: columns) == .category)
        #expect(ErrorLevel.forReview.symbol?.name == "checkmark")
    }

    @Test func aTrackingAccountKeepsTheApprovalWithoutACategoryColumn() throws {
        var fixture = RegisterFixture()
        let waiting = fixture.add(fixture.depot, -3, approved: false, source: .bank)
        let (model, store) = fixture.spied(selection: .account(fixture.depot))
        #expect(!model.visibleColumns.contains(.category))
        let waitingRow = try row(model, waiting)
        #expect(waitingRow.errorLevel == .forReview)
        #expect(RegisterRowView.statusColumn(for: waitingRow, in: model.visibleColumns) == .cleared)
        model.errorIconClicked(waitingRow)
        #expect(store.commands == [.approveTransactions([waiting])])
    }

    @Test func aMarkFallsBackToTheOtherColumnWhenItsOwnIsHidden() {
        var waiting = RegisterRow(id: "T", transactionId: "T", kind: .transaction)
        waiting.errorLevel = .forReview
        #expect(RegisterRowView.statusColumn(for: waiting, in: [.payee, .category]) == .category)
        var missing = waiting
        missing.errorLevel = .needsCategory
        #expect(RegisterRowView.statusColumn(for: missing, in: [.payee, .cleared]) == .cleared)
        #expect(RegisterRowView.statusColumn(for: missing, in: [.payee]) == nil)
    }
}
