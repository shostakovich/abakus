import Foundation

extension TransactionLeader {
    public var byName: String {
        switch self {
        case .kasse: "von der Kasse"
        case .depot: "vom Depot"
        }
    }

    public var inName: String {
        switch self {
        case .kasse: "in der Kasse"
        case .depot: "im Depot"
        }
    }

    public var leadsNote: String { "Wird \(byName) geführt." }

    public static func byNames(_ leaders: Set<TransactionLeader>) -> String {
        allCases.filter(leaders.contains).map(\.byName).joined(separator: " und ")
    }
}

extension Budget {
    /// Its own `ledBy` or its transfer counterpart's (ADR 0020).
    public func leader(of transactionId: String) -> TransactionLeader? {
        guard let transaction = transaction(withId: transactionId) else { return nil }
        return transaction.ledBy ?? transaction.transferTransactionId.flatMap { self.transaction(withId: $0)?.ledBy }
    }

    public func isLed(_ transactionId: String) -> Bool {
        leader(of: transactionId) != nil
    }

    public var ledTransactionIds: Set<String> {
        Set(ledTransactions.keys)
    }

    /// A second pass only when something is led, as every command checks them.
    var ledTransactions: [String: (transaction: Transaction, leader: TransactionLeader)] {
        var leaders: [String: TransactionLeader] = [:]
        for transaction in transactions {
            if let leader = transaction.ledBy { leaders[transaction.id] = leader }
        }
        guard !leaders.isEmpty else { return [:] }
        var led: [String: (transaction: Transaction, leader: TransactionLeader)] = [:]
        for transaction in transactions {
            guard let leader = transaction.ledBy ?? transaction.transferTransactionId.flatMap({ leaders[$0] })
            else { continue }
            led[transaction.id] = (transaction, leader)
        }
        return led
    }

    func leaderOfChangedLedTransaction(since before: Budget) -> TransactionLeader? {
        var unseen = before.ledTransactions
        guard !unseen.isEmpty else { return nil }
        let resolve = SuccessorChain(successorIds)
        for transaction in transactions where transaction.ledBy != nil || transaction.transferTransactionId != nil {
            guard let old = unseen.removeValue(forKey: transaction.id) else { continue }
            if LedFields(old.transaction, resolve) != LedFields(transaction, resolve) { return old.leader }
        }
        return unseen.first?.value.leader
    }
}

/// Payees and categories count for their successors, so merging payees and deleting categories go through.
private struct LedFields: Equatable {
    var accountId: String
    var date: DateWithoutTime
    var amount: Decimal
    var payeeId: String?
    var transferTransactionId: String?
    var transferSubtransactionId: String?
    var ledBy: TransactionLeader?
    var parts: [Subtransaction]

    init(_ transaction: Transaction, _ resolve: SuccessorChain) {
        accountId = transaction.accountId
        date = transaction.date
        amount = transaction.amount
        payeeId = resolve(transaction.payeeId)
        transferTransactionId = transaction.transferTransactionId
        transferSubtransactionId = transaction.transferSubtransactionId
        ledBy = transaction.ledBy
        parts = transaction.subtransactions.map { part in
            var resolved = part
            resolved.payeeId = resolve(part.payeeId)
            resolved.categoryId = resolve(part.categoryId)
            return resolved
        }
    }
}
