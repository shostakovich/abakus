import Foundation

public struct DeleteAnalysis: Hashable, Sendable {
    public var deletable: [String] = []
    public var transfersIntoSplits = 0
    public var reconciled = 0
    public var otherSideReconciled = 0
    public var transfers = 0
    public var led = 0
    public var leaders: Set<TransactionLeader> = []

    public init() {}
}

public struct RegisterNotifierCounts: Hashable, Sendable {
    public var errors = 0
    public var needsCategory = 0
    public var forReview = 0

    public init() {}
}

/// A moved transaction's or schedule's account and cleared status before the move, for the register's undo.
public struct MovedTransaction: Hashable, Sendable {
    public var transactionId: String
    public var accountId: String
    public var cleared: ClearedStatus

    public init(transactionId: String, accountId: String, cleared: ClearedStatus) {
        self.transactionId = transactionId
        self.accountId = accountId
        self.cleared = cleared
    }
}

extension Budget {
    public func deleteAnalysis(_ ids: [String]) -> DeleteAnalysis {
        var analysis = DeleteAnalysis()
        let led = ledTransactions
        for id in ids {
            guard let transaction = transaction(withId: id) else { continue }
            if isTransferFromSplit(transaction) {
                analysis.transfersIntoSplits += 1
                continue
            }
            if let leader = removedWithIt(transaction).lazy.compactMap({ led[$0]?.leader }).first {
                analysis.led += 1
                analysis.leaders.insert(leader)
                continue
            }
            analysis.deletable.append(id)
            if transaction.cleared == .reconciled { analysis.reconciled += 1 }
            if let counterpart = transaction.transferTransactionId.flatMap(self.transaction(withId:)),
                counterpart.cleared == .reconciled
            {
                analysis.otherSideReconciled += 1
            }
            if transaction.transferTransactionId != nil || transaction.subtransactions.contains(where: isTransfer) {
                analysis.transfers += 1
            }
        }
        return analysis
    }

    public func moveTargets(excluding accountId: String?) -> [Account] {
        accounts.filter { !$0.closed && $0.id != accountId }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func notifierCounts(forAccount key: String) -> RegisterNotifierCounts {
        notifierCounts(of: transactions.lazy.filter { key == EntityID.allAccounts || $0.accountId == key })
    }

    private func notifierCounts(of listed: some Sequence<Transaction>) -> RegisterNotifierCounts {
        var counts = RegisterNotifierCounts()
        let lookup = BudgetLookup(self)
        for transaction in listed {
            switch lookup.errorState(of: transaction).level {
            case .error: counts.errors += 1
            case .needsCategory: counts.needsCategory += 1
            case .forReview: counts.forReview += 1
            case .none: break
            }
        }
        return counts
    }

    mutating func approveTransactions(_ ids: [String]) {
        for index in ids.compactMap(transactionIndex) { approve(at: index) }
    }

    /// Approving a transfer also approves its counterpart.
    mutating func approve(at index: Int) {
        transactions[index].approved = true
        guard let counterpartId = transactions[index].transferTransactionId, let other = transactionIndex(counterpartId)
        else { return }
        transactions[other].approved = true
    }

    /// All cleared become uncleared, else all become cleared and approved.
    mutating func toggleCleared(_ ids: [String]) {
        let indices = ids.compactMap(transactionIndex).filter { transactions[$0].cleared != .reconciled }
        guard !indices.isEmpty else { return }
        let allCleared = indices.allSatisfy { transactions[$0].cleared == .cleared }
        for index in indices {
            if allCleared {
                transactions[index].cleared = .uncleared
            } else {
                transactions[index].cleared = .cleared
                approve(at: index)
            }
        }
    }

    mutating func categorizeTransactions(_ ids: [String], categoryId: String?) {
        for id in ids {
            guard let index = transactionIndex(id), !transactions[index].isSplit else { continue }
            transactions[index].categoryId = categoryId
        }
    }

    mutating func fillMissingCategory(_ ids: [String], categoryId: String) {
        setCategory(ids, atLevel: .needsCategory, to: categoryId)
    }

    mutating func removeTransferCategories(_ ids: [String]) {
        setCategory(ids, atLevel: .error, to: nil)
    }

    private mutating func setCategory(_ ids: [String], atLevel level: ErrorLevel, to categoryId: String?) {
        for index in ids.compactMap(transactionIndex) {
            let transaction = transactions[index]
            if transaction.isSplit {
                for subIndex in transaction.subtransactions.indices
                where errorState(of: transaction.subtransactions[subIndex], inAccount: transaction.accountId).level
                    == level
                {
                    transactions[index].subtransactions[subIndex].categoryId = categoryId
                }
            } else if errorState(of: transaction).level == level {
                transactions[index].categoryId = categoryId
            }
        }
    }

    mutating func moveTransactions(_ ids: [String], to accountId: String) throws {
        guard let target = account(withId: accountId) else { throw BudgetError.accountNotFound(accountId) }
        let led = ledTransactionIds
        for id in ids where !led.contains(id) {
            guard let index = transactionIndex(id) else { continue }
            let previous = transactions[index]
            if previous.transfers(into: accountId) { throw BudgetError.transferIntoMoveTarget(target.name) }
            transactions[index].accountId = accountId
            if previous.cleared == .reconciled { transactions[index].cleared = .cleared }
            if let subId = previous.transferSubtransactionId, let parentIndex = splitParentIndex(ofSub: subId),
                let subIndex = transactions[parentIndex].subtransactions.firstIndex(where: { $0.id == subId })
            {
                transactions[parentIndex].subtransactions[subIndex].transfer(to: accountId)
            } else {
                syncTransfers(of: id, previous: previous)
            }
        }
    }

    /// Only the account and the cleared status go back.
    mutating func restoreMovedTransactions(_ moved: [MovedTransaction]) throws {
        for entry in moved {
            if let index = scheduledIndex(entry.transactionId) {
                scheduledTransactions[index].accountId = entry.accountId
                continue
            }
            guard let current = transaction(withId: entry.transactionId) else { continue }
            if current.accountId != entry.accountId { try moveTransactions([entry.transactionId], to: entry.accountId) }
            if let index = transactionIndex(entry.transactionId) { transactions[index].cleared = entry.cleared }
        }
    }

    mutating func restoreTransactions(_ restored: [Transaction], payees restoredPayees: [Payee]) {
        for payee in restoredPayees where !payees.contains(where: { $0.id == payee.id }) {
            payees.append(payee)
        }
        for transaction in restored {
            if let index = transactionIndex(transaction.id) {
                transactions[index] = transaction
            } else {
                transactions.append(transaction)
            }
        }
    }

    /// A monthly copy starts with the first monthly step after today, a once copy keeps the date.
    mutating func scheduleCopy(of transactionId: String, scheduleId: String, monthlyAfter today: DateWithoutTime?)
        throws
    {
        guard let transaction = transaction(withId: transactionId) else {
            throw BudgetError.transactionNotFound(transactionId)
        }
        let recurring = today != nil
        if !recurring, let leader = leader(of: transactionId) { throw BudgetError.ledTransaction(leader) }
        var source = transaction
        source.id = scheduleId
        if let today {
            while source.date <= today { source.date = source.date.addingMonths(1) }
        }
        source.subtransactions = transaction.subtransactions.map { $0.copy(into: scheduleId) }
        scheduledTransactions.append(ScheduledTransaction(source, frequency: recurring ? .monthly : .once))
        if !recurring { deleteTransactions([transactionId]) }
    }
}
