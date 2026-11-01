import Foundation

public protocol Positioned {
    var id: String { get }
    var position: Int { get }
}

extension Sequence where Element: Positioned {
    /// Equal positions order by id, as on every writer.
    public func sortedByPosition() -> [Element] {
        sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }
}

/// The Mac's own settings of a budget; Abakus has no column for them.
public struct BudgetMetaData: Hashable, Sendable {
    public var budgetType: BudgetType
    public var currencyISOSymbol: String
    public var currencyLocale: String
    public var dateLocale: String
    public var strictBudget: Bool

    public init(
        budgetType: BudgetType = .personal,
        currencyISOSymbol: String = "EUR",
        currencyLocale: String = "de_DE",
        dateLocale: String = "de_DE",
        strictBudget: Bool = true
    ) {
        self.budgetType = budgetType
        self.currencyISOSymbol = currencyISOSymbol
        self.currencyLocale = currencyLocale
        self.dateLocale = dateLocale
        self.strictBudget = strictBudget
    }
}

/// Live rows only; the store keeps what is deleted as tombstones.
public struct Budget: Hashable, Sendable {

    public var budgetName: String
    public var budgetMetaData: BudgetMetaData
    /// Whether a group is expanded is each device's own.
    public var collapsedCategoryGroupIds: Set<String>
    public var accounts: [Account]
    public var categoryGroups: [CategoryGroup]
    public var payees: [Payee]
    public var payeeRenameConditions: [PayeeRenameCondition]
    public var transactions: [Transaction]
    /// Bank imports proposed as a match for a transaction; they count nowhere and no command touches them.
    public internal(set) var matchProposals: [Transaction]
    public var scheduledTransactions: [ScheduledTransaction]
    public internal(set) var assignments: [Assignment]
    public internal(set) var targetVersions: [TargetVersion]
    public internal(set) var targetSnoozes: [TargetSnooze]
    public internal(set) var successorIds: [String: String]

    public init(
        budgetName: String,
        budgetMetaData: BudgetMetaData = BudgetMetaData(),
        collapsedCategoryGroupIds: Set<String> = [],
        accounts: [Account] = [],
        categoryGroups: [CategoryGroup]? = nil,
        payees: [Payee] = [],
        payeeRenameConditions: [PayeeRenameCondition] = [],
        transactions: [Transaction] = [],
        scheduledTransactions: [ScheduledTransaction] = [],
        assignments: [Assignment] = [],
        targetVersions: [TargetVersion] = [],
        targetSnoozes: [TargetSnooze] = [],
        successorIds: [String: String] = [:]
    ) {
        self.budgetName = budgetName
        self.budgetMetaData = budgetMetaData
        self.collapsedCategoryGroupIds = collapsedCategoryGroupIds
        self.accounts = accounts
        self.categoryGroups = categoryGroups ?? DefaultCategories.categoryGroups(for: budgetMetaData.budgetType)
        self.payees = payees
        self.payeeRenameConditions = payeeRenameConditions
        self.transactions = transactions.filter { $0.matchedTransactionId == nil }
        matchProposals = transactions.filter { $0.matchedTransactionId != nil }
        self.scheduledTransactions = scheduledTransactions
        self.assignments = assignments.filter { $0.amount != 0 }
        self.targetVersions = targetVersions
        self.targetSnoozes = targetSnoozes
        self.successorIds = successorIds
    }

    public var readyToAssignCategoryId: String {
        categoryGroups.lazy.flatMap(\.categories).first(where: \.isInternal)?.id ?? ""
    }

    public func isReadyToAssign(_ categoryId: String?) -> Bool {
        categoryId != nil && categoryId == readyToAssignCategoryId
    }

    public func account(withId id: String) -> Account? {
        accounts.first { $0.id == id }
    }

    public func account(named name: String) -> Account? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        return accounts.first { $0.name.lowercased() == wanted }
    }

    public func transaction(withId id: String) -> Transaction? {
        transactions.first { $0.id == id }
    }

    public func payee(withId id: String) -> Payee? {
        payees.first { $0.id == id }
    }

    public func category(withId id: String) -> Category? {
        for group in categoryGroups {
            if let category = group.categories.first(where: { $0.id == id }) { return category }
        }
        return nil
    }

    public func categoryGroup(withId id: String) -> CategoryGroup? {
        categoryGroups.first { $0.id == id }
    }

    public var sortedAccounts: [Account] { accounts.sortedByPosition() }

    public func transactions(inAccount accountId: String) -> [Transaction] {
        transactions.filter { $0.accountId == accountId }
    }

    public func scheduledTransactions(inAccount accountId: String) -> [ScheduledTransaction] {
        scheduledTransactions.filter { $0.accountId == accountId }.sorted { $0.nextDate < $1.nextDate }
    }

    public func transferAccountId(ofPayee payeeId: String?) -> String? {
        guard let payeeId else { return nil }
        return payee(withId: payeeId)?.transferAccountId
    }

    /// A split is no transfer as a whole.
    public func transferAccountId(of transaction: some SplittableTransaction) -> String? {
        transaction.isSplit ? nil : transferAccountId(ofPayee: transaction.payeeId)
    }

    public func transferAccountId(of part: Subtransaction) -> String? {
        transferAccountId(ofPayee: part.payeeId)
    }

    public func isTransfer(_ transaction: some SplittableTransaction) -> Bool {
        transferAccountId(of: transaction) != nil
    }

    public func isTransfer(_ part: Subtransaction) -> Bool {
        transferAccountId(of: part) != nil
    }

    public func payeeName(ofPayee payeeId: String?) -> String {
        guard let payeeId, let payee = payee(withId: payeeId) else { return "" }
        return payeeName(of: payee)
    }

    public func payeeName(of payee: Payee) -> String {
        payee.transferAccountId.flatMap(account(withId:))?.transferPayeeName ?? payee.name
    }

    public func payeeName(of transaction: some SplittableTransaction) -> String {
        payeeName(ofPayee: transaction.payeeId)
    }

    public func payeeName(of part: Subtransaction) -> String {
        payeeName(ofPayee: part.payeeId)
    }

    public func categoryDisplayName(_ categoryId: String?) -> String {
        guard let categoryId else { return "" }
        if isReadyToAssign(categoryId) { return DefaultCategories.readyToAssignName }
        if categoryId == EntityID.splitCategory { return DefaultCategories.splitCategoryName }
        guard let category = category(withId: categoryId) else { return "" }
        let groupName = categoryGroup(withId: category.categoryGroupId)?.name ?? ""
        return "\(groupName): \(category.name)"
    }

    /// The category's own name, without its group.
    public func categoryName(_ categoryId: String?) -> String {
        guard let categoryId else { return "" }
        if isReadyToAssign(categoryId) { return DefaultCategories.readyToAssignName }
        if categoryId == EntityID.splitCategory { return DefaultCategories.splitCategoryName }
        return category(withId: categoryId)?.name ?? ""
    }
}
