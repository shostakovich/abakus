import Foundation

public protocol SplittableTransaction {
    var payeeId: String? { get set }
    var categoryId: String? { get set }
    var amount: Decimal { get }
    var subtransactions: [Subtransaction] { get set }
}

extension SplittableTransaction {
    public var inflow: Decimal { amount > 0 ? amount : 0 }
    public var outflow: Decimal { amount < 0 ? -amount : 0 }
    public var isSplit: Bool { !subtransactions.isEmpty }

    func uses(payee payeeId: String) -> Bool {
        self.payeeId == payeeId || subtransactions.contains { $0.payeeId == payeeId }
    }

    var payeeIds: [String] {
        [payeeId].compactMap(\.self) + subtransactions.compactMap(\.payeeId)
    }

    mutating func replacePayee(_ oldId: String, with newId: String) {
        if payeeId == oldId { payeeId = newId }
        for index in subtransactions.indices where subtransactions[index].payeeId == oldId {
            subtransactions[index].payeeId = newId
        }
    }

    public mutating func transfer(to accountId: String) {
        payeeId = EntityID.transferPayee(accountId: accountId)
    }

    public func transfers(into accountId: String) -> Bool {
        let payee = EntityID.transferPayee(accountId: accountId)
        return payeeId == payee || subtransactions.contains { $0.payeeId == payee }
    }
}

/// Also the parts of a scheduled transaction, which are never linked as transfers.
public struct Subtransaction: Hashable, Identifiable, Sendable {
    public var id: String
    public var transactionId: String
    public var amount: Decimal { didSet { amount = Amount.round(amount) } }
    public var payeeId: String?
    public var categoryId: String?
    public var memo: String?
    public var transferTransactionId: String?

    public var inflow: Decimal { amount > 0 ? amount : 0 }
    public var outflow: Decimal { amount < 0 ? -amount : 0 }

    public init(
        id: String = EntityID.createUID(),
        transactionId: String,
        amount: Decimal,
        payeeId: String? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        transferTransactionId: String? = nil
    ) {
        self.id = id
        self.transactionId = transactionId
        self.amount = Amount.round(amount)
        self.payeeId = payeeId
        self.categoryId = categoryId
        self.memo = memo
        self.transferTransactionId = transferTransactionId
    }

    public mutating func transfer(to accountId: String) {
        payeeId = EntityID.transferPayee(accountId: accountId)
    }

    /// The part cloned into another parent: a new id and no transfer link.
    func copy(into parentId: String, id: String = EntityID.createUID()) -> Subtransaction {
        Subtransaction(
            id: id, transactionId: parentId, amount: amount, payeeId: payeeId, categoryId: categoryId, memo: memo)
    }
}

public enum TransactionSource: String, Codable, CaseIterable, Sendable {
    case manual
    case ynab
    case file
    case bank
    case api
    case kasse
    case depot
    case scheduled
}

/// The area on the server that writes a linked transaction and leads it.
public enum TransactionLeader: String, CaseIterable, Sendable {
    case kasse
    case depot
}

/// A split has subtransactions instead of a category.
public struct Transaction: Hashable, Identifiable, Sendable, SplittableTransaction {
    public var id: String
    public var accountId: String
    public var date: DateWithoutTime
    public var payeeId: String?
    public var categoryId: String?
    public var memo: String?
    public var amount: Decimal { didSet { amount = Amount.round(amount) } }
    public var cleared: ClearedStatus {
        didSet { if cleared == .reconciled { approved = true } }
    }
    public var approved: Bool
    public var source: TransactionSource
    /// Only the server writes it.
    public var ledBy: TransactionLeader?
    public var transferTransactionId: String?
    /// Set on the counterpart of a split's transfer part.
    public var transferSubtransactionId: String?
    /// Set on a match proposal, which the budget keeps apart.
    public var matchedTransactionId: String?
    public var scheduledTransactionId: String?
    public var scheduledDate: DateWithoutTime?
    public var subtransactions: [Subtransaction]

    public init(
        id: String = EntityID.createUID(),
        accountId: String,
        date: DateWithoutTime,
        payeeId: String? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        amount: Decimal,
        cleared: ClearedStatus = .uncleared,
        approved: Bool = true,
        source: TransactionSource = .manual,
        ledBy: TransactionLeader? = nil,
        transferTransactionId: String? = nil,
        transferSubtransactionId: String? = nil,
        matchedTransactionId: String? = nil,
        scheduledTransactionId: String? = nil,
        scheduledDate: DateWithoutTime? = nil,
        subtransactions: [Subtransaction] = []
    ) {
        self.id = id
        self.accountId = accountId
        self.date = date
        self.payeeId = payeeId
        self.categoryId = categoryId
        self.memo = memo
        self.amount = Amount.round(amount)
        self.cleared = cleared
        self.approved = approved || cleared == .reconciled
        self.source = source
        self.ledBy = ledBy
        self.transferTransactionId = transferTransactionId
        self.transferSubtransactionId = transferSubtransactionId
        self.matchedTransactionId = matchedTransactionId
        self.scheduledTransactionId = scheduledTransactionId
        self.scheduledDate = scheduledDate
        self.subtransactions = subtransactions
    }

    /// The occurrence on the schedule's next date, with the ids the protocol names after it.
    init(occurrenceOf scheduled: ScheduledTransaction, approved: Bool) {
        let id = EntityID.enteredTransaction(scheduledId: scheduled.id, date: scheduled.nextDate)
        self.init(
            id: id, accountId: scheduled.accountId, date: scheduled.nextDate, payeeId: scheduled.payeeId,
            categoryId: scheduled.categoryId, memo: scheduled.memo, amount: scheduled.amount,
            cleared: scheduled.cleared, approved: approved, source: .scheduled,
            scheduledTransactionId: scheduled.id, scheduledDate: scheduled.nextDate,
            subtransactions: scheduled.subtransactions.enumerated().map { position, part in
                part.copy(into: id, id: EntityID.enteredSubtransaction(transactionId: id, position: position))
            })
    }

    /// The counterpart of a split's transfer part changes there.
    public var isTransferFromSplit: Bool { transferSubtransactionId != nil }

    /// What this edit changed from `original`, written onto `current`; a category and its parts go together.
    public func rebased(from original: Transaction, onto current: Transaction, partsChanged: Bool = false)
        -> Transaction
    {
        var result = current
        if accountId != original.accountId { result.accountId = accountId }
        if date != original.date { result.date = date }
        if payeeId != original.payeeId { result.payeeId = payeeId }
        if (memo ?? "") != (original.memo ?? "") { result.memo = memo }
        if amount != original.amount { result.amount = amount }
        if cleared != original.cleared { result.cleared = cleared }
        if approved != original.approved { result.approved = approved }
        if partsChanged || categoryId != original.categoryId || subtransactions != original.subtransactions {
            result.categoryId = categoryId
            result.subtransactions = subtransactions
        } else if result.isSplit {
            result.categoryId = EntityID.splitCategory
        }
        return result
    }
}
