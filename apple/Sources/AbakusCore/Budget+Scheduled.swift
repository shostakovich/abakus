import Foundation

/// The scheduler editor's Done / Save: the edited clone with the schedule's id and the chosen repeat.
public struct ScheduledSave: Hashable, Sendable {
    public var transaction: Transaction
    public var repeats: Repeat
    public var payeeName: String?
    public var subPayeeNames: [String: String]
    public var isNew: Bool

    public init(
        transaction: Transaction, repeats: Repeat, payeeName: String?,
        subPayeeNames: [String: String] = [:], isNew: Bool
    ) {
        self.transaction = transaction
        self.repeats = repeats
        self.payeeName = payeeName
        self.subPayeeNames = subPayeeNames
        self.isNew = isNew
    }
}

public struct ScheduledEntry: Hashable, Sendable {
    public var scheduledIds: [String]
    /// "Jetzt buchen" approves; the automatic entry leaves the transactions for review.
    public var approved: Bool
    public var taken: Set<String>

    public init(scheduledIds: [String], approved: Bool, taken: Set<String> = []) {
        self.scheduledIds = scheduledIds
        self.approved = approved
        self.taken = taken
    }
}

extension ScheduledTransaction {
    /// The schedule as the register editor edits it: a transaction with the schedule's id.
    public var editableTransaction: Transaction {
        Transaction(
            id: id, accountId: accountId, date: nextDate, payeeId: payeeId, categoryId: categoryId, memo: memo,
            amount: amount, cleared: cleared, subtransactions: subtransactions)
    }
}

extension Budget {
    public func scheduledTransaction(withId id: String) -> ScheduledTransaction? {
        scheduledTransactions.first { $0.id == id }
    }

    func scheduledIndex(_ id: String) -> Int? {
        scheduledTransactions.firstIndex { $0.id == id }
    }

    mutating func saveScheduledTransaction(_ save: ScheduledSave) throws {
        if !save.isNew && scheduledTransaction(withId: save.transaction.id) == nil {
            throw BudgetError.transactionNotFound(save.transaction.id)
        }
        let named = try applyingSubPayeeNames(save.subPayeeNames, to: save.transaction)
        var (edited, payeeName) = normalizedForSave(named, payeeName: save.payeeName)
        try prepare(&edited, payeeName: payeeName)
        let scheduled = ScheduledTransaction(edited, repeats: save.repeats)
        if let index = scheduledIndex(scheduled.id) {
            scheduledTransactions[index] = scheduled
        } else {
            scheduledTransactions.append(scheduled)
        }
    }

    public func transactionIdsEntered(by entry: ScheduledEntry) -> [String] {
        var copy = self
        return copy.enterScheduledTransactions(entry)
    }

    @discardableResult
    mutating func enterScheduledTransactions(_ entry: ScheduledEntry) -> [String] {
        var entered: [String] = []
        var once: Set<String> = []
        for id in entry.scheduledIds {
            guard let index = scheduledIndex(id), canEnter(scheduledTransactions[index]) else { continue }
            if scheduledTransactions[index].repeats == .once { once.insert(id) }
            if let transactionId = addToRegister(scheduledIndex: index, approved: entry.approved, taken: entry.taken) {
                entered.append(transactionId)
            }
        }
        scheduledTransactions.removeAll { once.contains($0.id) }
        return entered
    }

    public func canEnter(_ scheduled: ScheduledTransaction) -> Bool {
        account(withId: scheduled.accountId)?.takesEntries == true
    }

    func entersWhenDue(_ scheduled: ScheduledTransaction) -> Bool {
        account(withId: scheduled.accountId)?.closed != true
    }

    mutating func enterDueScheduledTransactions(today: DateWithoutTime, taken: Set<String> = []) {
        var finishedOnce: Set<String> = []
        for index in scheduledTransactions.indices where entersWhenDue(scheduledTransactions[index]) {
            if scheduledTransactions[index].repeats == .once {
                guard scheduledTransactions[index].nextDate <= today else { continue }
                addToRegister(scheduledIndex: index, approved: false, taken: taken)
                finishedOnce.insert(scheduledTransactions[index].id)
                continue
            }
            while scheduledTransactions[index].nextDate <= today {
                let entered = scheduledTransactions[index].nextDate
                addToRegister(scheduledIndex: index, approved: false, taken: taken)
                if scheduledTransactions[index].nextDate <= entered { break }
            }
        }
        scheduledTransactions.removeAll { finishedOnce.contains($0.id) }
    }

    mutating func skipScheduledTransactions(_ ids: [String]) {
        let wanted = Set(ids)
        for index in scheduledTransactions.indices where wanted.contains(scheduledTransactions[index].id) {
            scheduledTransactions[index].nextDate = scheduledTransactions[index].followingDate
        }
        scheduledTransactions.removeAll { wanted.contains($0.id) && $0.repeats == .once }
    }

    mutating func deleteScheduledTransactions(_ ids: [String]) {
        let wanted = Set(ids)
        scheduledTransactions.removeAll { wanted.contains($0.id) }
    }

    public func scheduledTransfersInto(_ accountId: String, ids: [String]) -> Bool {
        let wanted = Set(ids)
        return scheduledTransactions.contains { wanted.contains($0.id) && $0.transfers(into: accountId) }
    }

    mutating func moveScheduledTransactions(_ ids: [String], to accountId: String) throws {
        guard let target = account(withId: accountId) else { throw BudgetError.accountNotFound(accountId) }
        if scheduledTransfersInto(accountId, ids: ids) {
            throw BudgetError.transferIntoMoveTarget(target.name)
        }
        let wanted = Set(ids)
        for index in scheduledTransactions.indices where wanted.contains(scheduledTransactions[index].id) {
            scheduledTransactions[index].accountId = accountId
        }
    }

    /// An id in `taken` is stored already, deleted or not: another writer entered that occurrence.
    @discardableResult
    private mutating func addToRegister(scheduledIndex index: Int, approved: Bool, taken: Set<String> = [])
        -> String?
    {
        let scheduled = scheduledTransactions[index]
        scheduledTransactions[index].nextDate = scheduled.followingDate
        let transaction = Transaction(occurrenceOf: scheduled, approved: approved)
        guard transactionIndex(transaction.id) == nil, !taken.contains(transaction.id) else { return nil }
        if (try? addTransaction(transaction, payeeName: nil)) == nil {
            var plain = transaction
            if isTransfer(plain) { plain.payeeId = nil }
            plain.subtransactions = plain.subtransactions.map { sub in
                var line = sub
                if isTransfer(line) { line.payeeId = nil }
                return line
            }
            if (try? addTransaction(plain, payeeName: nil)) == nil {
                plain.subtransactions = []
                plain.categoryId = nil
                try? addTransaction(plain, payeeName: nil)
            }
        }
        return transaction.id
    }
}
