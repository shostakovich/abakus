import CoreGraphics

/// Fixed widths for the date, the amounts and the status; where the texts get too little, the phone's cards show.
public struct RegisterTouchTable: Hashable, Sendable {
    enum Sizing: Hashable, Sendable {
        case fixed(CGFloat)
        case share(CGFloat)
    }

    public static let spacing: CGFloat = 12
    public static let statusWidth: CGFloat = 32
    static let dateWidth: CGFloat = 52
    static let amountWidth: CGFloat = 92
    static let minimumShareWidth: CGFloat = 36

    /// The status always last.
    public let columns: [RegisterColumn]
    let scale: CGFloat

    /// `scale` grows the date, the amounts and the texts' minimum with the text size.
    public init(visibleColumns: [RegisterColumn], scale: CGFloat = 1) {
        columns = visibleColumns.filter { $0 != .cleared && $0 != .repeats } + [.cleared]
        self.scale = scale
    }

    private func sizing(of column: RegisterColumn) -> Sizing {
        switch column {
        case .date: .fixed(Self.dateWidth * scale)
        case .amount: .fixed(Self.amountWidth * scale)
        case .cleared: .fixed(Self.statusWidth)
        case .payee: .share(3.5)
        case .category: .share(3)
        case .account, .repeats: .share(2)
        case .memo: .share(1.5)
        }
    }

    public func fits(in width: CGFloat) -> Bool {
        let (fixed, shares) = totals
        return shares == 0 || width - fixed >= shares * Self.minimumShareWidth * scale
    }

    public func widths(in total: CGFloat) -> [CGFloat] {
        let (fixed, shares) = totals
        let unit = shares > 0 ? max(0, total - fixed) / shares : 0
        return columns.map { column in
            switch sizing(of: column) {
            case .fixed(let width): width
            case .share(let share): share * unit
            }
        }
    }

    private var totals: (fixed: CGFloat, shares: CGFloat) {
        var fixed = Self.spacing * CGFloat(max(columns.count - 1, 0))
        var shares: CGFloat = 0
        for column in columns {
            switch sizing(of: column) {
            case .fixed(let width): fixed += width
            case .share(let share): shares += share
            }
        }
        return (fixed, shares)
    }
}
