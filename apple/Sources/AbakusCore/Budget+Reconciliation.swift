import Foundation

public struct ReconciliationSummary: Hashable, Sendable {
    public var reconciledBalance: Decimal
    public var clearedAbove: Decimal
    public var statementBalance: Decimal

    public var clearedBalance: Decimal { Amount.round(reconciledBalance + clearedAbove) }
    public var difference: Decimal { Amount.round(clearedBalance - statementBalance) }
    public var isBalanced: Bool { difference == 0 }

    public init(reconciledBalance: Decimal, clearedAbove: Decimal, statementBalance: Decimal) {
        self.reconciledBalance = reconciledBalance
        self.clearedAbove = clearedAbove
        self.statementBalance = statementBalance
    }
}

public struct ReconciliationFinish: Hashable, Sendable {
    public var accountId: String
    public var statementDate: DateWithoutTime
    public var statementBalance: Decimal
    /// The reconciliation list as shown: its Cleared rows become Reconciled.
    public var transactionIds: [String]
    public var createsAdjustment: Bool
    public var today: DateWithoutTime

    public init(
        accountId: String, statementDate: DateWithoutTime, statementBalance: Decimal, transactionIds: [String],
        createsAdjustment: Bool, today: DateWithoutTime
    ) {
        self.accountId = accountId
        self.statementDate = statementDate
        self.statementBalance = Amount.round(statementBalance)
        self.transactionIds = transactionIds
        self.createsAdjustment = createsAdjustment
        self.today = today
    }
}

public struct BalanceAdjustment: Hashable, Sendable {
    public var accountId: String
    public var workingBalance: Decimal
    public var today: DateWithoutTime

    public init(accountId: String, workingBalance: Decimal, today: DateWithoutTime) {
        self.accountId = accountId
        self.workingBalance = Amount.round(workingBalance)
        self.today = today
    }
}

extension Budget {
    public static let automaticTransactionMemo = "Automatisch angelegt"

    public func reconciliationList(accountId: String, through date: DateWithoutTime) -> [Transaction] {
        transactions.filter { $0.accountId == accountId && $0.cleared != .reconciled && $0.date <= date }
    }

    public func reconciliationSummary(accountId: String, statementBalance: Decimal, list: [Transaction])
        -> ReconciliationSummary
    {
        ReconciliationSummary(
            reconciledBalance: balances(forAccount: accountId).reconciled,
            clearedAbove: Amount.sum(list.filter { $0.cleared == .cleared }.map(\.amount)),
            statementBalance: statementBalance)
    }

    mutating func finishReconciliation(_ finish: ReconciliationFinish) throws {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == finish.accountId }) else {
            throw BudgetError.accountNotFound(finish.accountId)
        }
        let wanted = Set(finish.transactionIds)
        let list = reconciliationList(accountId: finish.accountId, through: finish.statementDate)
            .filter { wanted.contains($0.id) }
        if finish.createsAdjustment {
            let summary = reconciliationSummary(
                accountId: finish.accountId, statementBalance: finish.statementBalance, list: list)
            let working = balances(forAccount: finish.accountId).working
            if let id = adjustBalance(
                accountId: finish.accountId, to: Amount.round(working - summary.difference),
                payee: Payee.reconciliationBalanceAdjustmentName, isReconciliation: true, today: finish.today),
                let index = transactionIndex(id)
            {
                transactions[index].date = finish.statementDate
                transactions[index].cleared = .reconciled
            }
        }
        accounts[accountIndex].lastReconciledAt = finish.today.noon()
        let clearedIds = Set(list.filter { $0.cleared == .cleared }.map(\.id))
        for index in transactions.indices where clearedIds.contains(transactions[index].id) {
            transactions[index].cleared = .reconciled
        }
    }

    mutating func adjustBalance(_ adjustment: BalanceAdjustment) throws {
        guard account(withId: adjustment.accountId) != nil else {
            throw BudgetError.accountNotFound(adjustment.accountId)
        }
        adjustBalance(
            accountId: adjustment.accountId, to: adjustment.workingBalance, payee: Payee.manualBalanceAdjustmentName,
            isReconciliation: false, today: adjustment.today)
    }

    /// The id of the transaction that now carries the difference, if any.
    @discardableResult
    mutating func adjustBalance(
        accountId: String, to target: Decimal, payee: String, isReconciliation: Bool, today: DateWithoutTime
    ) -> String? {
        guard let account = account(withId: accountId) else { return nil }
        let own = transactions(inAccount: accountId)
        if own.isEmpty && !isReconciliation {
            return appendAutomatic(
                accountId: accountId, date: today, payee: Payee.startingBalanceName, memo: nil,
                categoryId: balanceCategory(of: account), amount: target)
        }
        if own.count == 1, let start = own.first, payeeName(of: start) == Payee.startingBalanceName,
            start.date == today, start.amount == 0, let index = transactionIndex(start.id)
        {
            transactions[index].amount = target
            return start.id
        }
        let difference = Amount.round(target - balances(forAccount: accountId).working)
        guard difference != 0 else { return nil }
        return appendAutomatic(
            accountId: accountId, date: today, payee: payee, memo: Self.automaticTransactionMemo,
            categoryId: balanceCategory(of: account), amount: difference)
    }

    private mutating func appendAutomatic(
        accountId: String, date: DateWithoutTime, payee: String, memo: String?, categoryId: String?, amount: Decimal
    ) -> String {
        let transaction = Transaction(
            accountId: accountId, date: date,
            payeeId: payeeIdCreatingIfNeeded(named: payee, hidden: payee == Payee.startingBalanceName),
            categoryId: categoryId, memo: memo, amount: amount, cleared: .cleared)
        transactions.append(transaction)
        return transaction.id
    }
}
