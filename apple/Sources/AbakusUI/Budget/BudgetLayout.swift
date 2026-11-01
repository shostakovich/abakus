import CoreGraphics
import Foundation

public enum BudgetMetrics {
    public static let rowHeight: CGFloat = 32
    public static let horizontalInset: CGFloat = 16
    public static let topInset: CGFloat = 8
    public static let bottomInset: CGFloat = 16
    /// The gap before each month that holds its vertical separator.
    public static let separatorWidth: CGFloat = 12
    public static let minimumMonthWidth: CGFloat = 240
    public static let defaultCategoryWidth: CGFloat = 190
    public static let categoryWidthRange: ClosedRange<CGFloat> = 190...380
    public static let maximumFittedCategoryWidth: CGFloat = 220
    public static let pageScroll: CGFloat = 100
    public static let dragThreshold: CGFloat = 11
    public static let headerTopPadding: CGFloat = 4
    public static let monthTitleHeight: CGFloat = 22
    public static let headerGap: CGFloat = 4
    public static let resultHeight: CGFloat = 36
    /// The column titles with their totals and the padding below them.
    public static let columnHeadHeight: CGFloat = 34
    public static let monthHeaderHeight =
        headerTopPadding + monthTitleHeight + headerGap + resultHeight + headerGap + columnHeadHeight
    public static let headerLineHeight: CGFloat = 15.5
    public static let headerDetailsPadding: CGFloat = 4
    /// Between a figure's digits and its cell's trailing edge; the € hangs in it.
    public static let cellPadding: CGFloat = 12
    public static let fieldHeight: CGFloat = 24
    public static let fieldLeadingInset: CGFloat = 8
    public static let fieldTrailingInset: CGFloat = 5
    public static let fieldButtonWidth: CGFloat = 20
    /// The legacy scroller's width; the last month keeps its figures clear of it, and of an expanded overlay scroller.
    public static let scrollerGutter: CGFloat = 17
}

public struct BudgetLayout: Hashable, Sendable {
    public var panelSize: CGSize
    public var categoryWidth: CGFloat
    public var headerProgress: CGFloat
    /// The most lines the header of a shown month has; every card is as tall as that one.
    public var headerLineCount: Int

    public init(
        panelSize: CGSize, categoryWidth: CGFloat = BudgetMetrics.defaultCategoryWidth, headerProgress: CGFloat = 1,
        headerLineCount: Int = 4
    ) {
        self.panelSize = panelSize
        self.categoryWidth = categoryWidth
        self.headerProgress = headerProgress
        self.headerLineCount = headerLineCount
    }

    public var tableWidth: CGFloat { max(0, panelSize.width - 2 * BudgetMetrics.horizontalInset) }

    public var listWidth: CGFloat { max(0, tableWidth - categoryWidth) }

    public var columnCount: Int {
        let slot = BudgetMetrics.separatorWidth + BudgetMetrics.minimumMonthWidth
        return listWidth <= BudgetMetrics.separatorWidth ? 0 : max(1, Int(listWidth / slot))
    }

    public var columnWidth: CGFloat {
        columnCount == 0 ? 0 : listWidth / CGFloat(columnCount) - BudgetMetrics.separatorWidth
    }

    public func columnX(_ index: Int) -> CGFloat {
        categoryWidth + BudgetMetrics.separatorWidth + CGFloat(index) * (columnWidth + BudgetMetrics.separatorWidth)
    }

    /// The centre of the separator before month `index`; the first one is the category column's divider.
    public func separatorX(_ index: Int) -> CGFloat {
        columnX(index) - BudgetMetrics.separatorWidth / 2
    }

    public var headerDetailsHeight: CGFloat {
        CGFloat(headerLineCount) * BudgetMetrics.headerLineHeight + BudgetMetrics.headerDetailsPadding
    }

    public var headerHeight: CGFloat {
        BudgetMetrics.monthHeaderHeight + headerDetailsHeight * headerProgress
    }

    public var tableFrame: CGRect {
        CGRect(
            x: BudgetMetrics.horizontalInset, y: BudgetMetrics.topInset, width: tableWidth,
            height: max(0, panelSize.height - BudgetMetrics.topInset - BudgetMetrics.bottomInset))
    }

    public var rowsOrigin: CGPoint {
        CGPoint(x: tableFrame.minX, y: tableFrame.minY + headerHeight)
    }

    public var viewportHeight: CGFloat { max(0, tableFrame.height - headerHeight - 1) }

    public func cells(at index: Int) -> BudgetCellColumns {
        BudgetCellColumns(width: columnWidth - (index == columnCount - 1 ? BudgetMetrics.scrollerGutter : 0))
    }

    /// Verfügbar of month `index` in the table, from its column title down to the next month's separator line; the
    /// last one runs under the scroller.
    public func availableColumn(at index: Int) -> CGRect {
        let cells = cells(at: index)
        let top = headerHeight - BudgetMetrics.columnHeadHeight
        let minX = columnX(index) + cells.assigned + cells.outflows
        let maxX = index == columnCount - 1 ? columnX(index) + columnWidth : separatorX(index + 1)
        return CGRect(x: minX, y: top, width: max(0, maxX - minX), height: max(0, tableFrame.height - top))
    }
}

public struct BudgetCellColumns: Hashable, Sendable {
    public var width: CGFloat

    public init(width: CGFloat) {
        self.width = width
    }

    public var assigned: CGFloat { (width * 0.31).rounded() }
    public var outflows: CGFloat { (width * 0.31).rounded() }
    public var balance: CGFloat { max(0, width - assigned - outflows) }

    public var field: CGRect {
        CGRect(
            x: BudgetMetrics.fieldLeadingInset, y: (BudgetMetrics.rowHeight - BudgetMetrics.fieldHeight) / 2,
            width: max(0, assigned - BudgetMetrics.fieldLeadingInset - BudgetMetrics.fieldTrailingInset),
            height: BudgetMetrics.fieldHeight)
    }
}
