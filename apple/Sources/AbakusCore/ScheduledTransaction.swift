import Foundation

public struct ScheduledTransaction: Hashable, Identifiable, Sendable, SplittableTransaction {
    public var id: String
    public var accountId: String
    public var nextDate: DateWithoutTime
    public var repeats: Repeat
    public var payeeId: String?
    public var categoryId: String?
    public var memo: String?
    public var amount: Decimal { didSet { amount = Amount.round(amount) } }
    public var cleared: ClearedStatus
    public var subtransactions: [Subtransaction]

    public init(
        id: String = EntityID.createUID(),
        accountId: String,
        nextDate: DateWithoutTime,
        repeats: Repeat = .monthly,
        payeeId: String? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        amount: Decimal,
        cleared: ClearedStatus = .uncleared,
        subtransactions: [Subtransaction] = []
    ) {
        self.id = id
        self.accountId = accountId
        self.nextDate = nextDate
        self.repeats = repeats
        self.payeeId = payeeId
        self.categoryId = categoryId
        self.memo = memo
        self.amount = Amount.round(amount)
        self.cleared = cleared == .reconciled ? .cleared : cleared
        self.subtransactions = subtransactions
    }

    /// A transaction as a schedule: uncleared and its parts never linked as transfers.
    init(_ transaction: Transaction, repeats: Repeat) {
        self.init(
            id: transaction.id, accountId: transaction.accountId, nextDate: transaction.date, repeats: repeats,
            payeeId: transaction.payeeId, categoryId: transaction.isSplit ? nil : transaction.categoryId,
            memo: transaction.memo, amount: transaction.amount,
            subtransactions: transaction.subtransactions.map { part in
                var line = part
                line.transactionId = transaction.id
                line.transferTransactionId = nil
                return line
            })
    }

    /// Once stays on its date.
    public var followingDate: DateWithoutTime {
        repeats.following(nextDate) ?? nextDate
    }
}
