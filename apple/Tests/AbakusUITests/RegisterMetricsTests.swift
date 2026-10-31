import CoreGraphics
import Testing

@testable import AbakusUI

@Suite struct RegisterAddRowPlacementTests {
    @Test func floatsDirectlyUnderTheLastRow() {
        let placement = RegisterAddRowPlacement.compute(gridHeight: 400, rowCount: 1)
        #expect(placement == .floating(y: 56))
        #expect(placement.listHeight(gridHeight: 400) == 372)
    }

    @Test func withoutAnAddEditorTheListTakesTheWholeGrid() {
        #expect(RegisterAddRowPlacement.compute(gridHeight: 400, rowCount: 15).listHeight(gridHeight: 400) == 372)
    }

    @Test func theAddEditorDocksWhenTheRowsFillTheGrid() {
        let placement = RegisterAddRowPlacement.compute(gridHeight: 400, rowCount: 15, editorHeight: 55)
        #expect(placement == .docked(y: 345))
        #expect(placement.isDocked)
        #expect(placement.listHeight(gridHeight: 400) == 317)
    }

    @Test func listContentKeepsRowsAlignedAtTheEnd() {
        #expect(registerListContentHeight(rowCount: 3, viewportHeight: 230) == 230)
        #expect(registerListContentHeight(rowCount: 10, viewportHeight: 230) == 286)
        #expect(registerListContentHeight(rowCount: 30, viewportHeight: 230) == 846)
    }
}

@Suite struct ScrollMetricsTests {
    @Test func sizesWithinAPointAreTheSame() {
        let placed = ScrollMetrics(offset: 648, contentHeight: 1126.42, viewportHeight: 478.42)
        #expect(ScrollMetrics(offset: 640, contentHeight: 1126.5, viewportHeight: 478.5).hasSameSize(as: placed))
        #expect(!ScrollMetrics(offset: 648, contentHeight: 1127.5, viewportHeight: 479.5).hasSameSize(as: placed))
    }

    @Test func theEndIsWithinHalfAPointOfTheLastOffset() {
        let metrics = ScrollMetrics(offset: 899.6, contentHeight: 1200, viewportHeight: 300)
        #expect(metrics.canScroll)
        #expect(metrics.isAtEnd)
        #expect(!ScrollMetrics(offset: 0, contentHeight: 300, viewportHeight: 300).canScroll)
    }
}
