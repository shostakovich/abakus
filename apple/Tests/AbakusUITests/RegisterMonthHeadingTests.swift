import AbakusCore
import CoreGraphics
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterMonthHeadingTests {
    private struct Girokonto {
        var fixture = RegisterFixture(start: day("2026-10-01"))
        let october: String
        let november: String

        init() {
            fixture.budget.budgetMetaData = BudgetMetaData()
            october = fixture.add(fixture.giro, -30, on: "2026-10-30", payee: "Kleinanzeigen", id: "OCT")
            november = fixture.add(fixture.giro, -20, on: "2026-11-01", payee: "Bäckerei", id: "NOV")
        }
    }

    private func labels(_ model: RegisterViewModel) -> [String] {
        model.gridRows.map { $0.isMonthHeading ? $0.title : $0.date }
    }

    @Test func monthHeadingsFollowTheDateOrder() {
        let model = Girokonto().fixture.model()
        #expect(model.sortOrder == RegisterSortOrder(column: .date, ascending: false))
        #expect(labels(model) == ["November 2026", "01.11.", "Oktober 2026", "30.10.", "01.10."])
    }

    @Test func monthHeadingsTurnWithAnAscendingDateOrder() {
        let model = Girokonto().fixture.model()
        model.grid.headerClicked(.date)
        #expect(labels(model) == ["Oktober 2026", "01.10.", "30.10.", "November 2026", "01.11."])
    }

    @Test func noMonthHeadingsWhenSortedByPayee() {
        let model = Girokonto().fixture.model()
        model.grid.headerClicked(.payee)
        #expect(!model.gridRows.contains { $0.isMonthHeading })
        #expect(model.gridRows == model.rows)
    }

    @Test func monthHeadingsAreNeitherSelectableNorTransactions() {
        let model = Girokonto().fixture.model()
        #expect(model.rows.count == 3)
        #expect(model.gridIds == model.transactionIds)
        model.rowClicked(model.rows[0], column: .payee, modifiers: [])
        model.grid.navigationKeyPressed(.down, extending: false, caretOnly: false, pageRows: 10)
        #expect(model.selectedTransactionIds == [Girokonto().october])
    }

    @Test func aSplitLineFollowsItsParentUnderTheHeading() {
        var girokonto = Girokonto()
        let split = girokonto.fixture.add(
            girokonto.fixture.giro, -30, on: "2026-11-01",
            subtransactions: [
                Subtransaction(transactionId: "", amount: -10), Subtransaction(transactionId: "", amount: -20),
            ])
        let model = girokonto.fixture.model()
        model.toggleSplit(split)
        let rows = model.gridRows
        let parent = rows.firstIndex { $0.id == split }!
        #expect(rows[0].title == "November 2026")
        #expect(rows[parent + 1].isSubtransaction && rows[parent + 2].isSubtransaction)
        #expect(rows[parent].category == "Aufgeteilt (2)")
    }

    @Test func revealingARowAboveTheViewLeavesRoomForThePinnedHeading() throws {
        let model = Girokonto().fixture.model()
        let row = RegisterMetrics.rowHeight
        let offset = model.grid.scrollOffset(for: .row(Girokonto().october), viewport: row, current: 4 * row)
        let headingAndRowAbove: CGFloat = 2 * row
        #expect(offset == headingAndRowAbove)
    }

    @Test func aSecondaryClickOnAHeadingOpensNoMenu() {
        let model = Girokonto().fixture.model()
        #expect(model.grid.contextMenu(atY: 2, scrollOffset: 0) == [])
        #expect(model.grid.contextMenu(atY: RegisterMetrics.rowHeight + 2, scrollOffset: 0)?.isEmpty == false)
    }

    @Test func thePinnedHeadingTakesTheClickAboveTheRowsUnderIt() {
        let model = Girokonto().fixture.model()
        let row = RegisterMetrics.rowHeight
        #expect(model.grid.contextMenu(atY: 2, scrollOffset: 3 * row) == [])
    }
}
