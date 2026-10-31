import Foundation

public struct AccountBalances: Hashable, Sendable {
    public var cleared: Decimal
    public var uncleared: Decimal
    public var reconciled: Decimal

    public var working: Decimal { Amount.round(cleared + uncleared) }

    public init(cleared: Decimal = 0, uncleared: Decimal = 0, reconciled: Decimal = 0) {
        self.cleared = cleared
        self.uncleared = uncleared
        self.reconciled = reconciled
    }

    public static func of<S: Sequence>(_ transactions: S, through date: DateWithoutTime? = nil) -> AccountBalances
    where S.Element == Transaction {
        var balances = AccountBalances()
        for transaction in transactions where date.map({ transaction.date <= $0 }) ?? true {
            switch transaction.cleared {
            case .reconciled:
                balances.reconciled = Amount.round(balances.reconciled + transaction.amount)
                balances.cleared = Amount.round(balances.cleared + transaction.amount)
            case .cleared:
                balances.cleared = Amount.round(balances.cleared + transaction.amount)
            case .uncleared:
                balances.uncleared = Amount.round(balances.uncleared + transaction.amount)
            }
        }
        return balances
    }
}

public enum SidebarGroup: String, CaseIterable, Sendable {
    case budgetAccounts
    case offBudgetAccounts
    case closedAccounts

    public var title: String {
        switch self {
        case .budgetAccounts: "Budgetkonten"
        case .offBudgetAccounts: "Trackingkonten"
        case .closedAccounts: "Geschlossene Konten"
        }
    }

    public func contains(_ account: Account) -> Bool {
        switch self {
        case .budgetAccounts: !account.closed && account.onBudget
        case .offBudgetAccounts: !account.closed && !account.onBudget
        case .closedAccounts: account.closed
        }
    }
}

public struct AccountErrorSummary: Hashable, Sendable {
    public var count: Int
    public var maxLevel: ErrorLevel

    public init(count: Int = 0, maxLevel: ErrorLevel = .none) {
        self.count = count
        self.maxLevel = maxLevel
    }

    mutating func merge(_ other: AccountErrorSummary) {
        count += other.count
        if other.maxLevel.accountPriority > maxLevel.accountPriority { maxLevel = other.maxLevel }
    }
}

extension Budget {
    public func balances(forAccount accountId: String, through date: DateWithoutTime? = nil) -> AccountBalances {
        if accountId == EntityID.allAccounts { return allAccountsBalances(through: date) }
        return .of(transactions.lazy.filter { $0.accountId == accountId }, through: date)
    }

    public func allAccountsBalances(through date: DateWithoutTime? = nil) -> AccountBalances {
        .of(transactions, through: date)
    }

    public func workingBalances() -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for account in accounts { result[account.id] = 0 }
        for transaction in transactions {
            result[transaction.accountId] = Amount.round((result[transaction.accountId] ?? 0) + transaction.amount)
        }
        return result
    }

    public func accounts(in group: SidebarGroup) -> [Account] {
        sortedAccounts.filter(group.contains)
    }

    public func errorSummary(forAccount accountId: String) -> AccountErrorSummary {
        var summary = AccountErrorSummary()
        let lookup = BudgetLookup(self)
        for transaction in transactions where transaction.accountId == accountId {
            let level = lookup.errorState(of: transaction).level
            if level != .none { summary.merge(AccountErrorSummary(count: 1, maxLevel: level)) }
        }
        return summary
    }

    public func errorSummary(for group: SidebarGroup) -> AccountErrorSummary {
        accounts(in: group).map { errorSummary(forAccount: $0.id) }.reduce(into: AccountErrorSummary()) {
            $0.merge($1)
        }
    }
}
