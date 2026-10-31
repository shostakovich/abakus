import Foundation

public struct AutoFillSettings: Hashable, Sendable {
    public var category: Bool
    public var memo: Bool
    public var amount: Bool

    public init(category: Bool = true, memo: Bool = false, amount: Bool = false) {
        self.category = category
        self.memo = memo
        self.amount = amount
    }
}

public struct PayeeAutoFill: Hashable, Sendable {
    public var categoryId: String?
    public var memo: String?
    public var amount: Decimal?
}

extension Budget {
    public func autoFill(payeeName: String, accountId: String, settings: AutoFillSettings) -> PayeeAutoFill? {
        guard let payee = payee(named: payeeName, includingTransfers: true), isSuggested(payee),
            let account = account(withId: accountId), payee.transferAccountId != accountId
        else { return nil }
        var fill = PayeeAutoFill()
        if settings.category, account.onBudget { fill.categoryId = suggestedCategory(for: payee, in: account) }
        let last = lastTransaction(ofPayee: payee.id)
        if settings.memo, let memo = last?.memo, !memo.isEmpty { fill.memo = memo }
        if settings.amount, let amount = last?.amount, amount != 0 { fill.amount = amount }
        return fill
    }

    func lastTransaction(ofPayee payeeId: String) -> Transaction? {
        transactions.lazy.filter { $0.payeeId == payeeId }.max { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    func lastTransferCategory(budgetAccountId: String, trackingAccountId: String) -> String? {
        let transferPayee = EntityID.transferPayee(accountId: trackingAccountId)
        var latest: (date: DateWithoutTime, categoryId: String)?
        for transaction in transactions where transaction.accountId == budgetAccountId {
            let sides =
                [(transaction.payeeId, transaction.categoryId)]
                + transaction.subtransactions.map { ($0.payeeId, $0.categoryId) }
            for (payeeId, categoryId) in sides where payeeId == transferPayee {
                guard let categoryId, isSuggestable(categoryId), latest.map({ transaction.date >= $0.date }) ?? true
                else { continue }
                latest = (transaction.date, categoryId)
            }
        }
        return latest?.categoryId
    }

    private func suggestedCategory(for payee: Payee, in account: Account) -> String? {
        guard let targetId = payee.transferAccountId else {
            return payee.lastCategoryId.flatMap { isSuggestable($0) ? $0 : nil }
        }
        guard let target = self.account(withId: targetId), !target.onBudget else { return nil }
        return lastTransferCategory(budgetAccountId: account.id, trackingAccountId: targetId)
    }

    private func isSuggestable(_ categoryId: String) -> Bool {
        EntityID.isCategorized(categoryId) && category(withId: categoryId) != nil
    }
}
