import Foundation

public struct DefaultOrderKeys: Hashable, Sendable {
    public var date: DateWithoutTime
    public var amount: Decimal
    public var payee: String
    public var category: String
    public var memo: String
    public var cleared: ClearedStatus
    public var errorLevel: ErrorLevel

    /// Inflows sort before outflows on the same day.
    public func compare(_ other: DefaultOrderKeys) -> ComparisonResult {
        if date != other.date { return date < other.date ? .orderedAscending : .orderedDescending }
        if amount != other.amount { return amount > other.amount ? .orderedAscending : .orderedDescending }
        for (lhs, rhs) in [(payee, other.payee), (category, other.category), (memo, other.memo)] {
            let order = lhs.localizedStandardCompare(rhs)
            if order != .orderedSame { return order }
        }
        if cleared != other.cleared {
            return cleared.integerValue > other.cleared.integerValue ? .orderedAscending : .orderedDescending
        }
        if errorLevel != other.errorLevel {
            return errorLevel > other.errorLevel ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }
}

/// Id lookups built once for work over many transactions; `Budget`'s own lookups scan its arrays.
public struct BudgetLookup: Sendable {
    public let budget: Budget
    private let accounts: [String: Account]
    private let payeeNames: [String: String]
    private let transferAccounts: [String: String]
    private let categoryNames: [String: String]
    private let shortCategoryNames: [String: String]

    public init(_ budget: Budget) {
        self.budget = budget
        accounts = Dictionary(budget.accounts.map { ($0.id, $0) }) { first, _ in first }
        payeeNames = Dictionary(budget.payees.map { ($0.id, budget.payeeName(of: $0)) }) { first, _ in first }
        transferAccounts = Dictionary(
            budget.payees.compactMap { payee in payee.transferAccountId.map { (payee.id, $0) } }
        ) {
            first, _ in first
        }
        let ids = budget.categoryGroups.flatMap(\.categories).map(\.id) + [EntityID.splitCategory]
        categoryNames = Dictionary(ids.map { ($0, budget.categoryDisplayName($0)) }) { first, _ in first }
        shortCategoryNames = Dictionary(ids.map { ($0, budget.categoryName($0)) }) { first, _ in first }
    }

    public func account(withId id: String) -> Account? { accounts[id] }

    public func payeeName(of transaction: Transaction) -> String {
        transaction.payeeId.flatMap { payeeNames[$0] } ?? ""
    }

    public func payeeName(of sub: Subtransaction) -> String {
        sub.payeeId.flatMap { payeeNames[$0] } ?? ""
    }

    public func errorState(of transaction: Transaction) -> ErrorState {
        budget.errorState(of: transaction, transfers: transferAccountId(ofPayee:))
    }

    public func errorState(of sub: Subtransaction, inAccount accountId: String) -> ErrorState {
        budget.errorState(of: sub, inAccount: accountId, transfers: transferAccountId(ofPayee:))
    }

    public func needsCategory(_ transaction: Transaction) -> Bool {
        budget.needsCategory(transaction, transfers: transferAccountId(ofPayee:))
    }

    private func transferAccountId(ofPayee payeeId: String?) -> String? {
        payeeId.flatMap { transferAccounts[$0] }
    }

    public func transferAccountId(of transaction: Transaction) -> String? {
        transaction.isSplit ? nil : transaction.payeeId.flatMap { transferAccounts[$0] }
    }

    public func transferAccountId(of sub: Subtransaction) -> String? {
        sub.payeeId.flatMap { transferAccounts[$0] }
    }

    public func categoryDisplayName(_ categoryId: String?) -> String {
        categoryId.flatMap { categoryNames[$0] } ?? ""
    }

    public func categoryName(_ categoryId: String?) -> String {
        categoryId.flatMap { shortCategoryNames[$0] } ?? ""
    }

    public func categoryDisplayName(of transaction: Transaction) -> String {
        categoryDisplayName(transaction.isSplit ? EntityID.splitCategory : transaction.categoryId)
    }

    public func defaultOrderKeys(of transaction: Transaction) -> DefaultOrderKeys {
        DefaultOrderKeys(
            date: transaction.date, amount: transaction.amount,
            payee: transferAccountId(of: transaction).flatMap { accounts[$0]?.name } ?? payeeName(of: transaction),
            category: categoryDisplayName(of: transaction), memo: transaction.memo ?? "",
            cleared: transaction.cleared, errorLevel: errorState(of: transaction).level)
    }
}
