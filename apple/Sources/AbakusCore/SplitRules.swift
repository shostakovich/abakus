import Foundation

public enum SplitRules {
    /// `payeeNames` holds the payees typed into lines but not resolved yet, by line id.
    private static func isEmpty(_ sub: Subtransaction, payeeNames: [String: String]) -> Bool {
        !hasPayee(sub, payeeNames: payeeNames) && sub.categoryId == nil && sub.amount == 0 && (sub.memo ?? "").isEmpty
    }

    private static func hasPayee(_ sub: Subtransaction, payeeNames: [String: String]) -> Bool {
        sub.payeeId != nil || !(payeeNames[sub.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Drops empty sub-rows; none left makes an uncategorized transaction, one left collapses when nothing clashes.
    /// A stored split has no category of its own.
    public static func normalized(
        _ input: Transaction, parentPayeeName: String, subPayeeNames: [String: String] = [:], in budget: Budget
    ) -> Transaction {
        var transaction = input
        guard transaction.categoryId == EntityID.splitCategory || transaction.isSplit else { return transaction }
        let kept = transaction.subtransactions.filter { !isEmpty($0, payeeNames: subPayeeNames) }
        transaction.subtransactions = kept
        transaction.categoryId = nil
        guard kept.count == 1, let sub = kept.first else { return transaction }
        let isTransfer = budget.isTransfer(sub)
        let ownPayee = !isTransfer && hasPayee(sub, payeeNames: subPayeeNames)
        let payeeClash = ownPayee || !parentPayeeName.trimmingCharacters(in: .whitespaces).isEmpty && isTransfer
        let memoClash = !(transaction.memo ?? "").isEmpty && !(sub.memo ?? "").isEmpty
        let amountClash = sub.amount != 0 && transaction.amount != 0
        guard !payeeClash && !memoClash && !amountClash else { return transaction }
        transaction.subtransactions = []
        transaction.categoryId = sub.categoryId
        if isTransfer { transaction.payeeId = sub.payeeId }
        if let memo = sub.memo, !memo.isEmpty { transaction.memo = memo }
        if transaction.amount == 0 { transaction.amount = sub.amount }
        return transaction
    }

    public static func unassigned(_ transaction: Transaction) -> Decimal {
        Amount.round(transaction.amount - Amount.sum(transaction.subtransactions.map(\.amount)))
    }

    /// Proportional shares, the rounding rest to the largest line.
    public static func autoDistribute(_ transaction: Transaction) -> Transaction {
        var result = transaction
        let remaining = unassigned(transaction)
        guard remaining != 0, !result.subtransactions.isEmpty else { return result }
        let total = Amount.sum(result.subtransactions.map(\.amount))
        let count = Decimal(result.subtransactions.count)
        for index in result.subtransactions.indices {
            let share =
                total == 0 ? remaining / count : remaining * result.subtransactions[index].amount / total
            result.subtransactions[index].amount = Amount.round(result.subtransactions[index].amount + share)
        }
        let rest = unassigned(result)
        if rest != 0,
            let largest = result.subtransactions.indices.max(by: {
                abs(result.subtransactions[$0].amount) < abs(result.subtransactions[$1].amount)
            })
        {
            result.subtransactions[largest].amount = Amount.round(result.subtransactions[largest].amount + rest)
        }
        return result
    }

    public static func adjustOriginal(_ transaction: Transaction) -> Transaction {
        var result = transaction
        result.amount = Amount.sum(transaction.subtransactions.map(\.amount))
        return result
    }
}
