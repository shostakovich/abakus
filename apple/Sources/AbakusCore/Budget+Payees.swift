import Foundation

public struct RenameRulePreview: Hashable, Sendable {
    public var transactionCount: Int
    public var payeeNames: [String]
}

extension Budget {
    public var payeesSortedByName: [Payee] {
        payees.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    public func payeeUseCount(_ payeeId: String) -> Int {
        transactions.count(where: { $0.uses(payee: payeeId) })
            + scheduledTransactions.count(where: { $0.uses(payee: payeeId) })
    }

    public func payeeHasScheduledTransactions(_ payeeId: String) -> Bool {
        scheduledTransactions.contains { $0.uses(payee: payeeId) }
    }

    public func isSuggested(_ payee: Payee) -> Bool {
        if let accountId = payee.transferAccountId { return account(withId: accountId)?.closed == false }
        return !payee.hidden
    }

    public func renameConditions(ofPayee payeeId: String) -> [PayeeRenameCondition] {
        payeeRenameConditions.filter { $0.payeeId == payeeId }.sortedByPosition()
    }

    public func appliesRenameRules(of payee: Payee, to name: String) -> Bool {
        guard !Payee.isTransferPayeeName(name) else { return false }
        return Payee.sameName(name, payee.name) || renameConditions(ofPayee: payee.id).contains { $0.matches(name) }
    }

    func isPayeeUsed(_ payeeId: String) -> Bool {
        transactions.contains { $0.uses(payee: payeeId) } || scheduledTransactions.contains { $0.uses(payee: payeeId) }
            || matchProposals.contains { $0.uses(payee: payeeId) }
    }

    func validateNewPayeeName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { throw BudgetError.emptyPayeeName }
        if Payee.isTransferPayeeName(trimmed) { throw BudgetError.transferPayeeName(trimmed) }
    }

    mutating func renamePayeeEverywhere(_ payeeId: String, to name: String) throws {
        try validateNewPayeeName(name)
        guard let payee = payee(withId: payeeId) else { return }
        if payee.isTransferPayee { throw BudgetError.transferPayeeCannotBeRenamed }
        renamePayee(payeeId, to: name)
    }

    /// A capitalisation change adds no "ist" rule for the old name.
    @discardableResult
    mutating func renamePayee(_ payeeId: String?, to name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let payeeId, let index = payees.firstIndex(where: { $0.id == payeeId }),
            !payees[index].isTransferPayee, !trimmed.isEmpty, !Payee.isTransferPayeeName(trimmed)
        else { return nil }
        let oldName = payees[index].name
        guard oldName != trimmed else { return payeeId }
        let targetId: String
        if let existing = payees.first(where: {
            $0.id != payeeId && !$0.isTransferPayee && Payee.sameName($0.name, trimmed)
        }) {
            mergePayee(payeeId, into: existing.id)
            targetId = existing.id
        } else {
            payees[index].name = trimmed
            if Payee.sameName(oldName, trimmed) { return payeeId }
            targetId = payeeId
        }
        recordRenameRule(oldName: oldName, on: targetId)
        return targetId
    }

    private mutating func mergePayee(_ sourceId: String, into targetId: String) {
        for index in transactions.indices where transactions[index].uses(payee: sourceId) {
            transactions[index].replacePayee(sourceId, with: targetId)
        }
        for index in scheduledTransactions.indices where scheduledTransactions[index].uses(payee: sourceId) {
            scheduledTransactions[index].replacePayee(sourceId, with: targetId)
        }
        takeOverRenameConditions(from: sourceId, into: targetId)
        payees.removeAll { $0.id == sourceId }
        successorIds[sourceId] = targetId
    }

    private mutating func takeOverRenameConditions(from sourceId: String, into targetId: String) {
        var kept = renameConditions(ofPayee: targetId)
        for condition in renameConditions(ofPayee: sourceId)
        where !kept.contains(where: { $0.isEquivalent(to: condition) }) {
            kept.append(condition)
        }
        storeRenameConditions(kept, ofPayee: targetId)
        payeeRenameConditions.removeAll { $0.payeeId == sourceId }
    }

    private mutating func recordRenameRule(oldName: String, on targetId: String) {
        let rule = PayeeRenameCondition(operator: .is, text: oldName)
        payeeRenameConditions.removeAll { $0.isEquivalent(to: rule) }
        guard let target = payee(withId: targetId), !appliesRenameRules(of: target, to: oldName) else { return }
        storeRenameConditions(renameConditions(ofPayee: targetId) + [rule], ofPayee: targetId)
    }

    private mutating func storeRenameConditions(_ conditions: [PayeeRenameCondition], ofPayee payeeId: String) {
        payeeRenameConditions.removeAll { $0.payeeId == payeeId }
        payeeRenameConditions += conditions.enumerated().map { position, condition in
            var stored = condition
            stored.payeeId = payeeId
            stored.position = position
            return stored
        }
    }

    mutating func combinePayees(_ payeeIds: [String], into name: String) throws {
        try validateNewPayeeName(name)
        for payeeId in payeeIds { renamePayee(payeeId, to: name) }
    }

    /// A transfer payee is suggested while its account is open.
    mutating func setPayeesHidden(_ payeeIds: [String], _ hidden: Bool) {
        let wanted = Set(payeeIds)
        for index in payees.indices where wanted.contains(payees[index].id) && !payees[index].isTransferPayee {
            payees[index].hidden = hidden
        }
    }

    mutating func setPayeeLastCategory(_ payeeId: String, categoryId: String?) {
        guard let index = payees.firstIndex(where: { $0.id == payeeId }) else { return }
        if let categoryId, !EntityID.isCategorized(categoryId) || category(withId: categoryId) == nil { return }
        payees[index].lastCategoryId = categoryId
    }

    mutating func setPayeeRenameConditions(_ payeeId: String, _ conditions: [PayeeRenameCondition]) {
        guard payee(withId: payeeId) != nil else { return }
        storeRenameConditions(conditions.filter { !$0.isBlank }, ofPayee: payeeId)
    }

    /// A transfer payee never applies in its own account or to a split.
    func renameRule(of payee: Payee, applies name: String, accountId: String, isSplit: Bool) -> Bool {
        if let target = payee.transferAccountId, target == accountId || isSplit { return false }
        return appliesRenameRules(of: payee, to: name)
    }

    private func ruleMatches(of target: Payee) -> (count: Int, payeeIds: [String]) {
        var count = 0
        var payeeIds: [String] = []
        func visit(_ payeeId: String?, accountId: String, isSplit: Bool) {
            guard let payeeId, payeeId != target.id, let payee = payee(withId: payeeId),
                renameRule(of: target, applies: payee.name, accountId: accountId, isSplit: isSplit)
            else { return }
            count += 1
            if !payeeIds.contains(payeeId) { payeeIds.append(payeeId) }
        }
        func visit(_ transaction: some SplittableTransaction, accountId: String) {
            visit(transaction.payeeId, accountId: accountId, isSplit: transaction.isSplit)
            for sub in transaction.subtransactions { visit(sub.payeeId, accountId: accountId, isSplit: true) }
        }
        for transaction in transactions { visit(transaction, accountId: transaction.accountId) }
        for scheduled in scheduledTransactions { visit(scheduled, accountId: scheduled.accountId) }
        return (count, payeeIds)
    }

    public func renameRulePreview(for payeeId: String) -> RenameRulePreview {
        guard let target = payee(withId: payeeId) else { return RenameRulePreview(transactionCount: 0, payeeNames: []) }
        let matches = ruleMatches(of: target)
        let names = matches.payeeIds.compactMap { payee(withId: $0)?.name }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return RenameRulePreview(transactionCount: matches.count, payeeNames: names)
    }

    mutating func applyRenameRules(_ payeeId: String) {
        guard let target = payee(withId: payeeId) else { return }
        for sourceId in ruleMatches(of: target).payeeIds {
            if target.isTransferPayee {
                convertToTransfers(sourceId, transferPayeeId: payeeId)
            } else {
                renamePayee(sourceId, to: target.name)
            }
        }
    }

    /// Transactions in the transfer's own account and splits keep the old payee.
    private mutating func convertToTransfers(_ sourceId: String, transferPayeeId: String) {
        guard let accountId = payee(withId: transferPayeeId)?.transferAccountId, let source = payee(withId: sourceId)
        else { return }
        let led = ledTransactionIds
        let ids = transactions.filter {
            $0.payeeId == sourceId && $0.accountId != accountId && !$0.isSplit && !led.contains($0.id)
        }.map(\.id)
        for id in ids {
            guard let index = transactionIndex(id) else { continue }
            let previous = transactions[index]
            transactions[index].payeeId = transferPayeeId
            syncTransfers(of: id, previous: previous)
        }
        for index in scheduledTransactions.indices
        where scheduledTransactions[index].payeeId == sourceId && scheduledTransactions[index].accountId != accountId
            && !scheduledTransactions[index].isSplit
        {
            scheduledTransactions[index].payeeId = transferPayeeId
        }
        guard !isPayeeUsed(sourceId) else { return }
        takeOverRenameConditions(from: sourceId, into: transferPayeeId)
        payees.removeAll { $0.id == sourceId }
        recordRenameRule(oldName: source.name, on: transferPayeeId)
    }
}
