import AbakusCore
import CoreGraphics
import Foundation

public enum RegisterMetrics {
    public static let notifierBarHeight: CGFloat = 34
    public static let searchInfoBarHeight: CGFloat = 28
    public static let headerHeight: CGFloat = 28
    public static let rowHeight: CGFloat = 28
    public static let columnMenuWidth: CGFloat = 20
    public static let statusBarHeight: CGFloat = 30
    public static let searchFieldWidth: CGFloat = 200
}

/// Where the add editor opens: under the last row while the rows fit, docked at the bottom otherwise.
public enum RegisterAddRowPlacement: Hashable, Sendable {
    case floating(y: CGFloat)
    case docked(y: CGFloat)

    public var y: CGFloat {
        switch self {
        case .floating(let y), .docked(let y): y
        }
    }

    public var isDocked: Bool {
        if case .docked = self { return true }
        return false
    }

    public func listHeight(gridHeight: CGFloat) -> CGFloat {
        let bottom = isDocked ? y : gridHeight
        return max(0, bottom - RegisterMetrics.headerHeight)
    }

    /// `extraHeight` is what an edited row adds to its 28 pt; `editorHeight` is the add editor's, 0 while none is open.
    public static func compute(
        gridHeight: CGFloat, rowCount: Int, extraHeight: CGFloat = 0, editorHeight: CGFloat = 0
    ) -> RegisterAddRowPlacement {
        let header = RegisterMetrics.headerHeight
        let rowsHeight = CGFloat(rowCount) * RegisterMetrics.rowHeight + extraHeight
        let slots = Int((max(0, gridHeight - header) / RegisterMetrics.rowHeight).rounded(.up))
        if rowsHeight >= CGFloat(slots - 1) * RegisterMetrics.rowHeight {
            return .docked(y: max(header, gridHeight - editorHeight))
        }
        let y = header + rowsHeight
        if y + editorHeight > gridHeight - 2 { return .docked(y: max(header, gridHeight - 2 - editorHeight)) }
        return .floating(y: y)
    }
}

/// Content height that keeps a row-aligned top edge when scrolled to the end, like the row-based Flex list.
public func registerListContentHeight(rowCount: Int, viewportHeight: CGFloat, extraHeight: CGFloat = 0) -> CGFloat {
    let rows = CGFloat(rowCount) * RegisterMetrics.rowHeight + extraHeight
    guard rows > viewportHeight else { return viewportHeight }
    return viewportHeight + ((rows - viewportHeight) / RegisterMetrics.rowHeight).rounded(.up)
        * RegisterMetrics.rowHeight
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
