import AbakusCore
import Foundation

@testable import AbakusUI

func day(_ text: String) -> DateWithoutTime {
    DateWithoutTime(string: text)!
}

/// Giro, Tagesgeld and Karte on budget, Depot a tracking account; en_US amounts.
struct RegisterFixture {
    var budget = Budget(
        budgetName: "Register",
        budgetMetaData: BudgetMetaData(currencyISOSymbol: "USD", currencyLocale: "en_US", dateLocale: "en_GB"))
    let giro = "GIRO"
    let tagesgeld = "TAGES"
    let karte = "KARTE"
    let depot = "DEPOT"

    init(start: DateWithoutTime = day("2014-04-29")) {
        let accounts: [(String, String, AccountKind, Decimal)] = [
            (giro, "Giro", .checking, 1111), (tagesgeld, "Tagesgeld", .savings, 500), (karte, "Karte", .checking, 0),
            (depot, "Depot", .tracking, 2000),
        ]
        for (id, name, type, balance) in accounts {
            try! budget.apply(
                .addAccount(
                    NewAccount(
                        id: id, name: name, kind: type, startingBalance: balance,
                        startDate: start)))
        }
    }

    func category(_ master: String, _ sub: String) -> String {
        budget.categoryGroups.first { $0.name == master }!.categories.first { $0.name == sub }!.id
    }

    var groceries: String { category("Everyday Expenses", "Groceries") }

    @discardableResult
    mutating func add(
        _ accountId: String, _ amount: Decimal, on date: String = "2014-05-10", payee: String? = "Shop",
        category: String? = nil, memo: String? = nil, id: String = EntityID.createUID(),
        cleared: ClearedStatus = .uncleared, approved: Bool = true,
        source: TransactionSource = .manual, target: String? = nil, subtransactions: [Subtransaction] = []
    ) -> String {
        let transaction = Transaction(
            id: id, accountId: accountId, date: day(date), categoryId: category, memo: memo, amount: amount,
            cleared: cleared, approved: approved, source: source, subtransactions: subtransactions
        ).transferring(to: target)
        try! budget.apply(.addTransaction(transaction, payeeName: target == nil ? payee : nil))
        return id
    }

    @discardableResult
    mutating func addSchedule(
        _ id: String, _ amount: Decimal = -25, on date: String = "2014-06-02", account: String? = nil,
        payee: String? = "Rent", category: String? = nil, memo: String? = nil, target: String? = nil,
        frequency: ScheduledTransactionFrequency = .monthly, subtransactions: [Subtransaction] = []
    ) -> String {
        let transaction = Transaction(
            id: id, accountId: account ?? giro, date: day(date), categoryId: category, memo: memo, amount: amount,
            subtransactions: subtransactions
        ).transferring(to: target)
        try! budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, frequency: frequency, payeeName: payee, isNew: true)))
        return id
    }

    /// Rent of 25: 20 for Groceries and 5 for Groceries or a transfer to `target`.
    mutating func addSplitSchedule(
        _ id: String = "S1", on date: String = "2014-06-02", account: String? = nil, transferTo target: String? = nil
    ) {
        let groceries = groceries
        addSchedule(
            id, on: date, account: account, category: EntityID.splitCategory,
            subtransactions: [
                Subtransaction(transactionId: id, amount: -20, categoryId: groceries),
                Subtransaction(
                    transactionId: id, amount: -5, categoryId: target == nil ? groceries : nil
                ).transferring(to: target),
            ])
    }

    func startingBalanceId(of accountId: String) -> String {
        budget.transactions.first { $0.accountId == accountId && !budget.isTransfer($0) }!.id
    }

    @MainActor
    func model(selection: SidebarSelection? = nil) -> RegisterViewModel {
        let store = BudgetStore(budget: budget, today: { editDay })
        return RegisterViewModel(store: store, navigation: NavigationState(selection: selection ?? .account(giro)))
    }
}

extension RegisterMenuItem {
    var submenu: [RegisterMenuItem]? {
        if case .submenu(let items) = kind { return items }
        return nil
    }

    func item(titled title: String) -> RegisterMenuItem? {
        if self.title == title { return self }
        return submenu?.lazy.compactMap { $0.item(titled: title) }.first
    }
}

extension [RegisterMenuItem] {
    func item(titled title: String) -> RegisterMenuItem? {
        lazy.compactMap { $0.item(titled: title) }.first
    }
}

extension SplittableTransaction {
    func transferring(to accountId: String?) -> Self {
        var copy = self
        if let accountId { copy.transfer(to: accountId) }
        return copy
    }
}

extension Subtransaction {
    func transferring(to accountId: String?) -> Subtransaction {
        var copy = self
        if let accountId { copy.transfer(to: accountId) }
        return copy
    }
}
