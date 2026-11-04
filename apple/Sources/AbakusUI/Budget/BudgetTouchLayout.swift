import CoreGraphics

/// One month under a sticky header where a month does not fit beside the category column, else the web's months.
public enum BudgetTouchLayout: Hashable, Sendable {
    case phone
    case wide(months: Int, categoryWidth: CGFloat)

    public static let rowInset: CGFloat = 16
    public static let monthGap: CGFloat = 12
    public static let figureSpacing: CGFloat = 14
    /// Fits a month's three totals at the default text size.
    public static let minimumMonthWidth: CGFloat = 260
    static let twoMonthsWidth: CGFloat = 800
    static let threeMonthsWidth: CGFloat = 1110
    static let categoryShare: CGFloat = 0.22
    static let categoryWidthRange: ClosedRange<CGFloat> = 224...320

    public init(isCompact: Bool, width: CGFloat, minimumMonthWidth: CGFloat = Self.minimumMonthWidth) {
        let range = Self.categoryWidthRange
        let category = min(max((width * Self.categoryShare).rounded(.down), range.lowerBound), range.upperBound)
        let ruled = width >= Self.threeMonthsWidth ? 3 : width >= Self.twoMonthsWidth ? 2 : 1
        let fitting = (1...ruled).last { months in
            Self.monthWidth(months: months, width: width, categoryWidth: category) >= minimumMonthWidth
        }
        guard !isCompact, let months = fitting else {
            self = .phone
            return
        }
        self = .wide(months: months, categoryWidth: category)
    }

    public var monthCount: Int {
        switch self {
        case .phone: 1
        case .wide(let months, _): months
        }
    }

    public static func monthWidth(months: Int, width: CGFloat, categoryWidth: CGFloat) -> CGFloat {
        let count = CGFloat(months)
        return (width - 2 * rowInset - categoryWidth - count * monthGap) / count
    }
}
