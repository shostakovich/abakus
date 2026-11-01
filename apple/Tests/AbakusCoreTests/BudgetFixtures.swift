import Foundation

@testable import AbakusCore

let october24 = date("2026-10-24")
let german = BudgetFormatter()

/// The common background of the worked budget examples: Giro, "Alltag" (Lebensmittel, Kleidung) and "Sparen"
/// (Notgroschen), and 1.000,00 income on 2026-10-01.
struct ScenarioBudget {
    static let giro = "GIRO"
    static let alltag = "ALLTAG"
    static let sparen = "SPAREN"
    static let lebensmittel = "LEBENSMITTEL"
    static let kleidung = "KLEIDUNG"
    static let notgroschen = "NOTGROSCHEN"
    static let readyToAssign = "READY"

    var budget: Budget
    var today = october24

    init(
        income: Decimal? = 1000, masters: [(id: String, name: String, subs: [(id: String, name: String)])]? = nil,
        start: String = "2026-10-01"
    ) {
        let layout =
            masters ?? [
                (Self.alltag, "Alltag", [(Self.lebensmittel, "Lebensmittel"), (Self.kleidung, "Kleidung")]),
                (Self.sparen, "Sparen", [(Self.notgroschen, "Notgroschen")]),
            ]
        let userMasters = layout.enumerated().map { index, master in
            CategoryGroup(
                id: master.id, name: master.name, position: index,
                categories: master.subs.enumerated().map { subIndex, sub in
                    Category(id: sub.id, categoryGroupId: master.id, name: sub.name, position: subIndex)
                })
        }
        budget = Budget(
            budgetName: "Szenario",
            categoryGroups: [DefaultCategories.internalGroup(id: "INTERNAL", readyToAssignId: Self.readyToAssign)]
                + userMasters)
        try! budget.apply(
            .addAccount(
                NewAccount(
                    id: Self.giro, name: "Giro", kind: .checking, startingBalance: 0,
                    startDate: date(start))))
        if let income {
            try! add(income, on: "2026-10-01", category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        }
    }

    @discardableResult
    mutating func add(
        _ amount: Decimal, on day: String, category: String?, payee: String = "Laden",
        account: String = ScenarioBudget.giro,
        id: String = EntityID.createUID(), memo: String? = nil
    ) throws -> String {
        let transaction = Transaction(
            id: id, accountId: account, date: date(day), categoryId: category, memo: memo, amount: amount)
        try budget.apply(.addTransaction(transaction, payeeName: payee))
        return id
    }

    @discardableResult
    mutating func split(
        _ lines: [(Decimal, String?)], on day: String, payee: String, id: String = EntityID.createUID(),
        memo: String? = nil
    ) throws -> String {
        let subs = lines.map { Subtransaction(transactionId: id, amount: $0.0, categoryId: $0.1) }
        let transaction = Transaction(
            id: id, accountId: Self.giro, date: date(day), memo: memo, amount: Amount.sum(lines.map(\.0)),
            subtransactions: subs)
        try budget.apply(.addTransaction(transaction, payeeName: payee))
        return id
    }

    mutating func budget(_ amount: Decimal, _ category: String, in month: String) throws {
        try budget.apply(.setAssigned(month: date(month), categoryId: category, amount: amount))
    }

    var sheet: BudgetSheet { budget.budgetSheet(today: today) }

    func month(_ day: String) -> BudgetMonth { sheet.month(date(day))! }

    /// Scenario B: A plus Kleidung 50,00 assigned and overspent by 30,00.
    static func scenarioB() throws -> ScenarioBudget {
        var scenario = ScenarioBudget()
        try scenario.budget(300, lebensmittel, in: "2026-10-01")
        try scenario.add(-120, on: "2026-10-05", category: lebensmittel)
        try scenario.budget(50, kleidung, in: "2026-10-01")
        try scenario.add(-80, on: "2026-10-12", category: kleidung)
        return scenario
    }
}

extension BudgetMonth {
    /// The header as the screen reads it: the four lines, then "= amount" and its label.
    var headerText: [String] {
        headerLines(formatter: german).map { "\($0.amount) \($0.text)" }
            + ["= \(german.currency(available))", resultLabel]
    }

    var totalsText: [String] {
        [german.currency(assigned), german.currency(outflows), german.currency(balance)]
    }

    func masterText(_ id: String) -> [String] {
        guard let figures = master(id) else { return [] }
        return [
            german.currencyNoSymbol(figures.assigned),
            german.budgetAmount(figures.outflows, prefix: "+", prefixZero: false),
            german.currencyNoSymbol(figures.balance),
        ]
    }

    func rowText(_ id: String) -> [String] {
        guard let figures = category(id) else { return [] }
        return [
            figures.assigned != 0 ? german.currencyNoSymbol(figures.assigned) : "",
            figures.spent != 0 || figures.hasTransactions
                ? german.budgetAmount(figures.outflows, prefix: "+", prefixZero: false) : "",
            figures.balance != 0 || figures.hasTransactions ? german.currencyNoSymbol(figures.balance) : "",
        ]
    }
}

extension Budget {
    func monthRange(today: DateWithoutTime, including extra: [DateWithoutTime] = []) -> [DateWithoutTime] {
        monthIndexRange(today: today, including: extra).map(DateWithoutTime.init(monthIndex:))
    }

    func autoFillCategory(payeeName: String, accountId: String) -> String? {
        autoFill(payeeName: payeeName, accountId: accountId, settings: AutoFillSettings())?.categoryId
    }
}
