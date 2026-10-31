import Foundation

extension Budget {
    func transactionIndex(_ id: String) -> Int? {
        transactions.firstIndex { $0.id == id }
    }

    func splitParentIndex(ofSub subId: String) -> Int? {
        transactions.firstIndex { $0.subtransactions.contains { $0.id == subId } }
    }

    /// True for the counterpart of a split's transfer part: its amount and payee can only change from the split.
    public func isTransferFromSplit(_ transaction: Transaction) -> Bool {
        transaction.isTransferFromSplit
    }

    mutating func addTransaction(_ input: Transaction, payeeName: String?) throws {
        var transaction = input
        transaction.ledBy = nil
        transaction.matchedTransactionId = nil
        transaction.transferTransactionId = nil
        transaction.transferSubtransactionId = nil
        for index in transaction.subtransactions.indices {
            transaction.subtransactions[index].transferTransactionId = nil
        }
        try prepare(&transaction, payeeName: payeeName)
        transactions.append(transaction)
        syncTransfers(of: transaction.id, previous: nil)
    }

    mutating func updateTransaction(_ input: Transaction, payeeName: String?) throws {
        guard let index = transactionIndex(input.id) else {
            throw BudgetError.transactionNotFound(input.id)
        }
        let previous = transactions[index]
        var transaction = input
        transaction.ledBy = previous.ledBy
        transaction.matchedTransactionId = previous.matchedTransactionId
        transaction.transferTransactionId = previous.transferTransactionId
        transaction.transferSubtransactionId = previous.transferSubtransactionId
        let subLinks = Dictionary(uniqueKeysWithValues: previous.subtransactions.map { ($0.id, $0) })
        for index in transaction.subtransactions.indices {
            transaction.subtransactions[index].transferTransactionId =
                subLinks[transaction.subtransactions[index].id]?.transferTransactionId
        }
        if isTransferFromSplit(previous) {
            try updateTransferFromSplit(previous: previous, edited: transaction, payeeName: payeeName)
            return
        }
        try prepare(&transaction, payeeName: payeeName)
        transactions[index] = transaction
        if transaction.approved { approve(at: index) }
        syncTransfers(of: transaction.id, previous: previous)
    }

    /// Led transactions stay, and so does what would take one with it.
    mutating func deleteTransactions(_ ids: [String]) {
        let led = ledTransactionIds
        for id in ids {
            guard let transaction = transaction(withId: id), !isTransferFromSplit(transaction) else { continue }
            let removed = removedWithIt(transaction)
            guard removed.isDisjoint(with: led) else { continue }
            transactions.removeAll { removed.contains($0.id) }
        }
    }

    func removedWithIt(_ transaction: Transaction) -> Set<String> {
        var removed: Set<String> = [transaction.id]
        if let counterpartId = transaction.transferTransactionId { removed.insert(counterpartId) }
        for sub in transaction.subtransactions {
            if let counterpartId = sub.transferTransactionId { removed.insert(counterpartId) }
        }
        return removed
    }

    mutating func setCleared(_ status: ClearedStatus, for ids: [String]) {
        let wanted = Set(ids)
        for index in transactions.indices where wanted.contains(transactions[index].id) {
            transactions[index].cleared = status
        }
    }

    /// Drops empty split lines; the transfer of a collapsed one-line split survives an empty parent payee.
    func normalizedForSave(_ transaction: Transaction, payeeName: String?) -> (Transaction, payeeName: String?) {
        let parentPayee = payeeName ?? self.payeeName(of: transaction)
        let normalized = SplitRules.normalized(transaction, parentPayeeName: parentPayee, in: self)
        guard let typed = payeeName, typed.trimmingCharacters(in: .whitespaces).isEmpty,
            let target = transferAccountId(of: normalized).flatMap(account(withId:))
        else { return (normalized, payeeName) }
        return (normalized, target.transferPayeeName)
    }

    mutating func prepare(_ transaction: inout Transaction, payeeName: String?) throws {
        guard account(withId: transaction.accountId) != nil else {
            throw BudgetError.accountNotFound(transaction.accountId)
        }
        if let payeeName { try applyPayeeName(payeeName, to: &transaction) }
        if let targetId = transferAccountId(ofPayee: transaction.payeeId) {
            try validateTransferTarget(targetId, from: transaction.accountId)
            if transaction.isSplit { throw BudgetError.splitCannotBeTransfer }
        }
        if transaction.categoryId == EntityID.splitCategory { transaction.categoryId = nil }
        guard transaction.isSplit else { return }
        transaction.categoryId = nil
        for index in transaction.subtransactions.indices {
            transaction.subtransactions[index].transactionId = transaction.id
            if let targetId = transferAccountId(of: transaction.subtransactions[index]) {
                try validateTransferTarget(targetId, from: transaction.accountId)
            }
        }
        if Amount.sum(transaction.subtransactions.map(\.amount)) != transaction.amount {
            throw BudgetError.splitAmountMismatch
        }
    }

    mutating func applyPayeeName(_ name: String, to transaction: inout Transaction) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            transaction.payeeId = nil
        } else if let targetName = Payee.transferTargetAccountName(trimmed) {
            guard let target = account(named: targetName) else { throw BudgetError.invalidTransferPayee(trimmed) }
            transaction.transfer(to: target.id)
        } else {
            transaction.payeeId = payeeIdCreatingIfNeeded(named: trimmed)
        }
    }

    mutating func applyingSubPayeeNames(_ names: [String: String], to input: Transaction) throws -> Transaction {
        var transaction = input
        for index in transaction.subtransactions.indices {
            guard let name = names[transaction.subtransactions[index].id] else { continue }
            try applyPayeeName(name, to: &transaction.subtransactions[index])
        }
        return transaction
    }

    private mutating func applyPayeeName(_ name: String, to sub: inout Subtransaction) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sub.payeeId = nil
        if let targetName = Payee.transferTargetAccountName(trimmed) {
            guard let target = account(named: targetName) else { throw BudgetError.invalidTransferPayee(trimmed) }
            sub.transfer(to: target.id)
        } else if !trimmed.isEmpty {
            sub.payeeId = payeeIdCreatingIfNeeded(named: trimmed)
        }
    }

    func validateTransferTarget(_ targetId: String, from accountId: String) throws {
        guard account(withId: targetId) != nil else { throw BudgetError.invalidTransferPayee(targetId) }
        if targetId == accountId { throw BudgetError.transferToSameAccount }
    }

    mutating func syncTransfers(of id: String, previous: Transaction?) {
        guard let index = transactionIndex(id) else { return }
        let source = transactions[index]
        if !source.isTransferFromSplit, let targetId = transferAccountId(of: source) {
            let counterpartId = upsertCounterpart(
                existingId: source.transferTransactionId, side: .transaction(source.id),
                accountId: targetId, otherAccountId: source.accountId, date: source.date, memo: source.memo,
                amount: -source.amount, template: source)
            if let current = transactionIndex(id) { transactions[current].transferTransactionId = counterpartId }
        } else if !source.isTransferFromSplit, let counterpartId = source.transferTransactionId {
            transactions.removeAll { $0.id == counterpartId }
            if let current = transactionIndex(id) { transactions[current].transferTransactionId = nil }
        }
        syncSubTransfers(of: id, previous: previous)
    }

    private mutating func syncSubTransfers(of id: String, previous: Transaction?) {
        guard let parentIndex = transactionIndex(id) else { return }
        let parent = transactions[parentIndex]
        let currentSubIds = Set(parent.subtransactions.map(\.id))
        for oldSub in previous?.subtransactions ?? [] where !currentSubIds.contains(oldSub.id) {
            if let counterpartId = oldSub.transferTransactionId {
                transactions.removeAll { $0.id == counterpartId }
            }
        }
        for sub in parent.subtransactions {
            let counterpartId: String?
            if let targetId = transferAccountId(of: sub) {
                counterpartId = upsertCounterpart(
                    existingId: sub.transferTransactionId, side: .subtransaction(sub.id), accountId: targetId,
                    otherAccountId: parent.accountId, date: parent.date, memo: sub.memo, amount: -sub.amount,
                    template: parent)
            } else {
                if let existing = sub.transferTransactionId { transactions.removeAll { $0.id == existing } }
                counterpartId = nil
            }
            guard let current = transactionIndex(id),
                let subIndex = transactions[current].subtransactions.firstIndex(where: { $0.id == sub.id })
            else { continue }
            transactions[current].subtransactions[subIndex].transferTransactionId = counterpartId
        }
    }

    private enum TransferSide {
        case transaction(String)
        case subtransaction(String)

        var id: String {
            switch self {
            case .transaction(let id), .subtransaction(let id): id
            }
        }
    }

    private mutating func upsertCounterpart(
        existingId: String?, side: TransferSide, accountId: String, otherAccountId: String,
        date: DateWithoutTime, memo: String?, amount: Decimal, template: Transaction
    ) -> String {
        let counterpartId =
            existingId.flatMap { transactionIndex($0) != nil ? $0 : nil }
            ?? EntityID.transferCounterpart(of: side.id)
        var counterpart =
            transaction(withId: counterpartId)
            ?? Transaction(
                id: counterpartId, accountId: accountId, date: date, amount: amount, cleared: .uncleared,
                approved: template.approved, source: template.source)
        counterpart.accountId = accountId
        counterpart.transfer(to: otherAccountId)
        counterpart.transferTransactionId = nil
        counterpart.transferSubtransactionId = nil
        switch side {
        case .transaction(let id): counterpart.transferTransactionId = id
        case .subtransaction(let id): counterpart.transferSubtransactionId = id
        }
        counterpart.date = date
        counterpart.memo = memo
        counterpart.amount = amount
        if let index = transactionIndex(counterpartId) {
            transactions[index] = counterpart
        } else {
            transactions.append(counterpart)
        }
        return counterpartId
    }

    private mutating func updateTransferFromSplit(
        previous: Transaction, edited: Transaction, payeeName: String?
    ) throws {
        guard let subId = previous.transferSubtransactionId, let parentIndex = splitParentIndex(ofSub: subId),
            let subIndex = transactions[parentIndex].subtransactions.firstIndex(where: { $0.id == subId }),
            let index = transactionIndex(previous.id)
        else { throw BudgetError.transactionNotFound(previous.id) }
        if edited.amount != previous.amount { throw BudgetError.transferFromSplitAmountLocked }
        var target = transferAccountId(of: edited)
        if let payeeName {
            target = Payee.transferTargetAccountName(payeeName).flatMap { account(named: $0)?.id }
        }
        if target != transferAccountId(of: previous) || edited.accountId != previous.accountId {
            throw BudgetError.transferFromSplitPayeeLocked
        }
        var updated = edited
        updated.payeeId = previous.payeeId
        updated.subtransactions = []
        transactions[index] = updated
        transactions[parentIndex].subtransactions[subIndex].memo = edited.memo
        if edited.date != previous.date {
            transactions[parentIndex].date = edited.date
            syncSubTransfers(of: transactions[parentIndex].id, previous: transactions[parentIndex])
        }
    }
}
