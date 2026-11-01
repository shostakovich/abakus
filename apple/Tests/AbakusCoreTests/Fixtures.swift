import AbakusCore
import Foundation

let october23 = DateWithoutTime(year: 2026, month: 10, day: 23)

func date(_ text: String) -> DateWithoutTime {
    DateWithoutTime(string: text)!
}

func decimal(_ text: String) -> Decimal {
    Decimal(string: text)!
}

func withTemporaryDatabase<T>(_ body: (URL) throws -> T) rethrows -> T {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AbakusTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    return try body(folder.appendingPathComponent("budget.sqlite"))
}

func savedAndLoaded(_ budget: Budget) throws -> Budget {
    let database = try BudgetDatabase()
    try database.save(budget, over: nil, now: Date())
    return try database.budget()
}

struct SidebarBudget {
    var budget = Budget(budgetName: "Sidebar")

    init() {
        let accounts: [(String, String, AccountKind)] = [
            ("GIRO", "Girokonto", .checking), ("SPAR", "Sparkonto", .savings), ("BAR", "Bargeld", .cash),
            ("HAUS", "Haus", .tracking),
        ]
        for (id, name, kind) in accounts {
            try! budget.apply(
                .addAccount(NewAccount(id: id, name: name, kind: kind, startingBalance: 0, startDate: october23)))
        }
    }

    func names(in group: SidebarGroup) -> [String] {
        budget.accounts(in: group).map(\.name)
    }
}

struct TestBudget {
    var budget = Budget(budgetName: "Test")
    let girokonto = "GIRO"
    let tagesgeld = "TAGES"
    let depot = "DEPOT"

    init(startingBalances: (Decimal, Decimal, Decimal) = (1000, 500, 2000)) {
        let start = date("2026-10-01")
        try! budget.apply(
            .addAccount(
                NewAccount(
                    id: girokonto, name: "Girokonto", kind: .checking,
                    startingBalance: startingBalances.0, startDate: start)))
        try! budget.apply(
            .addAccount(
                NewAccount(
                    id: tagesgeld, name: "Tagesgeld", kind: .savings,
                    startingBalance: startingBalances.1, startDate: start)))
        try! budget.apply(
            .addAccount(
                NewAccount(
                    id: depot, name: "Depot", kind: .tracking,
                    startingBalance: startingBalances.2, startDate: start)))
    }

    func category(_ master: String, _ sub: String) -> String {
        budget.categoryGroups.first { $0.name == master }!.categories.first { $0.name == sub }!.id
    }

    var groceries: String { category("Everyday Expenses", "Groceries") }

    mutating func add(
        _ accountId: String, _ amount: Decimal, on day: String = "2026-10-10", payee: String? = "REWE",
        category: String? = nil, id: String = EntityID.createUID(), cleared: ClearedStatus = .uncleared
    ) throws -> String {
        let transaction = Transaction(
            id: id, accountId: accountId, date: date(day), categoryId: category, amount: amount, cleared: cleared)
        try budget.apply(.addTransaction(transaction, payeeName: payee))
        return id
    }

    mutating func transfer(
        from: String, to: String, _ amount: Decimal, on day: String = "2026-10-12", id: String = "TR",
        category: String? = nil, memo: String? = nil
    ) throws -> String {
        let transaction = Transaction(
            id: id, accountId: from, date: date(day), categoryId: category, memo: memo, amount: amount
        ).transferring(to: to)
        try budget.apply(.addTransaction(transaction))
        return id
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
