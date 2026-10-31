import CoreGraphics

public enum RegisterColumn: String, CaseIterable, Hashable, Sendable {
    case account, date, payee, errorState, category, memo, outflow, inflow
    case runningBalance, cleared, frequency

    public enum Header: Hashable, Sendable {
        case text(String)
        case symbol(String, label: String)
    }

    public var header: Header {
        switch self {
        case .account: .text("Konto")
        case .date: .text("Datum")
        case .payee: .text("Empfänger")
        case .errorState: .symbol("exclamationmark.triangle", label: "Status")
        case .category: .text("Kategorie")
        case .memo: .text("Memo")
        case .outflow: .text("Ausgang")
        case .inflow: .text("Eingang")
        case .runningBalance: .text("Saldo")
        case .cleared: .symbol("checkmark.circle", label: "Gebucht")
        case .frequency: .text("Häufigkeit")
        }
    }

    public var isAmount: Bool { self == .outflow || self == .inflow || self == .runningBalance }

    public var minWidth: CGFloat {
        switch self {
        case .errorState, .cleared: 32
        case .account, .payee, .category, .memo, .frequency: 50
        case .date: 92
        case .outflow, .inflow, .runningBalance: 70
        }
    }

    public var isResizable: Bool {
        switch self {
        case .account, .payee, .category, .memo, .frequency: true
        default: false
        }
    }

    public var isSortable: Bool { self != .runningBalance }

    public var canDisable: Bool {
        switch self {
        case .memo, .runningBalance, .cleared: true
        default: false
        }
    }

    public var defaultSetting: RegisterColumnSetting? {
        switch self {
        case .account: RegisterColumnSetting(visible: true, width: 75)
        case .date: RegisterColumnSetting(visible: true, width: 55)
        case .payee: RegisterColumnSetting(visible: true, width: 175)
        case .errorState: RegisterColumnSetting(visible: true, width: 23)
        case .category: RegisterColumnSetting(visible: true, width: 175)
        case .memo: RegisterColumnSetting(visible: true, width: 50)
        case .outflow: RegisterColumnSetting(visible: true, width: 70)
        case .inflow: RegisterColumnSetting(visible: true, width: 70)
        case .runningBalance: RegisterColumnSetting(visible: false, width: 70)
        case .cleared: RegisterColumnSetting(visible: true, width: 15)
        case .frequency: nil
        }
    }

    public var menuLabel: String {
        switch self {
        case .cleared: "Gebucht"
        case .memo: "Memo"
        case .runningBalance: "Laufender Saldo"
        default: rawValue
        }
    }
}

public struct RegisterColumnSetting: Hashable, Sendable {
    public var visible: Bool
    public var width: CGFloat

    public init(visible: Bool, width: CGFloat) {
        self.visible = visible
        self.width = width
    }
}

public struct RegisterColumnSettings: Hashable, Sendable {
    private var values: [RegisterColumn: RegisterColumnSetting]

    public init() {
        values = Dictionary(
            uniqueKeysWithValues: RegisterColumn.allCases.compactMap { column in
                column.defaultSetting.map { (column, $0) }
            })
    }

    public subscript(column: RegisterColumn) -> RegisterColumnSetting? {
        get { values[column] }
        set { values[column] = newValue }
    }
}

public struct RegisterColumnFrame: Hashable, Sendable {
    public var column: RegisterColumn
    public var x: CGFloat
    public var width: CGFloat

    public var maxX: CGFloat { x + width }
}

/// The trailing column-menu slot also leaves the system scroller its room.
public struct RegisterColumnLayout: Hashable, Sendable {
    public let gridWidth: CGFloat
    public let frames: [RegisterColumnFrame]

    public var displayWidth: CGFloat { max(0, gridWidth - RegisterMetrics.columnMenuWidth) }

    /// `minimumWidths` overrides a column's minimum, as the reconciliation's 90 pt cleared column does;
    /// `contentWidths` sizes a column to its content, leaving the rest to the flexible columns.
    public init(
        gridWidth: CGFloat, visibleColumns: [RegisterColumn], settings: RegisterColumnSettings,
        minimumWidths: [RegisterColumn: CGFloat] = [:], contentWidths: [RegisterColumn: CGFloat] = [:]
    ) {
        self.gridWidth = gridWidth
        let widths = Self.widths(
            gridWidth: gridWidth, visibleColumns: visibleColumns, settings: settings, minimumWidths: minimumWidths,
            contentWidths: contentWidths)
        var frames: [RegisterColumnFrame] = []
        var exactX: CGFloat = 0
        for (column, width) in zip(visibleColumns, widths) {
            let x = exactX.rounded()
            exactX += width
            frames.append(RegisterColumnFrame(column: column, x: x, width: exactX.rounded() - x))
        }
        self.frames = frames
    }

    public func frame(of column: RegisterColumn) -> RegisterColumnFrame? {
        frames.first { $0.column == column }
    }

    public func column(atX x: CGFloat) -> RegisterColumn? {
        frames.first { x >= $0.x && x < $0.maxX }?.column
    }

    static func widths(
        gridWidth: CGFloat, visibleColumns: [RegisterColumn], settings: RegisterColumnSettings,
        minimumWidths: [RegisterColumn: CGFloat] = [:], contentWidths: [RegisterColumn: CGFloat] = [:]
    ) -> [CGFloat] {
        let isFlexible = { (column: RegisterColumn) in column.isResizable && contentWidths[column] == nil }
        var fixedSum: CGFloat = 0
        var flexibleSum: CGFloat = 0
        for column in RegisterColumn.allCases {
            guard let setting = settings[column], setting.visible else { continue }
            if isFlexible(column) {
                flexibleSum += max(0, setting.width)
            } else {
                fixedSum += max(0, contentWidths[column] ?? setting.width)
            }
        }
        let displayWidth = max(0, gridWidth - RegisterMetrics.columnMenuWidth)
        let scale = flexibleSum > 0 ? (displayWidth - fixedSum) / flexibleSum : 1
        let current = visibleColumns.map { column -> CGFloat in
            if let content = contentWidths[column] { return content }
            guard let setting = settings[column] else { return column.minWidth }
            return column.isResizable ? setting.width * scale : setting.width
        }
        return distribute(
            current, columns: visibleColumns, displayWidth: displayWidth, isFlexible: isFlexible,
            minimumWidth: { contentWidths[$0] ?? minimumWidths[$0] ?? $0.minWidth })
    }

    private static func distribute(
        _ current: [CGFloat], columns: [RegisterColumn], displayWidth: CGFloat,
        isFlexible: (RegisterColumn) -> Bool, minimumWidth: (RegisterColumn) -> CGFloat
    ) -> [CGFloat] {
        let total = current.reduce(0, +)
        guard total > 0, let lastFlexible = columns.lastIndex(where: isFlexible) else {
            return total > 0 ? current.map { $0 * displayWidth / total } : current
        }
        let minimumSum = zip(columns, current).reduce(CGFloat(0)) { sum, pair in
            sum + (isFlexible(pair.0) ? minimumWidth(pair.0) : pair.1)
        }
        var widths = current
        for index in columns.indices {
            let column = columns[index]
            guard isFlexible(column) else {
                widths[index] = minimumWidth(column)
                continue
            }
            let width = current[index]
            let shrink =
                total > displayWidth
                ? (total - displayWidth) * (width - minimumWidth(column)) / max(1, total - minimumSum)
                : (total - displayWidth) * width / total
            widths[index] = max(width - shrink, minimumWidth(column))
        }
        widths[lastFlexible] += displayWidth - widths.reduce(0, +)
        if widths[lastFlexible] < 0 {
            takeDeficit(from: &widths, columns: columns, last: lastFlexible, isFlexible: isFlexible)
        }
        return widths
    }

    /// Flex would hand the last column a negative width (All Accounts with the error column); borrow it instead.
    private static func takeDeficit(
        from widths: inout [CGFloat], columns: [RegisterColumn], last: Int, isFlexible: (RegisterColumn) -> Bool
    ) {
        let deficit = -widths[last]
        widths[last] = 0
        let donors = columns.indices.filter { $0 != last && isFlexible(columns[$0]) }
        let spare = donors.reduce(CGFloat(0)) { $0 + max(0, widths[$1] - columns[$1].minWidth) }
        guard spare > 0 else { return }
        for index in donors {
            widths[index] -= deficit * max(0, widths[index] - columns[index].minWidth) / spare
        }
    }
}
