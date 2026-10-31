import Foundation

public struct NewAccount: Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: AccountKind
    public var startingBalance: Decimal
    public var startDate: DateWithoutTime

    public init(
        id: String = EntityID.createUID(),
        name: String,
        kind: AccountKind,
        startingBalance: Decimal,
        startDate: DateWithoutTime
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.startingBalance = Amount.round(startingBalance)
        self.startDate = startDate
    }
}

extension Budget {
    public func validateAccountName(_ name: String, excluding accountId: String? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw BudgetError.emptyAccountName }
        if trimmed.contains("`") { throw BudgetError.invalidAccountNameCharacter }
        let duplicate =
            trimmed.lowercased() == Account.allAccountsName.lowercased()
            || accounts.contains { $0.id != accountId && $0.name.lowercased() == trimmed.lowercased() }
        if duplicate { throw BudgetError.duplicateAccountName }
    }

    mutating func addAccount(_ new: NewAccount) throws {
        try validateAccountName(new.name)
        let account = Account(
            id: new.id,
            name: new.name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: new.kind,
            position: (accounts.map(\.position).max() ?? -1) + 1)
        accounts.append(account)
        refreshTransferPayees()
        transactions.append(
            Transaction(
                accountId: account.id, date: new.startDate,
                payeeId: payeeIdCreatingIfNeeded(named: Payee.startingBalanceName, hidden: true),
                categoryId: balanceCategory(of: account),
                amount: new.startingBalance, cleared: .cleared))
    }

    mutating func editAccount(_ edited: Account) throws {
        guard let index = accounts.firstIndex(where: { $0.id == edited.id }) else {
            throw BudgetError.accountNotFound(edited.id)
        }
        if edited.onBudget != accounts[index].onBudget { throw BudgetError.budgetStateIsFixed }
        try validateAccountName(edited.name, excluding: edited.id)
        var account = edited
        account.name = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index] = account
        refreshTransferPayees()
    }

    func balanceCategory(of account: Account) -> String? {
        account.onBudget ? readyToAssignCategoryId : nil
    }

    mutating func refreshTransferPayees() {
        let accountIds = Set(accounts.map(\.id))
        payees.removeAll { $0.isTransferPayee && !accountIds.contains($0.transferAccountId ?? "") }
        for account in accounts {
            let payee = Payee.transferPayee(for: account)
            if let index = payees.firstIndex(where: { $0.id == payee.id }) {
                payees[index].name = payee.name
            } else {
                payees.append(payee)
            }
        }
    }

    mutating func payeeIdCreatingIfNeeded(named name: String, hidden: Bool = false) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = payee(named: trimmed) { return existing.id }
        let payee = Payee(name: trimmed, hidden: hidden)
        payees.append(payee)
        return payee.id
    }
}
