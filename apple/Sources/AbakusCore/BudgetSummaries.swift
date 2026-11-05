import Foundation

public enum OutflowSummarySource: Hashable, Sendable {
    case category(String)
    case masterCategory(String)
    case allOutflows
}

public struct TransactionSummaryRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let transactionId: String
    public let date: DateWithoutTime
    public let accountName: String
    public let payee: String
    public let memo: String
    public let amount: Decimal
}

public struct AccountViewFilter: Hashable, Sendable {
    public let accountId: String
    public let searchText: String
    public let dateFilter: DateFilterSelection
}

public struct TransactionSummary: Hashable, Sendable {
    public let title: String
    public let message: String
    public let rows: [TransactionSummaryRow]
    public let transactionCount: Int
    public let accountView: AccountViewFilter?
}

extension Budget {
    public func outflowSummary(
        _ source: OutflowSummarySource, month: DateWithoutTime, today: DateWithoutTime, formatter: BudgetFormatter
    ) -> TransactionSummary {
        let (title, wanted, search) = outflowSummarySubject(source)
        let activity = BudgetActivity(self)
        var rows: [(row: TransactionSummaryRow, accountId: String)] = []
        var count = 0
        var spent: Decimal = 0
        for transaction in transactions where transaction.date.monthKey == month.monthKey {
            let matching = activity.entries(of: transaction).filter { entry in
                guard case .category(let id) = entry.bucket else { return false }
                return wanted?.contains(id) ?? true
            }
            guard !matching.isEmpty else { continue }
            count += 1
            spent = Amount.round(spent - Amount.sum(matching.map(\.amount)))
            if !transaction.isSplit {
                rows.append((summaryRow(transaction), transaction.accountId))
                continue
            }
            let lines =
                wanted == nil
                ? transaction.subtransactions.filter { !isReadyToAssign($0.categoryId) }
                : matching.compactMap(\.line)
            rows += lines.map { (summaryRow($0, of: transaction), transaction.accountId) }
        }
        let amount = formatter.currency(spent)
        let transactions = count == 1 ? "1 Buchung" : "\(count) Buchungen"
        let message =
            source == .masterCategory(EntityID.uncategorizedMasterCategory)
            ? "\(amount) ausgegeben in \(transactions) ohne Kategorie:" : "\(amount) ausgegeben in \(transactions):"
        return summary(
            title: title, message: message, rows: rows, count: count, search: search, today: today,
            formatter: formatter)
    }

    private func outflowSummarySubject(_ source: OutflowSummarySource) -> (
        title: String, categories: Set<String>?, search: String
    ) {
        switch source {
        case .category(let id):
            let name = categoryDisplayName(id)
            return (name, [id], "Kategorie: \(name), ")
        case .masterCategory(EntityID.uncategorizedMasterCategory):
            return (DefaultCategories.uncategorizedName, [EntityID.uncategorizedCategory], "Kategorie: , ")
        case .masterCategory(let id):
            let master = budgetCategoryGroups.first { $0.id == id }
            let name = master?.name ?? ""
            return (name, Set(master?.categories.map(\.id) ?? []), "Kategorie: \(name), ")
        case .allOutflows:
            return ("Alle Kategorien", nil, "")
        }
    }

    private func summary(
        title: String, message: String, rows: [(row: TransactionSummaryRow, accountId: String)], count: Int,
        search: String, today: DateWithoutTime, formatter: BudgetFormatter
    ) -> TransactionSummary {
        let sorted = rows.enumerated().sorted { ($1.element.row.date, $0.offset) < ($0.element.row.date, $1.offset) }
            .map(\.element)
        var accountView: AccountViewFilter?
        if let first = sorted.first {
            let accounts = Set(sorted.map(\.accountId))
            let dates = sorted.map(\.row.date)
            accountView = AccountViewFilter(
                accountId: accounts.count > 1 ? EntityID.allAccounts : first.accountId, searchText: search,
                dateFilter: Self.dateFilter(
                    from: dates.min() ?? today, to: dates.max() ?? today, today: today, formatter: formatter))
        }
        return TransactionSummary(
            title: title, message: message, rows: sorted.map(\.row), transactionCount: count,
            accountView: accountView)
    }

    private static func dateFilter(
        from earliest: DateWithoutTime, to latest: DateWithoutTime, today: DateWithoutTime, formatter: BudgetFormatter
    ) -> DateFilterSelection {
        let start = earliest.firstOfMonth
        let end = latest.firstOfMonth
        if start == end && start == today.firstOfMonth {
            return DateFilterSelection(
                preset: .thisMonth, start: start, end: end, label: DateFilterPreset.thisMonth.label)
        }
        let label =
            start == end
            ? formatter.monthHeader(start) : "\(formatter.monthHeader(start)) bis \(formatter.monthHeader(end))"
        return DateFilterSelection(preset: nil, start: start, end: end, label: label)
    }

    private func summaryRow(_ transaction: Transaction) -> TransactionSummaryRow {
        TransactionSummaryRow(
            id: transaction.id, transactionId: transaction.id, date: transaction.date,
            accountName: account(withId: transaction.accountId)?.name ?? "", payee: payeeName(of: transaction),
            memo: transaction.memo ?? "", amount: transaction.amount)
    }

    private func summaryRow(_ line: Subtransaction, of parent: Transaction) -> TransactionSummaryRow {
        var payee = "[Aufgeteilt] "
        let target = transferAccountId(of: line).flatMap(account(withId:))
        let ownPayee = target == nil ? line.payeeId.flatMap(payee(withId:))?.name ?? "" : ""
        let shownPayee = ownPayee.isEmpty ? payeeName(of: parent) : ownPayee
        if !shownPayee.isEmpty { payee += shownPayee + " " }
        if let target { payee += "/ " + target.transferPayeeName }
        let lineMemo = line.memo ?? ""
        let parentMemo = parent.memo ?? ""
        let memo = lineMemo.isEmpty ? parentMemo : parentMemo.isEmpty ? lineMemo : "\(lineMemo) - \(parentMemo)"
        return TransactionSummaryRow(
            id: line.id, transactionId: parent.id, date: parent.date,
            accountName: account(withId: parent.accountId)?.name ?? "", payee: payee, memo: memo,
            amount: line.amount)
    }
}
