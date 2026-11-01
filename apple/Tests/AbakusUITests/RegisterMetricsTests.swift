import CoreGraphics
import Testing

@testable import AbakusUI

@Suite struct RegisterListContentTests {
    @Test func listContentKeepsRowsAlignedAtTheEnd() {
        #expect(registerListContentHeight(rowCount: 3, viewportHeight: 230) == 230)
        #expect(registerListContentHeight(rowCount: 10, viewportHeight: 230) == 286)
        #expect(registerListContentHeight(rowCount: 30, viewportHeight: 230) == 846)
    }

    @Test func theAddEditorAboveTheRowsAddsItsHeight() {
        #expect(registerListContentHeight(rowCount: 3, viewportHeight: 230, leadHeight: 55) == 230)
        #expect(registerListContentHeight(rowCount: 7, viewportHeight: 230, leadHeight: 55) == 251)
        #expect(registerListContentHeight(rowCount: 10, viewportHeight: 230, leadHeight: 55) == 341)
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
