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
        case subtransaction(parentIndex: Int)
    }

    public var id: String
    public var transactionId: String
    public var kind: Kind
    public var account = ""
    public var date = ""
    public var frequency = ""
    public var payee = ""
    public var payeeTooltip: String?
    public var hasTransferIcon = false
    public var errorLevel = ErrorLevel.none
    public var errorMessage = ""
    public var category = ""
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

    public var isSubtransaction: Bool { kind != .transaction }

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

    var budget: Budget { lookup.budget }

    init(lookup: BudgetLookup, runningBalances: [String: Decimal] = [:]) {
        self.lookup = lookup
        self.formatter = BudgetFormatter(metaData: lookup.budget.budgetMetaData)
        self.runningBalances = runningBalances
    }

    /// The edited record stays collapsed: its edit row shows the split lines.
    func rows<Record: SplittableTransaction & Identifiable>(
        for records: [Record], expandedSplits: Set<String>, editingId: String?,
        row: (Record, _ isExpanded: Bool) -> RegisterRow, subRows: (Record, _ parentIndex: Int) -> [RegisterRow]
    ) -> [RegisterRow] where Record.ID == String {
        var rows: [RegisterRow] = []
        for record in records {
            let isExpanded = record.isSplit && expandedSplits.contains(record.id) && record.id != editingId
            let parentIndex = rows.count
            rows.append(row(record, isExpanded))
            if isExpanded { rows += subRows(record, parentIndex) }
        }
        return rows
    }

    func row(for transaction: Transaction, isExpanded: Bool) -> RegisterRow {
        let errorState = lookup.errorState(of: transaction)
        var row = baseRow(transaction, isExpanded: isExpanded)
        row.errorLevel = errorState.level
        row.errorMessage = errorState.message
        if needsCategory(transaction, level: errorState.level) { row.category = Self.needsCategoryPrompt }
        row.categoryStyle = Self.categoryStyle(errorState.level)
        row.runningBalance = runningBalances[transaction.id].map(formatter.currencyNoSymbol) ?? ""
        row.cleared = transaction.cleared
        row.textStyle = errorState.level == .forReview ? .bold : .plain
        return row
    }

    func row(for scheduled: ScheduledTransaction, isExpanded: Bool) -> RegisterRow {
        var row = baseRow(scheduled.editableTransaction, isExpanded: isExpanded)
        row.frequency = scheduled.frequency.readableName
        return row
    }

    func subRows(for transaction: Transaction, parentIndex: Int, match: RegisterSearchMatch? = nil) -> [RegisterRow] {
        zip(transaction.subtransactions, baseSubRows(transaction, parentIndex: parentIndex)).map { sub, base in
            let errorState = lookup.errorState(of: sub, inAccount: transaction.accountId)
            var row = base
            row.errorLevel = errorState.level
            row.errorMessage = errorState.message
            if !EntityID.isCategorized(sub.categoryId) && errorState.level == .needsCategory && sub.amount != 0 {
                row.category = Self.needsCategoryPrompt
            }
            row.categoryStyle = Self.categoryStyle(errorState.level)
            row.isExcludedFromSearch = !(match?.subMatches(sub.id) ?? true)
            return row
        }
    }

    func subRows(for scheduled: ScheduledTransaction, parentIndex: Int) -> [RegisterRow] {
        baseSubRows(scheduled.editableTransaction, parentIndex: parentIndex)
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
        row.date = formatter.dateShort(transaction.date)
        row.payee = lookup.payeeName(of: transaction)
        row.payeeTooltip = row.payee.isEmpty ? nil : row.payee
        row.hasTransferIcon = isTransfer(lookup.transferAccountId(of: transaction))
        row.category = account?.onBudget == true ? lookup.categoryDisplayName(of: transaction) : ""
        row.split = transaction.isSplit ? (isExpanded ? .expanded : .collapsed) : .none
        row.memo = transaction.memo ?? ""
        row.outflow = formatter.registerAmount(transaction.outflow)
        row.inflow = formatter.registerAmount(transaction.inflow)
        row.amount = transaction.amount
        return row
    }

    private func baseSubRows(_ transaction: Transaction, parentIndex: Int) -> [RegisterRow] {
        transaction.subtransactions.map { sub in
            var row = RegisterRow(
                id: sub.id, transactionId: transaction.id, kind: .subtransaction(parentIndex: parentIndex))
            row.payee = lookup.payeeName(of: sub)
            row.hasTransferIcon = isTransfer(lookup.transferAccountId(of: sub))
            row.category = budget.categoryDisplayName(sub.categoryId)
            row.memo = sub.memo ?? ""
            row.outflow = formatter.registerAmount(sub.outflow)
            row.inflow = formatter.registerAmount(sub.inflow)
            row.amount = sub.amount
            return row
        }
    }

    private func isTransfer(_ targetId: String?) -> Bool {
        targetId.flatMap(lookup.account(withId:)) != nil
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
