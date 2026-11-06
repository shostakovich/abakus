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
            if summary.difference != 0, let account = account(withId: finish.accountId) {
                transactions.append(
                    Transaction(
                        accountId: account.id, date: finish.statementDate,
                        payeeId: payeeIdCreatingIfNeeded(
                            named: Payee.reconciliationBalanceAdjustmentName, hidden: false),
                        categoryId: balanceCategory(of: account), memo: Self.automaticTransactionMemo,
                        amount: Amount.round(-summary.difference), cleared: .reconciled))
            }
        }
        accounts[accountIndex].lastReconciledAt = finish.today.noon()
        let clearedIds = Set(list.filter { $0.cleared == .cleared }.map(\.id))
        for index in transactions.indices where clearedIds.contains(transactions[index].id) {
            transactions[index].cleared = .reconciled
        }
    }
}
