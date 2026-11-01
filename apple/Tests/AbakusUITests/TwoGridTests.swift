import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct TwoGridTests {
    private func fixture() -> RegisterFixture {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -10, category: fixture.groceries)
        fixture.addSchedule("S1", category: fixture.groceries)
        return fixture
    }

    /// T1 needs a category, T2 is a transfer and T3 a split; S1 is a split schedule.
    private func clicksFixture() -> RegisterFixture {
        var fixture = RegisterFixture()
        let groceries = fixture.groceries
        fixture.add(fixture.giro, -10, id: "T1")
        fixture.add(fixture.giro, -5, on: "2014-05-11", id: "T2", target: fixture.tagesgeld)
        fixture.add(
            fixture.giro, -9, on: "2014-05-12", category: EntityID.splitCategory, id: "T3",
            subtransactions: [
                Subtransaction(transactionId: "T3", amount: -4, categoryId: groceries),
                Subtransaction(transactionId: "T3", amount: -5, categoryId: groceries),
            ])
        fixture.addSplitSchedule()
        fixture.addSchedule("S2", on: "2014-06-05", category: groceries)
        return fixture
    }

    enum MainGridClick: CaseIterable {
        case row, rightClick, header, splitArrow, cleared, errorIcon, transferIcon, newTransaction

        /// Clicks like the main grid's views do and returns whether the click took effect.
        @MainActor func perform(on model: RegisterViewModel, store: SpyBudgetStore) throws -> Bool {
            let row = try #require(model.rows.first { $0.id == self.rowId })
            switch self {
            case .row:
                model.grid.rowClicked(row.transactionId, column: .payee, modifiers: [])
                return model.selectedTransactionIds == ["T1"]
            case .rightClick:
                guard model.contextMenu(for: row) != nil else { return false }
                return model.selectedTransactionIds == ["T1"]
            case .header:
                model.grid.headerClicked(.payee)
                return model.sortOrder.column == .payee
            case .splitArrow:
                model.grid.toggleSplit(row.transactionId)
                return model.expandedSplits.contains("T3")
            case .cleared:
                model.clearedClicked(row)
                return store.commands == [.toggleCleared(["T1"])]
            case .errorIcon:
                model.errorIconClicked(row)
                return model.popup == .needsCategory(rowId: "T1")
            case .transferIcon:
                model.transferIconClicked(row)
                return model.accountKey == "TAGES"
            case .newTransaction:
                model.grid.beginNew()
                return model.editor?.mode == .new
            }
        }

        private var rowId: String {
            switch self {
            case .splitArrow: "T3"
            case .transferIcon: "T2"
            default: "T1"
            }
        }
    }

    @Test(arguments: MainGridClick.allCases)
    func aMainGridClickWaitsForAChangedScheduleEdit(_ click: MainGridClick) throws {
        let (model, store) = clicksFixture().spied()
        model.scheduler.beginEditing("S2", column: .memo)
        model.scheduler.editor?.type("changed")
        #expect(try !click.perform(on: model, store: store))
        #expect(model.scheduler.editor?.glowCount == 1)
        #expect(model.selection.isEmpty)
        #expect(model.editor == nil)
    }

    @Test(arguments: MainGridClick.allCases)
    func aMainGridClickEndsAnUnchangedScheduleEditFirst(_ click: MainGridClick) throws {
        let (model, store) = clicksFixture().spied()
        model.scheduler.beginEditing("S2")
        #expect(try click.perform(on: model, store: store))
        #expect(model.scheduler.editor == nil)
        if click != .newTransaction { #expect(model.scheduler.selection.isEmpty) }
    }

    enum SchedulerClick: CaseIterable {
        case row, header, splitArrow, rightClick, newTransaction

        /// Clicks like the scheduler's views do and returns whether the click took effect.
        @MainActor func perform(on model: RegisterViewModel) throws -> Bool {
            let scheduler = model.scheduler
            switch self {
            case .row:
                scheduler.grid.rowClicked("S2", column: .payee, modifiers: [])
                return scheduler.selectedIds == ["S2"]
            case .header:
                scheduler.grid.headerClicked(.payee)
                return scheduler.sortOrder.column == .payee
            case .splitArrow:
                scheduler.grid.toggleSplit("S1")
                return scheduler.expandedSplits.contains("S1")
            case .rightClick:
                let row = try #require(scheduler.rows.first { $0.id == "S2" })
                guard scheduler.contextMenu(for: row) != nil else { return false }
                return scheduler.selectedIds == ["S2"]
            case .newTransaction:
                scheduler.grid.beginNew()
                return scheduler.editor?.mode == .new
            }
        }
    }

    @Test(arguments: SchedulerClick.allCases)
    func aSchedulerClickWaitsForAChangedMainEdit(_ click: SchedulerClick) throws {
        let (model, _) = clicksFixture().spied()
        model.beginEditing("T1", column: .memo)
        model.editor?.type("changed")
        #expect(try !click.perform(on: model))
        #expect(model.editor?.glowCount == 1)
        #expect(model.scheduler.selection.isEmpty)
        #expect(model.scheduler.editor == nil)
    }

    @Test(arguments: SchedulerClick.allCases)
    func aSchedulerClickEndsAnUnchangedMainEditFirst(_ click: SchedulerClick) throws {
        let (model, _) = clicksFixture().spied()
        model.beginEditing("T1")
        #expect(try click.perform(on: model))
        #expect(model.editor == nil)
        if click != .newTransaction { #expect(model.selection.isEmpty) }
    }

    @Test func aSchedulerSplitArrowGlowsAtItsOwnChangedEdit() {
        let (model, _) = clicksFixture().spied()
        model.scheduler.beginEditing("S2", column: .memo)
        model.scheduler.editor?.type("changed")
        model.scheduler.grid.toggleSplit("S1")
        #expect(!model.scheduler.expandedSplits.contains("S1"))
        #expect(model.scheduler.editor?.glowCount == 1)
    }

    @Test func beginningAScheduleEditTakesTheSelectionFromTheMainGrid() throws {
        let (model, _) = fixture().spied()
        model.rowClicked(try #require(model.rows.last), column: .payee, modifiers: [])
        model.scheduler.beginEditing("S1")
        #expect(model.scheduler.selectedIds == ["S1"])
        #expect(model.selection.isEmpty)
    }

    @Test func undoingAMoveSelectsTheSchedulesAgainAndClearsTheMainSelection() throws {
        let fixture = fixture()
        var moved = fixture.budget
        moved.scheduledTransactions[0].accountId = fixture.tagesgeld
        let (model, store) = fixture.spied()
        model.scheduler.grid.rowClicked("S1", column: .payee, modifiers: [])
        store.budgetAfterNextCommand = moved
        model.scheduler.moveClicked(to: fixture.tagesgeld)
        #expect(model.scheduler.selection.isEmpty)
        store.budgetAfterNextCommand = fixture.budget
        model.rowClicked(try #require(model.rows.last), column: .payee, modifiers: [])
        model.notifiers.clicked(.undo)
        #expect(model.scheduler.selectedIds == ["S1"])
        #expect(model.selection.isEmpty)
    }

    @Test func leavingTheAccountDropsTheSchedulersSelectionAndEdit() throws {
        var fixture = fixture()
        fixture.addSchedule("S2", on: "2014-06-05", category: fixture.groceries)
        let (model, _) = fixture.spied()
        model.scheduler.grid.rowClicked("S1", column: .payee, modifiers: [])
        model.scheduler.beginEditing("S2", column: .memo)
        model.scheduler.editor?.type("changed")
        model.navigation.selection = .account(fixture.karte)
        model.navigation.selection = .account(fixture.giro)
        #expect(model.scheduler.selection.isEmpty)
        #expect(model.scheduler.editor == nil)
        let row = try #require(model.rows.last)
        #expect(model.grid.rowClicked(row.transactionId, column: .payee, modifiers: []))
        #expect(model.selectedTransactionIds == [row.transactionId])
    }

    @Test func selectingAllInTheMainGridClearsTheScheduledSelection() throws {
        let (model, _) = fixture().spied()
        let scheduled = try #require(model.scheduler.rows.first)
        model.scheduler.grid.rowClicked(scheduled.transactionId, column: .payee, modifiers: [])
        #expect(model.selectAllKeyPressed())
        #expect(model.scheduler.selection.isEmpty)
    }

    @Test func returnInTheMainGridWaitsForTheScheduledEdit() throws {
        let (model, _) = fixture().spied()
        model.selectAll()
        model.rowClicked(try #require(model.rows.last), column: .payee, modifiers: [])
        model.scheduler.beginEditing("S1", column: .memo)
        model.scheduler.editor?.type("changed")
        model.grid.editSelected()
        #expect(model.editor == nil)
    }

    @Test func returnInTheSchedulerWaitsForTheMainEdit() throws {
        let (model, _) = fixture().spied()
        let scheduled = try #require(model.scheduler.rows.first)
        model.scheduler.grid.rowClicked(scheduled.transactionId, column: .payee, modifiers: [])
        model.grid.beginNew()
        model.editor?.type("Shop")
        model.scheduler.grid.editSelected()
        #expect(model.scheduler.editor == nil)
    }

    @Test func aSwallowedClickLeavesTheFocusWithTheEdit() throws {
        let (model, _) = fixture().spied()
        let rows = model.rows
        model.beginEditing(rows[0].transactionId, column: .memo)
        model.editor?.type("changed")
        #expect(!model.rowClicked(rows[1], column: .payee, modifiers: []))
        #expect(model.editor?.focus == .field(.main(.memo)))
        model.editor?.cancel()
        #expect(model.rowClicked(rows[1], column: .payee, modifiers: []))
    }

    @Test func movingTheCaretInTheSchedulerClearsTheMainSelection() throws {
        let (model, _) = fixture().spied()
        model.rowClicked(try #require(model.rows.last), column: .payee, modifiers: [])
        model.scheduler.grid.navigationKeyPressed(.down, extending: false, caretOnly: false, pageRows: 1)
        #expect(model.scheduler.selectedIds == ["S1"])
        #expect(model.selection.isEmpty)
    }

    @Test func arrowsWhileEditingStepOnlyTheFrequency() throws {
        let (model, _) = fixture().spied()
        model.beginEditing(try #require(model.rows.first).transactionId)
        #expect(!model.grid.editorArrowPressed(.down))
        #expect(model.editor?.text(.main(.date)) == "10/05/14")
        model.editor?.cancel()
        model.scheduler.beginEditing("S1")
        let editor = try #require(model.scheduler.editor)
        #expect(!model.scheduler.grid.editorArrowPressed(.down))
        #expect(editor.text(.main(.date)) == "02/06/14")
        editor.press(.tab)
        #expect(editor.focus == .field(.main(.frequency)))
        #expect(model.scheduler.grid.editorArrowPressed(.down))
        #expect(editor.frequency == .everyOtherMonth)
    }

    @Test func aSchedulerRightClickWaitsForTheMainEdit() throws {
        let (model, _) = fixture().spied()
        model.beginEditing(try #require(model.rows.last).transactionId, column: .memo)
        model.editor?.type("changed")
        #expect(!model.scheduler.contextClicked(try #require(model.scheduler.rows.first)))
        #expect(model.editor?.glowCount == 1)
        #expect(model.scheduler.selection.isEmpty)
    }

    @Test func aSchedulerHeaderClickTakesTheSelectionFromTheMainGrid() throws {
        let (model, _) = fixture().spied()
        model.rowClicked(try #require(model.rows.last), column: .payee, modifiers: [])
        model.scheduler.grid.headerClicked(.payee)
        #expect(model.selection.isEmpty)
        #expect(model.scheduler.sortOrder.column == .payee)
    }

    @Test func aSchedulerSplitArrowWaitsForTheMainEdit() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10, category: fixture.groceries)
        fixture.addSplitSchedule()
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .memo)
        model.editor?.type("changed")
        model.scheduler.grid.toggleSplit("S1")
        #expect(model.scheduler.rows.count == 1)
        #expect(model.editor?.glowCount == 1)
    }
}
