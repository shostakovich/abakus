import CoreGraphics

public enum RegisterColumn: String, CaseIterable, Hashable, Sendable {
    case account, date, payee, category, memo, amount
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
        case .category: .text("Kategorie")
        case .memo: .text("Memo")
        case .amount: .text("Betrag")
        case .runningBalance: .text("Saldo")
        case .cleared: .symbol("checkmark.circle", label: "Status")
        case .frequency: .text("Häufigkeit")
        }
    }

    public var isAmount: Bool { self == .amount || self == .runningBalance }

    public var minWidth: CGFloat {
        switch self {
        case .cleared: 32
        case .account, .payee, .category, .memo, .frequency: 50
        case .date: 92
        case .amount: Self.signedAmountWidth
        case .runningBalance: Self.amountWidth
        }
    }

    /// Wide enough for "−10.000,00" in the register's font.
    static let amountWidth: CGFloat = ceil(
        ThemeFont.tableEmphasized.width(of: "−10.000,00") + 2 * RegisterGridStyle.cellInset)

    /// Betrag also fits the editor's calculator and sign button at the field's start.
    static let signedAmountWidth: CGFloat = amountWidth + EditCellStyle.amountAccessoriesWidth

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
        case .category: RegisterColumnSetting(visible: true, width: 175)
        case .memo: RegisterColumnSetting(visible: true, width: 50)
        case .amount: RegisterColumnSetting(visible: true, width: Self.signedAmountWidth)
        case .runningBalance: RegisterColumnSetting(visible: false, width: Self.amountWidth)
        case .cleared: RegisterColumnSetting(visible: true, width: 15)
        case .frequency: nil
        }
    }

    public var menuLabel: String {
        switch self {
        case .cleared: "Status"
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
            gridWidth: max(0, gridWidth - RegisterMetrics.leadingInset), visibleColumns: visibleColumns,
            settings: settings, minimumWidths: minimumWidths, contentWidths: contentWidths)
        var frames: [RegisterColumnFrame] = []
        var exactX = RegisterMetrics.leadingInset
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

    /// The memo takes what the other text columns leave; on a narrow grid it keeps its minimum and they shrink.
    static func widths(
        gridWidth: CGFloat, visibleColumns: [RegisterColumn], settings: RegisterColumnSettings,
        minimumWidths: [RegisterColumn: CGFloat] = [:], contentWidths: [RegisterColumn: CGFloat] = [:]
    ) -> [CGFloat] {
        let widths = sharedWidths(
            gridWidth: gridWidth, visibleColumns: visibleColumns, settings: settings, minimumWidths: minimumWidths,
            contentWidths: contentWidths)
        let memoMinimum = minimumWidths[.memo] ?? RegisterColumn.memo.minWidth
        guard contentWidths[.memo] == nil, let memo = visibleColumns.firstIndex(of: .memo),
            widths[memo] < memoMinimum
        else { return widths }
        return sharedWidths(
            gridWidth: gridWidth, visibleColumns: visibleColumns, settings: settings, minimumWidths: minimumWidths,
            contentWidths: contentWidths.merging([.memo: memoMinimum]) { $1 })
    }

    private static func sharedWidths(
        gridWidth: CGFloat, visibleColumns: [RegisterColumn], settings: RegisterColumnSettings,
        minimumWidths: [RegisterColumn: CGFloat], contentWidths: [RegisterColumn: CGFloat]
    ) -> [CGFloat] {
        let isFlexible = { (column: RegisterColumn) in column.isResizable && contentWidths[column] == nil }
        let minimumWidth = { (column: RegisterColumn) in
            contentWidths[column] ?? minimumWidths[column] ?? column.minWidth
        }
        let settingWidth = { (column: RegisterColumn) in max(0, settings[column]?.width ?? column.minWidth) }
        let fixedSum = visibleColumns.filter { !isFlexible($0) }.reduce(CGFloat(0)) { $0 + minimumWidth($1) }
        let flexibleSum = visibleColumns.filter(isFlexible).reduce(CGFloat(0)) { $0 + settingWidth($1) }
        let displayWidth = max(0, gridWidth - RegisterMetrics.columnMenuWidth)
        let scale = flexibleSum > 0 ? (displayWidth - fixedSum) / flexibleSum : 1
        let current = visibleColumns.map { isFlexible($0) ? settingWidth($0) * scale : minimumWidth($0) }
        var widths = distribute(
            current, columns: visibleColumns, displayWidth: displayWidth, isFlexible: isFlexible,
            minimumWidth: minimumWidth)
        giveRoomToMemo(&widths, columns: visibleColumns, settings: settings, isFlexible: isFlexible)
        return widths
    }

    /// The other text columns grow no wider than their setting; the memo takes the rest.
    private static func giveRoomToMemo(
        _ widths: inout [CGFloat], columns: [RegisterColumn], settings: RegisterColumnSettings,
        isFlexible: (RegisterColumn) -> Bool
    ) {
        guard let memo = columns.firstIndex(of: .memo), isFlexible(.memo) else { return }
        for index in columns.indices where index != memo && isFlexible(columns[index]) {
            guard let setting = settings[columns[index]], widths[index] > setting.width else { continue }
            widths[memo] += widths[index] - setting.width
            widths[index] = setting.width
        }
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

    /// Flex would hand the last column a negative width on a narrow All Accounts grid; borrow it instead.
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
