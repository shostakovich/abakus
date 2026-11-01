import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct SchedulerGridTests {
    private func fixture() -> RegisterFixture {
        var fixture = RegisterFixture()
        fixture.addSchedule("S1", payee: "Zeta", category: fixture.groceries)
        fixture.addSchedule("S2", on: "2014-06-05", payee: "Alpha", category: fixture.groceries)
        return fixture
    }

    @Test func movingSchedulesCanBeUndoneFromTheNotifier() throws {
        let fixture = fixture()
        let (model, store) = fixture.spied()
        model.scheduler.grid.rowClicked(
            try #require(model.scheduler.rows.first).transactionId, column: .payee, modifiers: [])
        model.scheduler.moveClicked(to: fixture.tagesgeld)
        #expect(model.notifiers.undoSlot?.message == "Buchung nach „Tagesgeld“ verschoben")
        model.notifiers.clicked(.undo)
        #expect(
            store.commands == [
                .moveScheduledTransactions(["S1"], toAccount: fixture.tagesgeld),
                .restoreMovedTransactions([
                    MovedTransaction(transactionId: "S1", accountId: fixture.giro, cleared: .uncleared)
                ]),
            ])
        #expect(model.notifiers.undoSlot == nil)
    }

    @Test func thePlusMenuHidesTheScheduledMemoColumn() throws {
        let (model, _) = fixture().spied()
        model.scheduler.columnOptionsClicked()
        let items = try #require(model.menuRequest?.items)
        #expect(
            items.map { $0.kind == .separator ? "-" : $0.title }
                == ["Memo", "-", "Für alle Konten übernehmen"])
        #expect(items.allSatisfy { $0.kind == .separator || $0.isChecked || $0.title.hasPrefix("Für alle") })
        model.performMenuAction(.toggleScheduledColumn(.memo))
        #expect(!model.scheduler.visibleColumns.contains(.memo))
    }

    @Test func headerClicksSortTheSchedules() {
        let (model, _) = fixture().spied()
        #expect(model.scheduler.scheduledIds == ["S1", "S2"])
        model.scheduler.grid.headerClicked(.payee)
        #expect(model.scheduler.scheduledIds == ["S2", "S1"])
        #expect(model.scheduler.sortOrder == RegisterSortOrder(column: .payee, ascending: true))
        model.scheduler.grid.headerClicked(.payee)
        #expect(model.scheduler.scheduledIds == ["S1", "S2"])
    }

    @Test func arrowsAfterDeletingTheCaretScheduleGoToTheNextOne() throws {
        var fixture = fixture()
        fixture.addSchedule("S3", -5, on: "2014-06-09", payee: "Beta", category: fixture.groceries)
        let (model, _) = fixture.spied(appliesCommands: true)
        model.scheduler.grid.rowClicked(
            try #require(model.scheduler.rows.first { $0.id == "S2" }).transactionId, column: .payee, modifiers: [])
        model.scheduler.deleteClicked()
        model.scheduler.grid.navigationKeyPressed(.down, extending: false, caretOnly: false, pageRows: 1)
        #expect(model.scheduler.selectedIds == ["S3"])
    }

    @Test func keysWaitWhileAMenuIsOpen() throws {
        let (model, _) = fixture().spied()
        model.scheduler.grid.rowClicked(
            try #require(model.scheduler.rows.first).transactionId, column: .payee, modifiers: [])
        model.scheduler.columnOptionsClicked()
        model.scheduler.grid.editSelected()
        #expect(model.scheduler.editor == nil)
        #expect(
            model.scheduler.grid.navigationKeyPressed(.down, extending: false, caretOnly: false, pageRows: 1) == nil)
        #expect(model.scheduler.selectedIds == ["S1"])
    }

    @Test func aScrollRequestBelongsToItsVisit() {
        let fixture = fixture()
        let (model, _) = fixture.spied()
        model.scheduler.beginEditing("S2")
        #expect(model.scheduler.grid.scrollRequest?.target == .row("S2"))
        model.navigation.selection = .account(fixture.karte)
        model.navigation.selection = .account(fixture.giro)
        #expect(model.scheduler.grid.scrollRequest == nil)
    }

    private func schedules(_ count: Int) -> RegisterFixture {
        var fixture = fixture()
        for number in 3...count { fixture.addSchedule("S\(number)", -5, on: "2014-06-1\(number)", payee: "Beta") }
        return fixture
    }

    @Test func pageAndEndKeysMoveTheCaret() throws {
        let (model, _) = schedules(5).spied()
        model.scheduler.grid.rowClicked(
            try #require(model.scheduler.rows.first).transactionId, column: .payee, modifiers: [])
        model.scheduler.grid.navigationKeyPressed(.end, extending: false, caretOnly: false, pageRows: 2)
        #expect(model.scheduler.selectedIds == ["S5"])
        model.scheduler.grid.navigationKeyPressed(.pageUp, extending: true, caretOnly: false, pageRows: 2)
        #expect(model.scheduler.selectedIds == ["S3", "S4", "S5"])
    }

    @Test func commandArrowsMoveOnlyTheCaret() throws {
        let (model, _) = schedules(5).spied()
        let grid = model.scheduler.grid
        grid.rowClicked("S1", column: .payee, modifiers: [])
        grid.navigationKeyPressed(.down, extending: false, caretOnly: true, pageRows: 2)
        #expect(model.scheduler.selectedIds == ["S1"])
        grid.navigationKeyPressed(.down, extending: true, caretOnly: false, pageRows: 2)
        #expect(model.scheduler.selectedIds == ["S1", "S2", "S3"])
    }

    @Test func deleteKeysWaitForMenusAndEdits() throws {
        let (model, store) = fixture().spied()
        model.scheduler.grid.rowClicked(
            try #require(model.scheduler.rows.first).transactionId, column: .payee, modifiers: [])
        model.scheduler.columnOptionsClicked()
        model.scheduler.deleteKeyPressed()
        model.menuDismissed()
        model.scheduler.beginEditing("S2")
        model.scheduler.deleteKeyPressed()
        #expect(store.commands.isEmpty)
        model.scheduler.editor?.cancel()
        model.scheduler.deleteKeyPressed()
        #expect(store.commands == [.deleteScheduledTransactions(["S2"])])
    }

    @Test func aRevealedScheduleScrollsOnlyAsFarAsNeeded() {
        let (model, _) = schedules(5).spied()
        let row = RegisterMetrics.rowHeight
        let grid = model.scheduler.grid
        #expect(grid.scrollOffset(for: .row("S2"), viewport: 2 * row, current: nil) == nil)
        #expect(grid.scrollOffset(for: .row("S4"), viewport: 2 * row, current: nil) == 2 * row)
        #expect(grid.scrollOffset(for: .row("S1"), viewport: 2 * row, current: 3 * row) == 0)
    }

    @Test func aTallEditRowKeepsItsFocusedPartInView() throws {
        var fixture = RegisterFixture()
        fixture.addSchedule("S2", on: "2014-05-25")
        fixture.addSchedule("S3", on: "2014-05-28")
        fixture.addSplitSchedule()
        let (model, _) = fixture.spied()
        let grid = model.scheduler.grid
        let viewport: CGFloat = 78
        let top = 2 * RegisterMetrics.rowHeight
        grid.beginEditing("S1")
        let editor = try #require(grid.editor)
        #expect(editor.rowHeight == 152)
        #expect(grid.scrollOffset(for: .row("S1"), viewport: viewport, current: 0) == top)
        #expect(grid.scrollOffset(for: .row("S1"), viewport: viewport, current: 90) == top)
        #expect(grid.scrollOffset(for: .row("S1"), viewport: viewport, current: top) == nil)
        editor.addSubRow()
        #expect(grid.scrollOffset(for: .row("S1"), viewport: viewport, current: top) == top + 114 - viewport)
        editor.setFocus(.button(.done), commitCurrent: false)
        #expect(grid.scrollOffset(for: .row("S1"), viewport: viewport, current: top) == top + 180 - viewport)
        editor.setFocus(.field(.sub(editor.subIds[0], .memo)), commitCurrent: false)
        #expect(grid.scrollOffset(for: .row("S1"), viewport: viewport, current: top + 180 - viewport) == top + 30)
    }

    @Test func splitLinesHaveNoPayeeTooltip() throws {
        var fixture = RegisterFixture()
        fixture.addSplitSchedule(transferTo: fixture.tagesgeld)
        let (model, _) = fixture.spied()
        model.scheduler.grid.toggleSplit("S1")
        let rows = model.scheduler.rows
        #expect(rows.map(\.payee) == ["Rent", "", "Tagesgeld"])
        #expect(rows.map(\.payeeTooltip) == ["Rent", nil, nil])
    }
}
