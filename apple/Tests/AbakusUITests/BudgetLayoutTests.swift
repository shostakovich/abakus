import AppKit
import CoreGraphics
import Testing

@testable import AbakusUI

@Suite struct BudgetLayoutTests {
    @Test(arguments: [
        (CGFloat(532), 1, CGFloat(298)), (776, 2, 265), (1076, 3, 272.667), (1652, 5, 274),
    ])
    func monthsShareTheListWidthAtLeast240Wide(panelWidth: CGFloat, count: Int, width: CGFloat) {
        let layout = BudgetLayout(panelSize: CGSize(width: panelWidth, height: 783))
        #expect(layout.columnCount == count)
        #expect(abs(layout.columnWidth - width) < 0.001)
    }

    @Test func aWideCategoryColumnLeavesOneNarrowMonth() {
        let layout = BudgetLayout(panelSize: CGSize(width: 532, height: 522), categoryWidth: 380)
        #expect(layout.listWidth == 120)
        #expect(layout.columnCount == 1)
        #expect(layout.columnWidth == 108)
        #expect(BudgetLayout(panelSize: CGSize(width: 233, height: 500)).columnCount == 0)
    }

    @Test func eachMonthFollowsItsSeparator() {
        let layout = BudgetLayout(panelSize: CGSize(width: 1076, height: 783))
        #expect(
            [0, 1, 2].map { abs(layout.columnX($0) - [202, 486.667, 771.333][$0]) < 0.001 } == [true, true, true])
        #expect(layout.separatorX(0) == 196)
        #expect(layout.tableFrame == CGRect(x: 16, y: 8, width: 1044, height: 759))
        #expect(layout.rowsOrigin == CGPoint(x: 16, y: 178))
        #expect(layout.viewportHeight == 588)
    }

    @Test func theMonthHeaderIs104HighAndTheCalculationAdds66() {
        var layout = BudgetLayout(panelSize: CGSize(width: 1076, height: 783))
        #expect(BudgetMetrics.monthHeaderHeight == 104)
        #expect(layout.headerHeight == 170)
        layout.headerProgress = 0
        #expect(layout.headerHeight == 104)
        #expect(layout.tableFrame.minY == 8)
        #expect(layout.rowsOrigin.y == 112)
    }

    @Test func verfuegbarIsTintedFromItsColumnTitleDownToTheNextSeparator() {
        let layout = BudgetLayout(panelSize: CGSize(width: 1076, height: 783), headerProgress: 0)
        let first = layout.availableColumn(at: 0)
        #expect(first.minX == layout.columnX(0) + 170)
        #expect(abs(first.maxX - layout.separatorX(1)) < 0.001)
        #expect(first.minY == 70)
        #expect(first.maxY == layout.tableFrame.height)
        let last = layout.availableColumn(at: 2)
        #expect(abs(last.maxX - (layout.columnX(2) + layout.columnWidth)) < 0.001)
    }

    @Test func theLastMonthsCellsEndBeforeTheScroller() {
        let layout = BudgetLayout(panelSize: CGSize(width: 1076, height: 783))
        #expect(layout.cells(at: 1) == BudgetCellColumns(width: layout.columnWidth))
        #expect(layout.cells(at: 2) == BudgetCellColumns(width: layout.columnWidth - 17))
        #expect(BudgetMetrics.scrollerGutter == NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
    }

    @Test func aMonthsCellsSplitItsWidthAndHoldTheField() {
        let cells = BudgetCellColumns(width: 274)
        #expect([cells.assigned, cells.outflows, cells.balance] == [85, 85, 104])
        #expect(cells.field == CGRect(x: 8, y: 4, width: 72, height: 24))
    }
}
