import Foundation

public enum BudgetMonthTiming: Sendable {
    case past, current, future
}

public struct BudgetCategoryFigures: Hashable, Sendable {
    public let assigned: Decimal
    /// Outflows positive, refunds negative.
    public let spent: Decimal
    public let balance: Decimal
    public let transactionCount: Int
    public var target: BudgetTargetFigures?

    public var outflows: Decimal { Amount.round(-spent) }
    public var hasTransactions: Bool { transactionCount > 0 }
    public var isOverspent: Bool { balance < 0 }
}

public struct BudgetMasterFigures: Hashable, Sendable {
    public let assigned: Decimal
    public let spent: Decimal
    public let balance: Decimal
    /// Distinct transactions: a split with lines in two of the master's sub categories counts once.
    public let transactionCount: Int

    public var outflows: Decimal { Amount.round(-spent) }
    public var hasTransactions: Bool { transactionCount > 0 }
}

public struct BudgetShortfall: Hashable, Sendable {
    public let month: DateWithoutTime
    public let amount: Decimal
}

/// `readyToAssign` is cumulative; `available` is the Zu verteilen shown, in an open month less later assignments.
public struct BudgetMonth: Hashable, Sendable {
    public let month: DateWithoutTime
    public let timing: BudgetMonthTiming
    public let previousMonthAvailable: Decimal
    /// Zero or negative, as `overspent`.
    public let previousMonthOverspent: Decimal
    public let income: Decimal
    public let assigned: Decimal
    public let spent: Decimal
    public let balance: Decimal
    public let overspent: Decimal
    public let readyToAssign: Decimal
    public internal(set) var assignedInFuture: Decimal = 0
    public internal(set) var uncovered: [BudgetShortfall] = []
    public let transactionCount: Int
    public let uncategorized: BudgetMasterFigures
    let masters: [String: BudgetMasterFigures]
    let categories: [String: BudgetCategoryFigures]

    public var isClosed: Bool { timing == .past }
    public var available: Decimal { isClosed ? readyToAssign : Amount.round(readyToAssign - assignedInFuture) }
    public var outflows: Decimal { Amount.round(-spent) }
    public var hasTransactions: Bool { transactionCount > 0 }
    public var hasRealData: Bool { income != 0 || assigned != 0 || spent != 0 }
    /// What can be assigned without taking what later months have assigned, in a closed month too.
    public var free: Decimal { max(Amount.round(readyToAssign - assignedInFuture), 0) }
    public var isOverassigned: Bool { available < 0 }
    /// Abakus shows an underfunded target only here: the current month, and any other with money assigned.
    public var isBeingBudgeted: Bool { timing == .current || assigned != 0 }
    public var resultLabel: String {
        guard isClosed else { return "Zu verteilen" }
        return isOverassigned ? "Zu viel verteilt" : "Nicht verteilt am Monatsende"
    }

    public func master(_ categoryGroupId: String) -> BudgetMasterFigures? {
        switch categoryGroupId {
        case EntityID.uncategorizedMasterCategory: uncategorized
        default: masters[categoryGroupId]
        }
    }

    public func category(_ categoryId: String) -> BudgetCategoryFigures? {
        categories[categoryId]
    }
}

public struct BudgetSheet: Sendable {
    public let today: DateWithoutTime
    public let months: [BudgetMonth]
    public let categoryGroups: [CategoryGroup]
    public let showsUncategorizedRow: Bool
    let budget: Budget
    private let firstMonthIndex: Int

    public var readyToAssignCategoryId: String { budget.readyToAssignCategoryId }

    public func isExpanded(_ groupId: String) -> Bool { !budget.collapsedCategoryGroupIds.contains(groupId) }

    public var firstMonthWithData: DateWithoutTime? { months.first(where: \.hasRealData)?.month }

    public func month(_ date: DateWithoutTime) -> BudgetMonth? {
        let offset = date.monthIndex - firstMonthIndex
        return months.indices.contains(offset) ? months[offset] : nil
    }

    init(
        today: DateWithoutTime, months: [BudgetMonth], categoryGroups: [CategoryGroup],
        showsUncategorizedRow: Bool, budget: Budget
    ) {
        self.today = today
        self.months = months
        self.categoryGroups = categoryGroups
        self.showsUncategorizedRow = showsUncategorizedRow
        self.budget = budget
        firstMonthIndex = months[0].month.monthIndex
    }
}

struct BudgetActivity {
    enum Bucket: Hashable {
        case category(String)
        case income
    }

    struct Entry {
        var bucket: Bucket
        var amount: Decimal
        var line: Subtransaction?
    }

    let onBudgetAccounts: Set<String>
    let outflowCategories: Set<String>
    let readyToAssign: String
    let transferAccounts: [String: String]

    init(_ budget: Budget) {
        onBudgetAccounts = Set(budget.accounts.filter(\.onBudget).map(\.id))
        outflowCategories = Set(budget.budgetCategoryGroups.flatMap(\.categories).map(\.id))
        readyToAssign = budget.readyToAssignCategoryId
        transferAccounts = Dictionary(
            budget.payees.compactMap { payee in payee.transferAccountId.map { (payee.id, $0) } }
        ) { first, _ in first }
    }

    func entries(of transaction: Transaction) -> [Entry] {
        guard onBudgetAccounts.contains(transaction.accountId) else { return [] }
        if transaction.isSplit {
            return transaction.subtransactions.compactMap { line in
                bucket(line.categoryId, amount: line.amount, target: line.payeeId.flatMap { transferAccounts[$0] }).map
                {
                    Entry(bucket: $0, amount: line.amount, line: line)
                }
            }
        }
        let target = transaction.payeeId.flatMap { transferAccounts[$0] }
        return bucket(transaction.categoryId, amount: transaction.amount, target: target).map {
            [Entry(bucket: $0, amount: transaction.amount)]
        } ?? []
    }

    private func bucket(_ categoryId: String?, amount: Decimal, target: String?) -> Bucket? {
        switch categoryId {
        case readyToAssign?: return .income
        case let id? where outflowCategories.contains(id): return .category(id)
        default:
            guard !EntityID.isCategorized(categoryId), amount != 0 else { return nil }
            if let target, onBudgetAccounts.contains(target) { return nil }
            return .category(EntityID.uncategorizedCategory)
        }
    }
}

extension DateWithoutTime {
    var monthIndex: Int { year * 12 + month - 1 }

    init(monthIndex: Int) {
        self.init(year: 0, month: monthIndex + 1, day: 1)
    }
}

extension Budget {
    func monthIndexRange(today: DateWithoutTime, including extra: [DateWithoutTime]) -> ClosedRange<Int> {
        let current = today.monthIndex
        var lower = current - 13
        var upper = current + 13
        for transaction in transactions {
            lower = min(lower, transaction.date.monthIndex - 1)
            upper = max(upper, transaction.date.monthIndex + 1)
        }
        for month in assignments.map(\.month) + targetVersions.map(\.fromMonth) + targetSnoozes.map(\.month) + extra {
            lower = min(lower, month.monthIndex)
            upper = max(upper, month.monthIndex)
        }
        return lower...upper
    }

    public func budgetSheet(today: DateWithoutTime, including extra: [DateWithoutTime] = []) -> BudgetSheet {
        var builder = SheetBuilder(budget: self, today: today, range: monthIndexRange(today: today, including: extra))
        return builder.build()
    }

    /// The register drop-down shows today's month whatever the transaction's date.
    public func categoryBalances(today: DateWithoutTime) -> [String: Decimal] {
        SheetBuilder.balances(of: self, through: today.monthIndex)
    }
}

private struct SheetBuilder {
    struct CategoryRow {
        let id: String
        let row: String
    }

    /// An overspent category starts the next month at zero: that month's Zu verteilen pays the difference.
    struct Carry {
        var balances: [String: Decimal] = [:]

        mutating func step(_ category: CategoryRow, assigned: Decimal, spent: Decimal) -> Decimal {
            let balance = Amount.round(max(balances[category.id] ?? 0, 0) + assigned - spent)
            balances[category.id] = balance
            return balance
        }
    }

    let budget: Budget
    let today: DateWithoutTime
    let first: Int
    let count: Int
    let masters: [CategoryGroup]
    let categories: [CategoryRow]
    var spent: [[String: Decimal]]
    var categoryCounts: [[String: Int]]
    var rowCounts: [[String: Int]]
    var monthCounts: [Int]
    var income: [Decimal]
    var lastActivity: Int?
    var showsUncategorizedRow = false

    init(budget: Budget, today: DateWithoutTime, range: ClosedRange<Int>) {
        self.budget = budget
        self.today = today
        first = range.lowerBound
        count = range.count
        masters = budget.budgetCategoryGroups
        categories = Self.categories(of: budget)
        spent = Array(repeating: [:], count: count)
        categoryCounts = Array(repeating: [:], count: count)
        rowCounts = Array(repeating: [:], count: count)
        monthCounts = Array(repeating: 0, count: count)
        income = Array(repeating: 0, count: count)
    }

    mutating func build() -> BudgetSheet {
        bucketTransactions()
        let stored = MonthData(budget)
        let targets = Targets(budget, stored: stored)
        let current = today.monthIndex
        var carry = Carry()
        var months: [BudgetMonth] = []
        months.reserveCapacity(count)
        for offset in 0..<count {
            let index = first + offset
            var figures: [String: BudgetCategoryFigures] = [:]
            figures.reserveCapacity(categories.count)
            var rows: [String: (assigned: Decimal, spent: Decimal, balance: Decimal)] = [:]
            var totalAssigned: Decimal = 0
            var totalSpent: Decimal = 0
            var totalBalance: Decimal = 0
            var overspent: Decimal = 0
            for category in categories {
                let assigned = stored.assigned(index, category.id)
                let spentHere = spent[offset][category.id] ?? 0
                let carried = max(carry.balances[category.id] ?? 0, 0)
                let balance = carry.step(category, assigned: assigned, spent: spentHere)
                figures[category.id] = BudgetCategoryFigures(
                    assigned: assigned, spent: spentHere, balance: balance,
                    transactionCount: categoryCounts[offset][category.id] ?? 0,
                    target: targets.figures(
                        category.id,
                        row: TargetCalculation.Row(
                            month: index, carried: carried, assigned: assigned,
                            isSnoozed: stored.isSnoozed(index, category.id))))
                var row = rows[category.row] ?? (0, 0, 0)
                row.assigned = Amount.round(row.assigned + assigned)
                row.spent = Amount.round(row.spent + spentHere)
                row.balance = Amount.round(row.balance + balance)
                rows[category.row] = row
                totalAssigned = Amount.round(totalAssigned + assigned)
                totalSpent = Amount.round(totalSpent + spentHere)
                totalBalance = Amount.round(totalBalance + balance)
                if balance < 0 { overspent = Amount.round(overspent + balance) }
            }
            func row(_ id: String) -> BudgetMasterFigures {
                let sums = rows[id] ?? (0, 0, 0)
                return BudgetMasterFigures(
                    assigned: sums.assigned, spent: sums.spent, balance: sums.balance,
                    transactionCount: rowCounts[offset][id] ?? 0)
            }
            let previousAvailable = months.last?.readyToAssign ?? 0
            let previousOverspent = months.last?.overspent ?? 0
            let timing: BudgetMonthTiming = index < current ? .past : index == current ? .current : .future
            months.append(
                BudgetMonth(
                    month: DateWithoutTime(monthIndex: index), timing: timing,
                    previousMonthAvailable: previousAvailable, previousMonthOverspent: previousOverspent,
                    income: income[offset], assigned: totalAssigned, spent: totalSpent, balance: totalBalance,
                    overspent: overspent,
                    readyToAssign: Amount.round(previousAvailable + previousOverspent + income[offset] - totalAssigned),
                    transactionCount: monthCounts[offset], uncategorized: row(EntityID.uncategorizedMasterCategory),
                    masters: Dictionary(uniqueKeysWithValues: masters.map { ($0.id, row($0.id)) }),
                    categories: figures))
        }
        let lastAssigned = stored.assigned.keys.max()
        let lastData = [lastActivity, lastAssigned.map { $0 - first }].compactMap(\.self).max()
        Self.lookAhead(&months, lastData: lastData)
        return BudgetSheet(
            today: today, months: months, categoryGroups: masters,
            showsUncategorizedRow: showsUncategorizedRow, budget: budget)
    }

    /// Shortfalls count up to the last month with data or a change of Zu verteilen; the months after only repeat it.
    static func lookAhead(_ months: inout [BudgetMonth], lastData: Int?) {
        let lastChange = months.indices.last {
            months[$0].readyToAssign != ($0 > 0 ? months[$0 - 1].readyToAssign : 0)
        }
        let horizon = max(lastChange ?? 0, lastData ?? 0)
        var assignedLater: Decimal = 0
        var uncovered: [BudgetShortfall] = []
        for offset in months.indices.reversed() {
            months[offset].assignedInFuture = assignedLater
            months[offset].uncovered = uncovered
            let readyToAssign = months[offset].readyToAssign
            if readyToAssign < 0 && offset <= horizon {
                uncovered.insert(BudgetShortfall(month: months[offset].month, amount: -readyToAssign), at: 0)
            }
            assignedLater = Amount.round(assignedLater + months[offset].assigned)
        }
    }

    struct MonthData {
        let assigned: [Int: [String: Decimal]]
        let snoozed: [Int: Set<String>]

        init(_ budget: Budget, through last: Int = .max) {
            var assigned: [Int: [String: Decimal]] = [:]
            for assignment in budget.assignments where assignment.month.monthIndex <= last {
                assigned[assignment.month.monthIndex, default: [:]][assignment.categoryId, default: 0] +=
                    assignment.amount
            }
            self.assigned = assigned
            var snoozed: [Int: Set<String>] = [:]
            for snooze in budget.targetSnoozes {
                snoozed[snooze.month.monthIndex, default: []].insert(snooze.categoryId)
            }
            self.snoozed = snoozed
        }

        func assigned(_ month: Int, _ categoryId: String) -> Decimal {
            assigned[month]?[categoryId] ?? 0
        }

        func isSnoozed(_ month: Int, _ categoryId: String) -> Bool {
            snoozed[month]?.contains(categoryId) ?? false
        }
    }

    struct Targets {
        let stored: MonthData
        let versions: [String: [TargetCalculation.Version]]

        init(_ budget: Budget, stored: MonthData) {
            self.stored = stored
            var versions: [String: [TargetCalculation.Version]] = [:]
            for version in budget.targetVersions {
                versions[version.categoryId, default: []].append(
                    TargetCalculation.Version(month: version.fromMonth.monthIndex, target: version.target))
            }
            self.versions = versions
        }

        func figures(_ categoryId: String, row: TargetCalculation.Row) -> BudgetTargetFigures? {
            guard let versions = versions[categoryId],
                let (target, cycleStart) = TargetCalculation.inEffect(versions, at: row.month)
            else { return nil }
            return TargetCalculation.figures(target, cycleStart: cycleStart, row: row) {
                stored.assigned($0, categoryId)
            }
        }
    }

    static func categories(of budget: Budget) -> [CategoryRow] {
        var categories: [CategoryRow] = []
        for master in budget.budgetCategoryGroups {
            for sub in master.categories {
                categories.append(CategoryRow(id: sub.id, row: master.id))
            }
        }
        categories.append(CategoryRow(id: EntityID.uncategorizedCategory, row: EntityID.uncategorizedMasterCategory))
        return categories
    }

    /// The sheet's balances in month `last`; a month without data only carries them on, so one stands for any gap.
    static func balances(of budget: Budget, through last: Int) -> [String: Decimal] {
        let categories = categories(of: budget)
        let activity = BudgetActivity(budget)
        var spent: [Int: [String: Decimal]] = [:]
        for transaction in budget.transactions where transaction.date.monthIndex <= last {
            let index = transaction.date.monthIndex
            for entry in activity.entries(of: transaction) {
                guard case .category(let id) = entry.bucket else { continue }
                spent[index, default: [:]][id] = Amount.round((spent[index]?[id] ?? 0) - entry.amount)
            }
        }
        let stored = MonthData(budget, through: last)
        var carry = Carry()
        var previous: Int?
        for index in Set(spent.keys).union(stored.assigned.keys).union([last]).sorted() {
            if let previous, index > previous + 1 {
                for category in categories { _ = carry.step(category, assigned: 0, spent: 0) }
            }
            for category in categories {
                _ = carry.step(
                    category, assigned: stored.assigned(index, category.id),
                    spent: spent[index]?[category.id] ?? 0)
            }
            previous = index
        }
        return carry.balances
    }

    private mutating func bucketTransactions() {
        let activity = BudgetActivity(budget)
        let rowOf = Dictionary(categories.map { ($0.id, $0.row) }) { first, _ in first }
        for transaction in budget.transactions {
            let entries = activity.entries(of: transaction)
            guard !entries.isEmpty else { continue }
            let offset = transaction.date.monthIndex - first
            lastActivity = max(lastActivity ?? offset, offset)
            var observed: Set<String> = []
            for entry in entries {
                switch entry.bucket {
                case .income:
                    income[offset] = Amount.round(income[offset] + entry.amount)
                case .category(let id):
                    spent[offset][id] = Amount.round((spent[offset][id] ?? 0) - entry.amount)
                    observed.insert(id)
                }
            }
            guard !observed.isEmpty else { continue }
            for id in observed { categoryCounts[offset][id, default: 0] += 1 }
            for row in Set(observed.compactMap { rowOf[$0] }) { rowCounts[offset][row, default: 0] += 1 }
            monthCounts[offset] += 1
            if observed.contains(EntityID.uncategorizedCategory) { showsUncategorizedRow = true }
        }
    }
}
