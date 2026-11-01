import Foundation

public enum BudgetCommand: Hashable, Sendable {
    case addAccount(NewAccount)
    case editAccount(Account)
    case moveAccount(accountId: String, index: Int)
    /// `payeeName` is what the user typed: `"Transfer : <Account>"` makes a transfer, other text a payee.
    case addTransaction(Transaction, payeeName: String? = nil)
    case updateTransaction(Transaction, payeeName: String? = nil)
    /// The register editor's Done / Save: split cleanup, approval, payee rename and auto-fill memory included.
    case saveTransaction(TransactionSave)
    case addNamedCategory(groupName: String, name: String)
    case deleteTransactions([String])
    case setCleared([String], ClearedStatus)
    case approveTransactions([String])
    /// The cleared column's rule: all cleared become uncleared, otherwise all become cleared and approved.
    case toggleCleared([String])
    case categorizeTransactions([String], categoryId: String?)
    case fillMissingCategory([String], categoryId: String)
    case removeTransferCategories([String])
    case moveTransactions([String], toAccountId: String)
    case restoreTransactions([Transaction], payees: [Payee])
    case restoreMovedTransactions([MovedTransaction])
    case makeRecurring(transactionId: String, scheduleId: String, today: DateWithoutTime)
    case moveToScheduler(transactionId: String, scheduleId: String)
    case renamePayee(payeeId: String, name: String)
    case combinePayees([String], name: String)
    case setPayeesHidden([String], Bool)
    case setPayeeLastCategory(payeeId: String, categoryId: String?)
    case setPayeeRenameConditions(payeeId: String, [PayeeRenameCondition])
    case applyRenameRules(payeeId: String)
    case finishReconciliation(ReconciliationFinish)
    case adjustBalance(BalanceAdjustment)
    case saveScheduledTransaction(ScheduledSave)
    case enterScheduledTransactions(ScheduledEntry)
    case enterDueScheduledTransactions(today: DateWithoutTime, taken: Set<String> = [])
    case skipScheduledTransactions([String])
    case deleteScheduledTransactions([String])
    case moveScheduledTransactions([String], toAccount: String)
    case setAssigned(month: DateWithoutTime, categoryId: String, amount: Decimal)
    /// Moves an assignment within the month; `EntityID.readyToAssignCategory` stands for Zu verteilen on either side.
    case moveAssigned(month: DateWithoutTime, from: String, to: String, amount: Decimal)
    case quickBudget(month: DateWithoutTime, fill: QuickBudgetFill, today: DateWithoutTime)
    case fillUnderfunded(month: DateWithoutTime, today: DateWithoutTime)
    /// `.ended` ends the target from the month on.
    case setTarget(month: DateWithoutTime, categoryId: String, target: Target)
    case setTargetSnoozed(month: DateWithoutTime, categoryId: String, Bool)
    case addCategoryGroup(groupId: String)
    case addCategory(groupId: String, categoryId: String)
    case renameCategoryGroup(groupId: String, name: String)
    case renameCategory(categoryId: String, name: String)
    case deleteCategory(categoryId: String, into: String)
    /// Only a category nothing refers to, as a new one cancelled in its callout.
    case discardCategory(categoryId: String)
    /// Only an empty group.
    case deleteCategoryGroup(groupId: String)
    case moveCategory(categoryId: String, toGroupId: String, index: Int)
    case moveCategoryGroup(groupId: String, index: Int)
    case setCategoryGroupExpanded(groupId: String, Bool)
    case setAllCategoryGroupsExpanded(Bool)
}

extension Budget {
    /// No command changes what the source of a led transaction leads.
    public mutating func apply(_ command: BudgetCommand) throws {
        let before = self
        try run(command)
        if let leader = leaderOfChangedLedTransaction(since: before) {
            self = before
            throw BudgetError.ledTransaction(leader)
        }
    }

    private mutating func run(_ command: BudgetCommand) throws {
        switch command {
        case .addAccount(let new): try addAccount(new)
        case .editAccount(let account): try editAccount(account)
        case .moveAccount(let accountId, let index): try moveAccount(accountId, index: index)
        case .addTransaction(let transaction, let payeeName): try addTransaction(transaction, payeeName: payeeName)
        case .updateTransaction(let transaction, let payeeName):
            try updateTransaction(transaction, payeeName: payeeName)
        case .saveTransaction(let save): try saveTransaction(save)
        case .addNamedCategory(let groupName, let name): try addNamedCategory(groupName: groupName, name: name)
        case .deleteTransactions(let ids): deleteTransactions(ids)
        case .setCleared(let ids, let status): setCleared(status, for: ids)
        case .approveTransactions(let ids): approveTransactions(ids)
        case .toggleCleared(let ids): toggleCleared(ids)
        case .categorizeTransactions(let ids, let categoryId): categorizeTransactions(ids, categoryId: categoryId)
        case .fillMissingCategory(let ids, let categoryId): fillMissingCategory(ids, categoryId: categoryId)
        case .removeTransferCategories(let ids): removeTransferCategories(ids)
        case .moveTransactions(let ids, let accountId): try moveTransactions(ids, to: accountId)
        case .restoreTransactions(let transactions, let payees): restoreTransactions(transactions, payees: payees)
        case .restoreMovedTransactions(let moved): try restoreMovedTransactions(moved)
        case .makeRecurring(let id, let scheduleId, let today):
            try scheduleCopy(of: id, scheduleId: scheduleId, monthlyAfter: today)
        case .moveToScheduler(let id, let scheduleId):
            try scheduleCopy(of: id, scheduleId: scheduleId, monthlyAfter: nil)
        case .renamePayee(let payeeId, let name): try renamePayeeEverywhere(payeeId, to: name)
        case .combinePayees(let ids, let name): try combinePayees(ids, into: name)
        case .setPayeesHidden(let ids, let hidden): setPayeesHidden(ids, hidden)
        case .setPayeeLastCategory(let payeeId, let categoryId):
            setPayeeLastCategory(payeeId, categoryId: categoryId)
        case .setPayeeRenameConditions(let payeeId, let conditions): setPayeeRenameConditions(payeeId, conditions)
        case .applyRenameRules(let payeeId): applyRenameRules(payeeId)
        case .finishReconciliation(let finish): try finishReconciliation(finish)
        case .adjustBalance(let adjustment): try adjustBalance(adjustment)
        case .saveScheduledTransaction(let save): try saveScheduledTransaction(save)
        case .enterScheduledTransactions(let entry): enterScheduledTransactions(entry)
        case .enterDueScheduledTransactions(let today, let taken):
            enterDueScheduledTransactions(today: today, taken: taken)
        case .skipScheduledTransactions(let ids): skipScheduledTransactions(ids)
        case .deleteScheduledTransactions(let ids): deleteScheduledTransactions(ids)
        case .moveScheduledTransactions(let ids, let accountId): try moveScheduledTransactions(ids, to: accountId)
        case .setAssigned(let month, let categoryId, let amount):
            try setAssigned(amount, month: month, categoryId: categoryId)
        case .moveAssigned(let month, let from, let to, let amount):
            try moveAssigned(amount, month: month, from: from, to: to)
        case .quickBudget(let month, let fill, let today): quickBudget(month: month, fill: fill, today: today)
        case .fillUnderfunded(let month, let today): fillUnderfunded(month: month, today: today)
        case .setTarget(let month, let categoryId, let target):
            try setTarget(target, month: month, categoryId: categoryId)
        case .setTargetSnoozed(let month, let categoryId, let snoozed):
            try setTargetSnoozed(snoozed, month: month, categoryId: categoryId)
        case .addCategoryGroup(let groupId): addCategoryGroup(id: groupId)
        case .addCategory(let groupId, let categoryId): try addCategory(groupId: groupId, id: categoryId)
        case .renameCategoryGroup(let groupId, let name): try renameCategoryGroup(groupId, to: name)
        case .renameCategory(let categoryId, let name): try renameCategory(categoryId, to: name)
        case .deleteCategory(let categoryId, let into): try deleteCategory(categoryId, into: into)
        case .discardCategory(let categoryId): try discardCategory(categoryId)
        case .deleteCategoryGroup(let groupId): try deleteCategoryGroup(groupId)
        case .moveCategory(let categoryId, let groupId, let index):
            try moveCategory(categoryId, toGroup: groupId, index: index)
        case .moveCategoryGroup(let groupId, let index): try moveCategoryGroup(groupId, index: index)
        case .setCategoryGroupExpanded(let groupId, let expanded): try setCategoryGroupExpanded(groupId, expanded)
        case .setAllCategoryGroupsExpanded(let expanded): setAllCategoryGroupsExpanded(expanded)
        }
    }

    public func applying(_ command: BudgetCommand) throws -> Budget {
        var copy = self
        try copy.apply(command)
        return copy
    }
}
