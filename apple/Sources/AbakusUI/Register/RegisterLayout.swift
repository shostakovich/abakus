import AbakusCore
import CoreGraphics
import Foundation

public enum RegisterMetrics {
    public static let searchInfoBarHeight: CGFloat = 28
    public static let headerHeight: CGFloat = 28
    public static let rowHeight: CGFloat = 28
    public static let columnMenuWidth: CGFloat = 20
    /// Puts the first column's text in line with the row above the grid.
    public static let leadingInset: CGFloat = 10
    public static let statusBarHeight: CGFloat = 30
    public static let searchFieldWidth: CGFloat = 200
}

/// Content height that keeps a row-aligned top edge when scrolled to the end, like the row-based Flex list; the rows
/// follow `leadHeight`, the add editor's.
public func registerListContentHeight(
    rowCount: Int, viewportHeight: CGFloat, extraHeight: CGFloat = 0, leadHeight: CGFloat = 0
) -> CGFloat {
    let rows = CGFloat(rowCount) * RegisterMetrics.rowHeight + extraHeight
    guard leadHeight + rows > viewportHeight else { return viewportHeight }
    guard rows > viewportHeight else { return leadHeight + rows }
    return viewportHeight + leadHeight
        + ((rows - viewportHeight) / RegisterMetrics.rowHeight).rounded(.up) * RegisterMetrics.rowHeight
}

public enum RegisterSummaryKind: Hashable, Sendable {
    case cleared, uncleared, working, selected, search, blank
}

public struct RegisterSummaryItem: Hashable, Sendable {
    public var kind: RegisterSummaryKind
    public var title: String
    public var amountText: String
    public var isNegative: Bool
    public var tooltip: String?

    public var isClickable: Bool { kind == .cleared || kind == .uncleared }

    static let blank = RegisterSummaryItem(kind: .blank, title: "", amountText: "", isNegative: false, tooltip: nil)
}

public struct RegisterSummary: Hashable, Sendable {
    public var first: RegisterSummaryItem
    public var second: RegisterSummaryItem
    public var working: RegisterSummaryItem

    public var showsOperands: Bool { first.kind == .cleared && second.kind == .uncleared }
}

public struct RegisterColumnMenuItem: Hashable, Sendable {
    public var column: RegisterColumn
    public var label: String
    public var isChecked: Bool
}

public struct RegisterSearchFilter: Hashable, Sendable {
    public var label: String
    public var query: RegisterSearchQuery
}

public struct RegisterSearchInfo: Hashable, Sendable {
    public var message: String
    public var clearButtonTitle: String?
}
