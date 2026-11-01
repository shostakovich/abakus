import AbakusCore
import Foundation

public enum RegisterTextStyle: Hashable, Sendable {
    case plain
    case bold
    case needsCategory
    case error
}

public enum RegisterSplitState: Hashable, Sendable {
    case none, collapsed, expanded
}

public struct RegisterRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case transaction
        case subtransaction
        case monthHeading
    }

    public var id: String
    public var transactionId: String
    public var kind: Kind
    /// A month heading's text, such as "Oktober 2026".
    public var title = ""
    public var account = ""
    public var date = ""
    public var frequency = ""
    public var payee = ""
    public var payeeTooltip: String?
    public var hasTransferIcon = false
    public var errorLevel = ErrorLevel.none
    public var errorMessage = ""
    public var category = ""
    public var categoryTooltip: String?
    public var categoryStyle = RegisterTextStyle.plain
    public var split = RegisterSplitState.none
    public var memo = ""
    public var outflow = ""
    public var inflow = ""
    public var runningBalance = ""
    public var cleared = ClearedStatus.uncleared
    public var textStyle = RegisterTextStyle.plain
    public var amount: Decimal = 0
    /// A split line a search did not match: struck through in grey.
    public var isExcludedFromSearch = false

    public var isSubtransaction: Bool { kind == .subtransaction }

    public var isMonthHeading: Bool { kind == .monthHeading }

    static func monthHeading(_ title: String) -> RegisterRow {
        RegisterRow(id: "month:" + title, transactionId: "", kind: .monthHeading, title: title)
    }

    public var clearedTooltip: String { Self.clearedTooltip(cleared) }

    public static func clearedTooltip(_ status: ClearedStatus) -> String {
        switch status {
        case .cleared:
            "Gebucht: Die Bank kennt diese Buchung. Klicken, um sie als vorgemerkt zu markieren."
        case .uncleared:
            "Vorgemerkt: Die Bank kennt diese Buchung noch nicht. Klicken, um sie als gebucht zu markieren."
        case .reconciled:
            "Abgeglichen: Die Bank kennt diese Buchung, und sie ist mit dem Banksaldo abgeglichen."
        }
    }
}

struct RegisterRowBuilder {
    static let needsCategoryPrompt = "Kategorie fehlt"

    let lookup: BudgetLookup
    let formatter: BudgetFormatter
    let runningBalances: [String: Decimal]
    /// Under month headings a date leaves out its year.
    var showsYear = true

    var budget: Budget { lookup.budget }

    init(lookup: BudgetLookup, runningBalances: [String: Decimal] = [:]) {
        self.lookup = lookup
        self.formatter = BudgetFormatter(metaData: lookup.budget.budgetMetaData)
        self.runningBalances = runningBalances
    }

    /// The edited record stays collapsed: its edit row shows the split lines. A heading precedes each run of records
    /// with the same `heading`.
    func rows<Record: SplittableTransaction & Identifiable>(
        for records: [Record], expandedSplits: Set<String>, editingId: String?,
        heading: (Record) -> String? = { _ in nil },
        row: (Record, _ isExpanded: Bool) -> RegisterRow, subRows: (Record) -> [RegisterRow]
    ) -> [RegisterRow] where Record.ID == String {
        var rows: [RegisterRow] = []
        var currentHeading: String?
        for record in records {
            if let title = heading(record), title != currentHeading {
                currentHeading = title
                rows.append(.monthHeading(title))
            }
            let isExpanded = record.isSplit && expandedSplits.contains(record.id) && record.id != editingId
            rows.append(row(record, isExpanded))
            if isExpanded { rows += subRows(record) }
        }
        return rows
    }

    func row(for transaction: Transaction, isExpanded: Bool) -> RegisterRow {
        let errorState = lookup.errorState(of: transaction)
        var row = baseRow(transaction, isExpanded: isExpanded)
        row.errorLevel = errorState.level
        row.errorMessage = errorState.message
        row.categoryStyle = Self.categoryStyle(errorState.level)
        if needsCategory(transaction, level: errorState.level) { showNeedsCategory(&row) }
        row.runningBalance = runningBalances[transaction.id].map(formatter.currencyNoSymbol) ?? ""
        row.cleared = transaction.cleared
        row.textStyle = errorState.level == .forReview ? .bold : .plain
        return row
    }

    private func showNeedsCategory(_ row: inout RegisterRow) {
        row.category = Self.needsCategoryPrompt
        row.categoryTooltip = nil
        row.categoryStyle = .needsCategory
    }

    func row(for scheduled: ScheduledTransaction, isExpanded: Bool) -> RegisterRow {
        var row = baseRow(scheduled.editableTransaction, isExpanded: isExpanded)
        row.frequency = scheduled.frequency.readableName
        return row
    }

    func subRows(for transaction: Transaction, match: RegisterSearchMatch? = nil) -> [RegisterRow] {
        zip(transaction.subtransactions, baseSubRows(transaction)).map { sub, base in
            let errorState = lookup.errorState(of: sub, inAccount: transaction.accountId)
            var row = base
            row.errorLevel = errorState.level
            row.errorMessage = errorState.message
            row.categoryStyle = Self.categoryStyle(errorState.level)
            if !EntityID.isCategorized(sub.categoryId) && errorState.level == .needsCategory && sub.amount != 0 {
                showNeedsCategory(&row)
            }
            row.isExcludedFromSearch = !(match?.subMatches(sub.id) ?? true)
            return row
        }
    }

    func subRows(for scheduled: ScheduledTransaction) -> [RegisterRow] {
        baseSubRows(scheduled.editableTransaction)
    }

    static func categoryStyle(_ level: ErrorLevel) -> RegisterTextStyle {
        switch level {
        case .none: .plain
        case .forReview: .bold
        case .needsCategory: .needsCategory
        case .error: .error
        }
    }

    private func baseRow(_ transaction: Transaction, isExpanded: Bool) -> RegisterRow {
        let account = lookup.account(withId: transaction.accountId)
        var row = RegisterRow(id: transaction.id, transactionId: transaction.id, kind: .transaction)
        row.account = account?.name ?? ""
        row.date = showsYear ? formatter.dateShort(transaction.date) : formatter.dayMonth(transaction.date)
        setPayee(&row, name: lookup.payeeName(of: transaction), target: lookup.transferAccountId(of: transaction))
        row.payeeTooltip = row.payee.isEmpty ? nil : row.payee
        if account?.onBudget == true {
            if transaction.isSplit {
                row.category = "Aufgeteilt (\(transaction.subtransactions.count))"
            } else {
                setCategory(&row, transaction.categoryId)
            }
        }
        row.split = transaction.isSplit ? (isExpanded ? .expanded : .collapsed) : .none
        row.memo = transaction.memo ?? ""
        row.outflow = formatter.registerAmount(transaction.outflow)
        row.inflow = formatter.registerAmount(transaction.inflow)
        row.amount = transaction.amount
        return row
    }

    private func baseSubRows(_ transaction: Transaction) -> [RegisterRow] {
        transaction.subtransactions.map { sub in
            var row = RegisterRow(
                id: sub.id, transactionId: transaction.id, kind: .subtransaction)
            setPayee(&row, name: lookup.payeeName(of: sub), target: lookup.transferAccountId(of: sub))
            setCategory(&row, sub.categoryId)
            row.memo = sub.memo ?? ""
            row.outflow = formatter.registerAmount(sub.outflow)
            row.inflow = formatter.registerAmount(sub.inflow)
            row.amount = sub.amount
            return row
        }
    }

    /// A transfer shows the account at its other side, after the transfer symbol.
    private func setPayee(_ row: inout RegisterRow, name: String, target: String?) {
        if let account = target.flatMap(lookup.account(withId:)) {
            row.payee = account.name
            row.hasTransferIcon = true
        } else {
            row.payee = name
        }
    }

    /// The category without its group; the group shows in the tooltip.
    private func setCategory(_ row: inout RegisterRow, _ categoryId: String?) {
        row.category = lookup.categoryName(categoryId)
        let qualified = lookup.categoryDisplayName(categoryId)
        row.categoryTooltip = qualified == row.category ? nil : qualified
    }

    private func needsCategory(_ transaction: Transaction, level: ErrorLevel) -> Bool {
        guard lookup.account(withId: transaction.accountId)?.onBudget == true, !transaction.isSplit,
            transaction.amount != 0
        else { return false }
        switch level {
        case .needsCategory: return true
        case .forReview:
            let target = lookup.transferAccountId(of: transaction).flatMap(lookup.account(withId:))
            return !EntityID.isCategorized(transaction.categoryId) && target?.onBudget != true
        default: return false
        }
    }
}
