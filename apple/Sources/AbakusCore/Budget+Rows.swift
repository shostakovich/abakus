import Foundation

public typealias SyncRows = [String: [String: SyncRow]]

extension Budget {
    /// Every live row with all its table's columns; what is deleted is absent.
    public var syncedRows: SyncRows {
        var rows = RowCollector()
        for kind in RowKind.all { kind.collect(self, &rows) }
        return rows.rows
    }

    /// The rows of whatever differs from `old`, as they were and as they are: unchanged rows are in neither.
    func changedRows(since old: Budget) -> (old: SyncRows, new: SyncRows) {
        var before = RowCollector()
        var after = RowCollector()
        for kind in RowKind.all {
            kind.collectChanges(old, self, &before, &after)
        }
        return (before.rows, after.rows)
    }

    /// The live rows of the store; whatever points at a deleted category or a merged payee points at its successor.
    public init(syncedRows rows: SyncRows, local settings: LocalBudgetSettings) {
        let live = rows.mapValues { $0.filter { !$0.value.isDeleted } }
        func table(_ name: String) -> [(id: String, row: SyncRow)] {
            (live[name] ?? [:]).map { ($0.key, $0.value) }.sorted { Self.order($0, $1) }
        }
        let successors = Self.successors(in: rows, tables: ["categories", "payees"])
        let resolve = SuccessorChain(successors)

        let groups = table("category_groups").compactMap { CategoryGroup(id: $0.id, row: $0.row) }
        let groupIds = Set(groups.map(\.id))
        let categories = table("categories").compactMap { Category(id: $0.id, row: $0.row) }
            .filter { groupIds.contains($0.categoryGroupId) }
        let categoryIds = Set(categories.map(\.id))
        let payees = table("payees").compactMap { Payee(id: $0.id, row: $0.row, resolve: resolve) }
        let payeeIds = Set(payees.map(\.id))
        let transactions = Self.transactions(table("transactions"), parts: table("subtransactions"), resolve: resolve)
        let scheduled = Self.scheduled(
            table("scheduled_transactions"), parts: table("scheduled_subtransactions"), resolve: resolve)

        self.init(
            budgetName: settings.budgetName,
            budgetMetaData: settings.budgetMetaData,
            collapsedCategoryGroupIds: settings.collapsedCategoryGroupIds,
            accounts: table("accounts").compactMap { Account(id: $0.id, row: $0.row) },
            categoryGroups: groups.map { group in
                var filled = group
                filled.categories = categories.filter { $0.categoryGroupId == group.id }
                return filled
            },
            payees: payees,
            payeeRenameConditions: table("payee_rename_conditions")
                .compactMap { PayeeRenameCondition(id: $0.id, row: $0.row) }
                .filter { payeeIds.contains($0.payeeId) },
            transactions: transactions,
            scheduledTransactions: scheduled,
            assignments: table("assignments").compactMap { Assignment(id: $0.id, row: $0.row, resolve: resolve) }
                .filter { categoryIds.contains($0.categoryId) },
            targetVersions: table("target_versions").compactMap { TargetVersion(id: $0.id, row: $0.row) }
                .filter { categoryIds.contains($0.categoryId) },
            targetSnoozes: table("target_snoozes").compactMap { TargetSnooze(id: $0.id, row: $0.row) }
                .filter { categoryIds.contains($0.categoryId) },
            successorIds: successors)
    }

    private static func order(_ lhs: (id: String, row: SyncRow), _ rhs: (id: String, row: SyncRow)) -> Bool {
        (lhs.row.integer("position") ?? 0, lhs.id) < (rhs.row.integer("position") ?? 0, rhs.id)
    }

    private static func successors(in rows: SyncRows, tables: [String]) -> [String: String] {
        var successors: [String: String] = [:]
        for name in tables {
            for (id, row) in rows[name] ?? [:] where row.isDeleted {
                if let successor = row.text("successor_id") { successors[id] = successor }
            }
        }
        return successors
    }

    private static func transactions(
        _ rows: [(id: String, row: SyncRow)], parts: [(id: String, row: SyncRow)], resolve: SuccessorChain
    ) -> [Transaction] {
        let partsByParent = Dictionary(grouping: parts, by: { $0.row.text("transaction_id") ?? "" })
        return rows.compactMap { entry in
            var transaction = Transaction(id: entry.id, row: entry.row, resolve: resolve)
            transaction?.subtransactions = (partsByParent[entry.id] ?? []).compactMap {
                Subtransaction(id: $0.id, row: $0.row, parent: "transaction_id", resolve: resolve)
            }
            return transaction
        }
    }

    private static func scheduled(
        _ rows: [(id: String, row: SyncRow)], parts: [(id: String, row: SyncRow)], resolve: SuccessorChain
    ) -> [ScheduledTransaction] {
        let partsByParent = Dictionary(grouping: parts, by: { $0.row.text("scheduled_transaction_id") ?? "" })
        return rows.compactMap { entry in
            var scheduled = ScheduledTransaction(id: entry.id, row: entry.row, resolve: resolve)
            scheduled?.subtransactions = (partsByParent[entry.id] ?? []).compactMap {
                Subtransaction(id: $0.id, row: $0.row, parent: "scheduled_transaction_id", resolve: resolve)
            }
            return scheduled
        }
    }
}

struct RowCollector {
    var rows: SyncRows = [:]

    mutating func put(_ table: String, _ id: String, _ fields: SyncRow) {
        var row = fields
        for column in SyncTable.named(table)?.columns ?? [] where row[column.name] == nil {
            row[column.name] = .null
        }
        rows[table, default: [:]][id] = row
    }
}

struct RowKind {
    let collect: (_ budget: Budget, _ rows: inout RowCollector) -> Void
    let collectChanges:
        (_ old: Budget, _ new: Budget, _ before: inout RowCollector, _ after: inout RowCollector) -> Void

    init<Element: Hashable & Identifiable>(
        _ elements: KeyPath<Budget, [Element]>, rows: @escaping (Element, inout RowCollector) -> Void
    ) where Element.ID == String {
        collect = { budget, collector in
            for element in budget[keyPath: elements] { rows(element, &collector) }
        }
        collectChanges = { old, new, before, after in
            let oldElements = old[keyPath: elements]
            let newElements = new[keyPath: elements]
            guard oldElements != newElements else { return }
            let oldById = Dictionary(oldElements.map { ($0.id, $0) }) { first, _ in first }
            var newIds = Set<String>()
            for element in newElements {
                newIds.insert(element.id)
                let previous = oldById[element.id]
                guard previous != element else { continue }
                rows(element, &after)
                if let previous { rows(previous, &before) }
            }
            for element in oldElements where !newIds.contains(element.id) { rows(element, &before) }
        }
    }

    static var all: [RowKind] {
        [
            RowKind(\.accounts) { $1.put("accounts", $0.id, $0.row) },
            RowKind(\.payees) { $1.put("payees", $0.id, $0.row) },
            RowKind(\.payeeRenameConditions) { $1.put("payee_rename_conditions", $0.id, $0.row) },
            RowKind(\.categoryGroups) { group, rows in
                rows.put("category_groups", group.id, group.row)
                for category in group.categories { rows.put("categories", category.id, category.row) }
            },
            RowKind(\.assignments) { $1.put("assignments", $0.id, $0.row) },
            RowKind(\.targetVersions) { $1.put("target_versions", $0.id, $0.row) },
            RowKind(\.targetSnoozes) { $1.put("target_snoozes", $0.id, $0.row) },
            RowKind(\.scheduledTransactions) { scheduled, rows in
                rows.put("scheduled_transactions", scheduled.id, scheduled.row)
                for (position, part) in scheduled.subtransactions.enumerated() {
                    rows.put("scheduled_subtransactions", part.id, part.scheduledRow(position: position))
                }
            },
            RowKind(\.transactions, rows: transactionRows),
            RowKind(\.matchProposals, rows: transactionRows),
        ]
    }

    private static func transactionRows(_ transaction: Transaction, _ rows: inout RowCollector) {
        rows.put("transactions", transaction.id, transaction.row)
        for (position, part) in transaction.subtransactions.enumerated() {
            rows.put("subtransactions", part.id, part.row(position: position))
        }
    }
}

public struct LocalBudgetSettings: Hashable, Sendable {
    public var budgetName: String
    public var budgetMetaData: BudgetMetaData
    public var collapsedCategoryGroupIds: Set<String>

    public init(
        budgetName: String, budgetMetaData: BudgetMetaData = BudgetMetaData(),
        collapsedCategoryGroupIds: Set<String> = []
    ) {
        self.budgetName = budgetName
        self.budgetMetaData = budgetMetaData
        self.collapsedCategoryGroupIds = collapsedCategoryGroupIds
    }
}

extension Budget {
    public var localSettings: LocalBudgetSettings {
        LocalBudgetSettings(
            budgetName: budgetName, budgetMetaData: budgetMetaData,
            collapsedCategoryGroupIds: collapsedCategoryGroupIds)
    }
}

/// Follows successors to a live row; a chain that comes back ends at the smallest id of its cycle.
struct SuccessorChain {
    let successors: [String: String]

    init(_ successors: [String: String]) {
        self.successors = successors
    }

    func callAsFunction(_ id: String?) -> String? {
        guard var current = id else { return nil }
        var seen: [String] = []
        while let next = successors[current] {
            if let start = seen.firstIndex(of: current) { return seen[start...].min() }
            seen.append(current)
            current = next
        }
        return current
    }
}

extension Account {
    var row: SyncRow {
        [
            "name": .text(name), "kind": .of(kind), "shared_expenses": .bool(sharedExpenses), "closed": .bool(closed),
            "note": .of(note), "position": .integer(position), "last_reconciled_at": .moment(lastReconciledAt),
        ]
    }

    init?(id: String, row: SyncRow) {
        guard let name = row.text("name"), let kind: AccountKind = row.enumValue("kind") else { return nil }
        self.init(
            id: id, name: name, kind: kind, sharedExpenses: row.bool("shared_expenses") ?? false,
            closed: row.bool("closed") ?? false, note: row.text("note"), position: row.integer("position") ?? 0,
            lastReconciledAt: row.moment("last_reconciled_at"))
    }
}

extension Payee {
    var row: SyncRow {
        [
            "name": .text(name), "hidden": .bool(hidden), "transfer_account_id": .of(transferAccountId),
            "last_category_id": .of(lastCategoryId),
        ]
    }

    init?(id: String, row: SyncRow, resolve: SuccessorChain) {
        guard let name = row.text("name") else { return nil }
        self.init(
            id: id, name: name, hidden: row.bool("hidden") ?? false,
            transferAccountId: row.text("transfer_account_id"),
            lastCategoryId: resolve(row.text("last_category_id")))
    }
}

extension PayeeRenameCondition {
    var row: SyncRow {
        [
            "payee_id": .text(payeeId), "position": .integer(position), "operator": .of(self.operator),
            "text": .text(text),
        ]
    }

    init?(id: String, row: SyncRow) {
        guard let payeeId = row.text("payee_id"), let condition: StringOperator = row.enumValue("operator") else {
            return nil
        }
        self.init(
            id: id, payeeId: payeeId, position: row.integer("position") ?? 0, operator: condition,
            text: row.text("text") ?? "")
    }
}

extension CategoryGroup {
    var row: SyncRow {
        [
            "name": .text(name), "hidden": .bool(hidden), "internal": .bool(isInternal), "position": .integer(position),
            "note": .of(note),
        ]
    }

    init?(id: String, row: SyncRow) {
        guard let name = row.text("name") else { return nil }
        self.init(
            id: id, name: name, hidden: row.bool("hidden") ?? false, isInternal: row.bool("internal") ?? false,
            position: row.integer("position") ?? 0, note: row.text("note"))
    }
}

extension Category {
    var row: SyncRow {
        [
            "category_group_id": .text(categoryGroupId), "name": .text(name), "hidden": .bool(hidden),
            "internal": .bool(isInternal), "position": .integer(position), "note": .of(note),
        ]
    }

    init?(id: String, row: SyncRow) {
        guard let groupId = row.text("category_group_id"), let name = row.text("name") else { return nil }
        self.init(
            id: id, categoryGroupId: groupId, name: name, hidden: row.bool("hidden") ?? false,
            isInternal: row.bool("internal") ?? false, position: row.integer("position") ?? 0,
            note: row.text("note"))
    }
}

extension Assignment {
    var row: SyncRow {
        ["category_id": .text(categoryId), "month": .date(month), "amount": .cents(amount)]
    }

    init?(id: String, row: SyncRow, resolve: SuccessorChain) {
        guard let categoryId = resolve(row.text("category_id")), let month = row.date("month"),
            let amount = row.amount("amount")
        else { return nil }
        self.init(id: id, categoryId: categoryId, month: month, amount: amount)
    }
}

extension TargetVersion {
    var row: SyncRow {
        [
            "category_id": .text(categoryId), "from_month": .date(fromMonth), "cadence": .of(cadence),
            "amount": .cents(amount), "due_on": .date(dueOn), "repeats_yearly": .bool(repeatsYearly),
            "set_aside": .bool(setAside),
        ]
    }

    init?(id: String, row: SyncRow) {
        guard let categoryId = row.text("category_id"), let fromMonth = row.date("from_month"),
            let cadence: TargetCadence = row.enumValue("cadence")
        else { return nil }
        self.init(
            categoryId: categoryId, fromMonth: fromMonth,
            target: Target(
                cadence: cadence, amount: row.amount("amount") ?? 0, dueOn: row.date("due_on"),
                repeatsYearly: row.bool("repeats_yearly") ?? false, setAside: row.bool("set_aside") ?? true))
        self.id = id
    }
}

extension TargetSnooze {
    var row: SyncRow {
        ["category_id": .text(categoryId), "month": .date(month)]
    }

    init?(id: String, row: SyncRow) {
        guard let categoryId = row.text("category_id"), let month = row.date("month") else { return nil }
        self.init(categoryId: categoryId, month: month)
        self.id = id
    }
}

extension ScheduledTransaction {
    var row: SyncRow {
        [
            "account_id": .text(accountId), "next_date": .date(nextDate), "frequency": .of(frequency),
            "first_day": .of(firstDay), "second_day": .of(secondDay), "amount": .cents(amount), "memo": .of(memo),
            "cleared": .of(cleared), "payee_id": .of(payeeId), "category_id": .of(categoryId),
        ]
    }

    init?(id: String, row: SyncRow, resolve: SuccessorChain) {
        guard let accountId = row.text("account_id"), let nextDate = row.date("next_date"),
            let frequency: ScheduledTransactionFrequency = row.enumValue("frequency"),
            let amount = row.amount("amount")
        else { return nil }
        let days = row.integer("first_day").flatMap { first in row.integer("second_day").map { (first, $0) } }
        self.init(
            id: id, accountId: accountId, nextDate: nextDate, frequency: frequency, days: days,
            payeeId: resolve(row.text("payee_id")), categoryId: resolve(row.text("category_id")),
            memo: row.text("memo"), amount: amount, cleared: row.enumValue("cleared") ?? .uncleared)
    }
}

extension Transaction {
    var row: SyncRow {
        [
            "account_id": .text(accountId), "date": .date(date), "amount": .cents(amount), "memo": .of(memo),
            "cleared": .of(cleared), "approved": .bool(approved), "source": .of(source),
            "scheduled_date": .date(scheduledDate), "led_by": .of(ledBy), "payee_id": .of(payeeId),
            "category_id": .of(categoryId), "transfer_transaction_id": .of(transferTransactionId),
            "transfer_subtransaction_id": .of(transferSubtransactionId),
            "matched_transaction_id": .of(matchedTransactionId),
            "scheduled_transaction_id": .of(scheduledTransactionId),
        ]
    }

    init?(id: String, row: SyncRow, resolve: SuccessorChain) {
        guard let accountId = row.text("account_id"), let date = row.date("date"), let amount = row.amount("amount")
        else { return nil }
        self.init(
            id: id, accountId: accountId, date: date, payeeId: resolve(row.text("payee_id")),
            categoryId: resolve(row.text("category_id")), memo: row.text("memo"), amount: amount,
            cleared: row.enumValue("cleared") ?? .uncleared, approved: row.bool("approved") ?? false,
            source: row.enumValue("source") ?? .manual, ledBy: row.enumValue("led_by"),
            transferTransactionId: row.text("transfer_transaction_id"),
            transferSubtransactionId: row.text("transfer_subtransaction_id"),
            matchedTransactionId: row.text("matched_transaction_id"),
            scheduledTransactionId: row.text("scheduled_transaction_id"), scheduledDate: row.date("scheduled_date"))
    }
}

extension Subtransaction {
    func row(position: Int) -> SyncRow {
        [
            "transaction_id": .text(transactionId), "position": .integer(position), "amount": .cents(amount),
            "memo": .of(memo), "category_id": .of(categoryId), "payee_id": .of(payeeId),
            "transfer_transaction_id": .of(transferTransactionId),
        ]
    }

    func scheduledRow(position: Int) -> SyncRow {
        [
            "scheduled_transaction_id": .text(transactionId), "position": .integer(position),
            "amount": .cents(amount), "memo": .of(memo), "category_id": .of(categoryId), "payee_id": .of(payeeId),
        ]
    }

    init?(id: String, row: SyncRow, parent: String, resolve: SuccessorChain) {
        guard let parentId = row.text(parent), let amount = row.amount("amount") else { return nil }
        self.init(
            id: id, transactionId: parentId, amount: amount, payeeId: resolve(row.text("payee_id")),
            categoryId: resolve(row.text("category_id")), memo: row.text("memo"),
            transferTransactionId: row.text("transfer_transaction_id"))
    }
}
