import AbakusCore
import Testing

@testable import AbakusUI

private let order = ["a", "b", "c", "d"]

@Suite struct RegisterSelectionTests {
    @Test func clickSelectsOnlyThatRow() {
        var selection = RegisterSelection()
        _ = selection.click("b", modifiers: [], order: order)
        _ = selection.click("c", modifiers: [], order: order)
        #expect(selection.ids == ["c"])
    }

    @Test func clickingTheOnlySelectedRowBeginsEditing() {
        var selection = RegisterSelection()
        #expect(selection.click("b", modifiers: [], order: order) == .selectionChanged)
        #expect(selection.click("b", modifiers: [], order: order) == .beginEdit)
        #expect(selection.ids == ["b"])
    }

    @Test func clickingOneOfSeveralSelectedRowsSelectsItAlone() {
        var selection = RegisterSelection()
        selection.selectAll(order)
        #expect(selection.click("b", modifiers: [], order: order) == .selectionChanged)
        #expect(selection.ids == ["b"])
    }

    @Test func commandClickTogglesARow() {
        var selection = RegisterSelection()
        _ = selection.click("a", modifiers: [], order: order)
        _ = selection.click("c", modifiers: .command, order: order)
        #expect(selection.ids == ["a", "c"])
        _ = selection.click("a", modifiers: .command, order: order)
        #expect(selection.ids == ["c"])
    }

    @Test func shiftClickSelectsTheRangeFromTheAnchor() {
        var selection = RegisterSelection()
        _ = selection.click("d", modifiers: [], order: order)
        _ = selection.click("b", modifiers: .shift, order: order)
        #expect(selection.ids == ["b", "c", "d"])
        _ = selection.click("c", modifiers: .shift, order: order)
        #expect(selection.ids == ["c", "d"])
        #expect(selection.ordered(by: order) == ["c", "d"])
    }

    @Test func arrowKeysMoveAndShiftExtends() {
        var selection = RegisterSelection()
        #expect(selection.moveCaret(by: 1, extending: false, order: order) == "a")
        selection.moveCaret(by: 1, extending: false, order: order)
        #expect(selection.ids == ["b"])
        selection.moveCaret(by: 1, extending: true, order: order)
        #expect(selection.ids == ["b", "c"])
        selection.moveCaret(by: 5, extending: false, order: order)
        #expect(selection.ids == ["d"])
        var empty = RegisterSelection()
        #expect(empty.moveCaret(by: -1, extending: false, order: order) == "d")
    }

    @Test func retainDropsRowsThatAreGone() {
        var selection = RegisterSelection()
        selection.selectAll(order)
        selection.retain(["a", "b"])
        #expect(selection.ids == ["a", "b"])
        #expect(selection.caret == nil)
    }
}

@MainActor
@Suite struct RegisterSelectionModelTests {
    @Test func secondClickOnTheOnlySelectedRowStartsEditing() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let model = fixture.model()
        let row = model.rows.first { $0.id == id }!
        model.rowClicked(row, column: .memo, modifiers: [])
        #expect(model.editor == nil)
        model.rowClicked(row, column: .memo, modifiers: [])
        #expect(model.editingTransactionId == id)
        #expect(model.editor?.focusedField == .main(.memo))
    }

    @Test func commandClickTogglesWithoutEditing() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let model = fixture.model()
        let rows = model.rows
        model.rowClicked(rows[0], column: nil, modifiers: .command)
        model.rowClicked(rows[1], column: nil, modifiers: .command)
        #expect(model.selection.count == 2)
        model.rowClicked(rows[1], column: nil, modifiers: .command)
        #expect(model.selectedTransactionIds == [id])
        #expect(!model.selection.contains(rows[1].id))
        #expect(model.editor == nil)
    }

    @Test func commandASelectsEveryTransactionUnlessTheSearchFieldHasFocus() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -4)
        let model = fixture.model()
        #expect(model.selectAllKeyPressed())
        #expect(model.selection.count == 2)
        model.clearSelection()
        model.search.focusChanged(true)
        #expect(!model.selectAllKeyPressed())
        #expect(model.selection.isEmpty)
    }

    @Test func clickingASplitChildSelectsItsParent() {
        var fixture = RegisterFixture()
        let split = fixture.add(
            fixture.giro, -3,
            subtransactions: [
                Subtransaction(transactionId: "", amount: -1, categoryId: fixture.groceries),
                Subtransaction(transactionId: "", amount: -2, categoryId: fixture.groceries),
            ])
        let model = fixture.model()
        model.toggleSplit(split)
        model.rowClicked(model.rows[2], column: .category, modifiers: [])
        #expect(model.selectedTransactionIds == [split])
    }

    @Test func selectionIsPerVisitAndClearedWhenSwitchingAccounts() {
        let fixture = RegisterFixture()
        let model = fixture.model()
        model.selectAll()
        #expect(model.selection.count == 1)
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(model.selection.isEmpty)
        model.navigation.selection = .account(fixture.giro)
        #expect(model.selection.isEmpty)
    }

    @Test func arrowKeysMoveTheModelSelection() {
        var fixture = RegisterFixture()
        let second = fixture.add(fixture.giro, -4)
        let model = fixture.model()
        model.rowClicked(model.rows[1], column: .payee, modifiers: [])
        #expect(model.grid.navigationKeyPressed(.up, extending: false, caretOnly: false, pageRows: 1) == second)
        #expect(model.selectedTransactionIds == [second])
        model.grid.navigationKeyPressed(.down, extending: true, caretOnly: false, pageRows: 1)
        #expect(model.selection.count == 2)
    }

    @Test func iconClicksKeepAMultiSelectionThatContainsTheRow() {
        var fixture = RegisterFixture()
        let second = fixture.add(fixture.giro, -4)
        let third = fixture.add(fixture.giro, -5)
        let (model, store) = fixture.spied()
        let rows = [fixture.startingBalanceId(of: fixture.giro), second, third].map { id in
            model.rows.first { $0.id == id }!
        }
        model.rowClicked(rows[0], column: nil, modifiers: .command)
        model.rowClicked(rows[1], column: nil, modifiers: .command)
        model.errorIconClicked(rows[1])
        #expect(model.selection.count == 2)
        #expect(model.popup == .needsCategory(rowId: rows[1].id))
        model.clearedClicked(rows[2])
        #expect(model.selectedTransactionIds == [third])
        #expect(store.commands == [.toggleCleared([third])])
    }

    @Test func deletedTransactionsLeaveTheSelection() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let model = fixture.model()
        model.selectAll()
        try model.store.perform(.deleteTransactions([id]))
        #expect(model.selection.count == 1)
        #expect(model.actionButtonTitle == "1 Buchung bearbeiten")
    }
}
