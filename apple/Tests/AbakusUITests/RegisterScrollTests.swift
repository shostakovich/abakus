import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterScrollTests {
    @Test func aScrollRequestBelongsToItsVisit() throws {
        var fixture = RegisterFixture()
        let transfer = fixture.add(fixture.giro, -5, target: fixture.tagesgeld)
        let model = fixture.model()
        model.requestScroll(.top)
        model.navigation.selection = .account(fixture.karte)
        #expect(model.grid.scrollRequest == nil)
        model.navigation.selection = .account(fixture.giro)
        model.transferIconClicked(try #require(model.rows.first { $0.id == transfer }))
        let counterpart = try #require(model.store.budget.transaction(withId: transfer)?.transferTransactionId)
        #expect(model.grid.scrollRequest?.target == .row(counterpart))
    }

    @Test func arrowAfterDeletingTheCaretRowGoesToTheNextRow() throws {
        var fixture = RegisterFixture()
        let ids = (1...4).map {
            fixture.add(fixture.giro, Decimal(-$0), on: "2014-05-1\($0)", category: fixture.groceries)
        }
        let model = fixture.model()
        model.rowClicked(try #require(model.rows.first { $0.id == ids[1] }), column: .payee, modifiers: [])
        model.deleteKeyPressed()
        model.grid.navigationKeyPressed(.down, extending: false, caretOnly: false, pageRows: 1)
        #expect(model.selectedTransactionIds == [ids[0]])
    }

    @Test func sortingScrollsToTheFirstSelectedRow() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -5, payee: "Zoo")
        let model = fixture.model()
        model.rowClicked(try #require(model.rows.first { $0.id == id }), column: .payee, modifiers: [])
        model.grid.headerClicked(.payee)
        #expect(model.grid.scrollRequest?.target == .row(id))
    }

    @Test func theRegisterStartsAtItsTopAndClampsOffsets() {
        var fixture = RegisterFixture()
        let ids = (1...5).map { fixture.add(fixture.giro, Decimal(-$0), on: "2014-05-1\($0)") }
        let model = fixture.model()
        let row = RegisterMetrics.rowHeight
        let grid = model.grid
        #expect(grid.scrollOffset(for: .row(ids[4]), viewport: 2 * row, current: nil) == nil)
        #expect(grid.scrollOffset(for: .row(ids[0]), viewport: 2 * row, current: nil) == 4 * row)
        #expect(grid.scrollOffset(for: .bottom, viewport: 2 * row, current: 0) == 6 * row)
        #expect(grid.scrollOffset(for: .offset(500), viewport: 2 * row, current: 0) == 6 * row)
        #expect(grid.scrollOffset(for: .offset(30), viewport: 2 * row, current: 0) == 30)
    }

    @Test func revealingTheEditedRowCountsItsExtraHeight() throws {
        var fixture = RegisterFixture()
        let ids = (1...5).map { fixture.add(fixture.giro, Decimal(-$0), on: "2014-05-1\($0)") }
        let model = fixture.model()
        model.beginEditing(ids[0])
        let height = try #require(model.editor?.rowHeight)
        let top = 5 * RegisterMetrics.rowHeight
        let revealed = ((top + height - 100) / RegisterMetrics.rowHeight).rounded(.up) * RegisterMetrics.rowHeight
        #expect(model.grid.scrollOffset(for: .row(ids[0]), viewport: 100, current: 48) == revealed)
    }

    @Test func editingASplitTallerThanTheViewportStartsAtTheRowsTopBelowItsHeading() throws {
        var fixture = RegisterFixture()
        let groceries = fixture.groceries
        let split = fixture.add(
            fixture.giro, -9, category: EntityID.splitCategory,
            subtransactions: (1...3).map { _ in
                Subtransaction(transactionId: "", amount: -3, categoryId: groceries)
            })
        fixture.add(fixture.giro, -1, on: "2014-05-11")
        fixture.add(fixture.giro, -1, on: "2014-05-12")
        let model = fixture.model()
        model.beginEditing(split)
        #expect(model.editor?.rowHeight == 180)
        let belowTheHeading: CGFloat = 2 * RegisterMetrics.rowHeight
        #expect(model.grid.scrollOffset(for: .row(split), viewport: 100, current: 0) == belowTheHeading)
    }

    private func register(rows count: Int) -> RegisterViewModel {
        var fixture = RegisterFixture()
        for number in 1..<count { fixture.add(fixture.giro, Decimal(-number)) }
        return fixture.model()
    }

    private let row = RegisterMetrics.rowHeight

    @Test func aListAtItsEndStaysAtItsEndWhenItsViewportChanges() {
        let model = register(rows: 21)
        let atEnd = model.grid.scrollMetrics(at: .greatestFiniteMagnitude, viewport: 200)
        #expect(atEnd.offset == 16 * row)
        #expect(model.grid.scrollMetrics(afterResizing: atEnd, to: 171).offset == 17 * row)
        #expect(model.grid.scrollMetrics(afterResizing: atEnd, to: 260).offset == 14 * row)
    }

    @Test func aScrolledListKeepsItsTopRowWhenItsViewportChanges() {
        let model = register(rows: 21)
        let scrolled = model.grid.scrollMetrics(at: 5 * row, viewport: 200)
        #expect(model.grid.scrollMetrics(afterResizing: scrolled, to: 171).offset == 5 * row)
        #expect(model.grid.scrollMetrics(afterResizing: scrolled, to: 260).offset == 5 * row)
        #expect(model.grid.scrollMetrics(afterResizing: scrolled, to: 560).offset == 3 * row)
    }

    @Test func aListThatFitsKeepsItsTop() {
        var fixture = RegisterFixture()
        for number in 1...3 { fixture.add(fixture.giro, Decimal(-number)) }
        fixture.addSchedule("S1")
        fixture.addSchedule("S2", on: "2014-06-05")
        let model = fixture.model()
        let register = model.grid.scrollMetrics(at: 0, viewport: 200)
        let scheduler = model.scheduler.grid.scrollMetrics(at: 0, viewport: 200)
        #expect(model.scheduler.rows.count == 2)
        #expect(model.grid.scrollMetrics(afterResizing: register, to: 72).offset == 0)
        #expect(model.scheduler.grid.scrollMetrics(afterResizing: scheduler, to: 30).offset == 0)
    }

    @Test func aSchedulerAtItsEndStaysAtItsEnd() {
        var fixture = RegisterFixture()
        for number in 1...6 { fixture.addSchedule("S\(number)", on: "2014-06-1\(number)") }
        let model = fixture.model()
        let atEnd = model.scheduler.grid.scrollMetrics(at: .greatestFiniteMagnitude, viewport: 100)
        #expect(atEnd.offset == 3 * row)
        let resized = model.scheduler.grid.scrollMetrics(afterResizing: atEnd, to: 70)
        #expect(resized.isAtEnd)
        #expect(resized.offset == 4 * row)
    }

    @Test func snappingLandsWithinARowOfTheEndOnTheEnd() throws {
        #expect(RegisterGridController.snappedOffset(100, maxOffset: 100) == 100)
        #expect(RegisterGridController.snappedOffset(80, maxOffset: 100) == 100)
        #expect(RegisterGridController.snappedOffset(70, maxOffset: 100) == 84)
        #expect(RegisterGridController.snappedOffset(50, maxOffset: 100) == 56)
        let model = register(rows: 21)
        let top = model.grid.scrollMetrics(at: 0, viewport: 451.4)
        #expect(try #require(model.grid.scrollMetrics(revealing: .bottom, from: top, viewport: 451.4)).isAtEnd)
        #expect(try #require(model.grid.scrollMetrics(revealing: .top, from: top, viewport: 451.4)).offset == 0)
    }

    @Test func aRowRevealedBelowTheViewIsShownWhole() throws {
        let model = register(rows: 21)
        let top = model.grid.scrollMetrics(at: 0, viewport: 451)
        model.rowClicked(
            try #require(model.rows.first { $0.id == model.transactionIds[17] }), column: .payee, modifiers: [])
        let next = try #require(model.grid.navigationKeyPressed(.down, extending: false, caretOnly: false, pageRows: 1))
        let shown = try #require(model.grid.scrollMetrics(revealing: .row(next), from: top, viewport: 451))
        #expect(shown.offset == 4 * row)
        #expect(shown.offset + 451 >= 20 * row)
        let last = try #require(model.grid.navigationKeyPressed(.end, extending: false, caretOnly: false, pageRows: 1))
        #expect(try #require(model.grid.scrollMetrics(revealing: .row(last), from: top, viewport: 451)).isAtEnd)
    }

    @Test func anEditBelowTheViewIsShownWhole() throws {
        let model = register(rows: 21)
        model.beginEditing(model.transactionIds[17])
        let height = try #require(model.editor?.rowHeight)
        let viewport = 17 * row + height - 5
        let top = model.grid.scrollMetrics(at: 0, viewport: viewport)
        let shown = model.grid.scrollMetrics(afterResizing: top, to: viewport)
        #expect(shown.offset == 2 * row)
    }

    @Test func anEditKeepsItsRowInViewWhileTheViewportChanges() {
        let model = register(rows: 21)
        let atEnd = model.grid.scrollMetrics(at: .greatestFiniteMagnitude, viewport: 200)
        model.beginEditing(model.transactionIds[1])
        #expect(model.editor != nil)
        #expect(model.grid.scrollMetrics(afterResizing: atEnd, to: 171).offset == row)
    }

    @Test func editingTheLastRowAtTheEndKeepsTheEnd() {
        let model = register(rows: 21)
        let atEnd = model.grid.scrollMetrics(at: .greatestFiniteMagnitude, viewport: 200)
        model.beginEditing(model.transactionIds[20])
        let end = model.grid.listContentHeight(viewport: 200) - 200
        #expect(end > atEnd.offset)
        #expect(model.grid.scrollMetrics(afterResizing: atEnd, to: 200).offset == end)
    }

    @Test func theAddEditorOpensAtTheTopOfALongListWhateverTheSort() {
        for ascending in [false, true] {
            let model = register(rows: 21)
            if ascending { model.grid.headerClicked(.date) }
            let atEnd = model.grid.scrollMetrics(at: .greatestFiniteMagnitude, viewport: 200)
            #expect(atEnd.offset > 0)
            model.addTransactionClicked()
            #expect(model.grid.isAdding)
            #expect(model.grid.scrollRequest?.target == .top)
            #expect(model.grid.scrollMetrics(afterResizing: atEnd, to: 200).offset == 0)
        }
    }

    @Test func theSchedulersAddEditorOpensAtItsTop() {
        var fixture = RegisterFixture()
        for number in 1...6 { fixture.addSchedule("S\(number)", on: "2014-06-1\(number)") }
        let model = fixture.model()
        let atEnd = model.scheduler.grid.scrollMetrics(at: .greatestFiniteMagnitude, viewport: 100)
        model.scheduler.addClicked()
        #expect(model.scheduler.grid.isAdding)
        #expect(model.scheduler.grid.scrollMetrics(afterResizing: atEnd, to: 100).offset == 0)
    }

    @Test func theRowsMoveDownByTheAddEditorsHeight() throws {
        let model = register(rows: 21)
        let first = try #require(model.grid.row(atY: 1, scrollOffset: 0))
        let second = try #require(model.grid.row(atY: row + 1, scrollOffset: 0))
        let content = model.grid.listContentHeight(viewport: 200)
        model.addTransactionClicked()
        let height = try #require(model.editor?.rowHeight)
        #expect(model.grid.addRowHeight == height)
        #expect(model.grid.row(atY: 1, scrollOffset: 0) == nil)
        #expect(model.grid.row(atY: height + 1, scrollOffset: 0)?.id == first.id)
        #expect(model.grid.row(atY: height + row + 1, scrollOffset: 0)?.id == second.id)
        #expect(model.grid.listContentHeight(viewport: 200) == content + height)
        #expect(model.grid.scrollMetrics(at: height + 20, viewport: 200).offset == height + row)
        #expect(model.grid.scrollMetrics(at: height - 10, viewport: 200).offset == height - 10)
    }

    /// The view's order: the request places the list, then each frame of the opening info bar resizes it.
    private func placementAfterDateFilter(ascending: Bool) throws -> ScrollMetrics {
        var fixture = RegisterFixture(start: day("2014-01-02"))
        for number in 1...20 {
            fixture.add(fixture.giro, Decimal(-number), on: "2014-01-1\(number % 10)")
            fixture.add(fixture.giro, Decimal(-number), on: "2014-05-1\(number % 10)")
        }
        let model = fixture.model()
        if ascending { model.grid.headerClicked(.date) }
        let before = model.grid.scrollMetrics(at: 4 * row, viewport: 300)
        model.search.timeframePresetClicked(.latestThreeMonths)
        #expect(model.transactionIds.count == 20)
        let request = try #require(model.grid.scrollRequest)
        var placed = try #require(model.grid.scrollMetrics(revealing: request.target, from: before, viewport: 299))
        for viewport: CGFloat in [296.5, 288, 275.2, 271.9, 271] {
            placed = model.grid.scrollMetrics(afterResizing: placed, to: viewport)
        }
        return placed
    }

    @Test func aDateFilterLeavesTheRegisterAtItsEndWhileTheInfoBarOpens() throws {
        let placed = try placementAfterDateFilter(ascending: true)
        #expect(placed.isAtEnd)
        #expect(placed.offset == 12 * row)
        #expect(try placementAfterDateFilter(ascending: false).offset == 0)
    }

    @Test func aSavedNewTransactionIsRevealedWhereItsDateSortsIt() throws {
        let (model, _) = RegisterFixture().spied(appliesCommands: true)
        model.requestScroll(.offset(90))
        model.addTransactionClicked()
        #expect(model.grid.scrollRequest?.target == .top)
        let editor = try #require(model.editor)
        editor.press(.tab)
        editor.type("Bakery")
        editor.press(.tab, .tab, .tab)
        editor.type("3")
        editor.activate(.save)
        let saved = try #require(model.transactions.first { $0.amount == -3 })
        #expect(model.grid.scrollRequest?.target == .row(saved.id))
    }

    @Test func savingAndAddingAnotherKeepsTheAddEditorAtTheTopAboveTheSavedRow() throws {
        let (model, _) = RegisterFixture().spied(appliesCommands: true)
        model.addTransactionClicked()
        let editor = try #require(model.editor)
        editor.press(.tab)
        editor.type("Bakery")
        editor.press(.tab, .tab, .tab)
        editor.type("3")
        editor.activate(.saveAndAddAnother)
        let saved = try #require(model.transactions.first { $0.amount == -3 })
        let next = try #require(model.editor)
        #expect(next !== editor)
        #expect(next.mode == .new)
        let request = try #require(model.grid.scrollRequest)
        #expect(request.target == .top)
        #expect(model.grid.scrollOffset(for: request.target, viewport: 200, current: 3 * row) == 0)
        let shown = stride(from: next.rowHeight + 1, to: 200, by: row).compactMap {
            model.grid.row(atY: $0, scrollOffset: 0)?.transactionId
        }
        #expect(shown.contains(saved.id))
    }

    @Test func clearingASearchRestoresThePositionBeforeIt() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -5, payee: "Zoo")
        let model = fixture.model()
        model.saveScrollOffset(120)
        model.search.boxChanged("zoo")
        model.search.submitted()
        model.saveScrollOffset(0)
        model.search.clearClicked()
        #expect(model.grid.scrollRequest?.target == .offset(120))
    }
}
