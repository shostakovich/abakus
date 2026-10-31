import Foundation
import Testing

@testable import AbakusCore

private struct SplitFixture {
    var test = TestBudget()
    let id = "SPLIT"

    var household: String { test.category("Everyday Expenses", "Household Goods") }

    func split(_ lines: [(id: String, amount: Decimal)]) -> Transaction {
        Transaction(
            id: id, accountId: test.girokonto, date: october23, categoryId: EntityID.splitCategory,
            amount: Amount.sum(lines.map(\.amount)),
            subtransactions: lines.map { Subtransaction(id: $0.id, transactionId: id, amount: $0.amount) })
    }

    mutating func save(_ transaction: Transaction, lines: [String: String], isNew: Bool = true) throws {
        try test.budget.apply(
            .saveTransaction(
                TransactionSave(transaction: transaction, payeeName: "Kaufland", subPayeeNames: lines, isNew: isNew)))
    }

    var saved: Transaction { test.budget.transaction(withId: id)! }

    func linePayees() -> [String] {
        saved.subtransactions.map { test.budget.payeeName(of: $0) }
    }

    func payee(_ name: String) -> Payee? {
        test.budget.payee(named: name)
    }
}

@Suite struct SplitPayeeTests {
    @Test func eachLineOfASplitHasItsOwnPayee() throws {
        var fixture = SplitFixture()
        try fixture.save(fixture.split([("L1", -30), ("L2", -20)]), lines: ["L1": "Bäcker", "L2": "dm"])
        #expect(fixture.linePayees() == ["Bäcker", "dm"])
        #expect(fixture.test.budget.payeeName(of: fixture.saved) == "Kaufland")
    }

    @Test func aLineTakesAnExistingPayeeByLookupKey() throws {
        var fixture = SplitFixture()
        _ = try fixture.test.add(fixture.test.girokonto, -3, payee: "Bäckerei Müller")
        try fixture.save(fixture.split([("L1", -30), ("L2", -20)]), lines: ["L1": "BÄCKEREI müller"])
        #expect(fixture.saved.subtransactions[0].payeeId == fixture.payee("Bäckerei Müller")?.id)
        #expect(fixture.test.budget.payees.count(where: { Payee.sameName($0.name, "Bäckerei Müller") }) == 1)
    }

    @Test func linesWithoutANamedPayeeKeepTheirsAndABlankNameClearsIt() throws {
        var fixture = SplitFixture()
        try fixture.save(fixture.split([("L1", -30), ("L2", -20)]), lines: ["L1": "Bäcker", "L2": "dm"])
        try fixture.save(fixture.saved, lines: ["L2": " "], isNew: false)
        #expect(fixture.linePayees() == ["Bäcker", ""])
    }

    @Test func aLineCanStillBeATransferByName() throws {
        var fixture = SplitFixture()
        try fixture.save(fixture.split([("L1", -30), ("L2", -20)]), lines: ["L1": "Transfer : Depot"])
        let line = fixture.saved.subtransactions[0]
        #expect(line.payeeId == EntityID.transferPayee(accountId: fixture.test.depot))
        #expect(fixture.test.budget.transactions(inAccount: fixture.test.depot).contains { $0.amount == 30 })
    }

    @Test func anUnknownTransferAccountIsRefused() {
        var fixture = SplitFixture()
        #expect(throws: BudgetError.invalidTransferPayee("Transfer : Nirgends")) {
            try fixture.save(fixture.split([("L1", -30), ("L2", -20)]), lines: ["L1": "Transfer : Nirgends"])
        }
    }

    @Test func aPayeeUsedOnlyByALineIsKeptAndMergedWithIt() throws {
        var fixture = SplitFixture()
        try fixture.save(fixture.split([("L1", -30), ("L2", -20)]), lines: ["L1": "Bäcker", "L2": "dm"])
        try fixture.save(fixture.saved, lines: [:], isNew: false)
        let dm = try #require(fixture.payee("dm"))
        #expect(fixture.test.budget.payeeUseCount(dm.id) == 1)
        try fixture.test.budget.apply(.renamePayee(payeeId: dm.id, name: "Bäcker"))
        #expect(fixture.payee("dm") == nil)
        #expect(fixture.linePayees() == ["Bäcker", "Bäcker"])
    }

    @Test func aLineRemembersItsCategoryForItsPayee() throws {
        var fixture = SplitFixture()
        var split = fixture.split([("L1", -30), ("L2", -20)])
        split.subtransactions[1].categoryId = fixture.household
        try fixture.save(split, lines: ["L2": "dm"])
        #expect(
            fixture.test.budget.autoFillCategory(payeeName: "dm", accountId: fixture.test.girokonto)
                == fixture.household)
    }

    @Test func aLineWithOnlyAPayeeIsKeptAndDoesNotCollapseIntoTheTransaction() {
        let fixture = SplitFixture()
        var split = fixture.split([("L1", 0), ("L2", 0)])
        split.subtransactions[0].payeeId = "P"
        #expect(
            SplitRules.normalized(split, parentPayeeName: "", in: fixture.test.budget).subtransactions.map(\.id) == [
                "L1"
            ])
        #expect(
            SplitRules.normalized(split, parentPayeeName: "", subPayeeNames: ["L2": "dm"], in: fixture.test.budget)
                .subtransactions.count == 2)
    }

    @Test func aLinePayeeSurvivesSavingAndLoading() throws {
        var fixture = SplitFixture()
        try fixture.save(fixture.split([("L1", -30), ("L2", -20)]), lines: ["L1": "Bäcker"])
        let loaded = try savedAndLoaded(fixture.test.budget)
        let line = try #require(loaded.transaction(withId: fixture.id)?.subtransactions.first)
        #expect(loaded.payeeName(of: line) == "Bäcker")
    }
}

@Suite struct TransferCategoryTests {
    private var fixture = TestBudget()
    private var household: String { fixture.category("Everyday Expenses", "Household Goods") }

    init() throws {
        _ = try fixture.transfer(
            from: fixture.girokonto, to: fixture.depot, -100, on: "2026-10-05", id: "OLD", category: fixture.groceries)
        let split = Transaction(
            id: "SPLIT", accountId: fixture.girokonto, date: date("2026-10-08"),
            categoryId: EntityID.splitCategory, amount: -50,
            subtransactions: [
                Subtransaction(
                    id: "L1", transactionId: "SPLIT", amount: -50, categoryId: household
                ).transferring(to: fixture.depot)
            ])
        try fixture.budget.apply(.addTransaction(split, payeeName: "Mixed"))
        _ = try fixture.transfer(
            from: fixture.tagesgeld, to: fixture.depot, -10, on: "2026-10-20", id: "OTHER", category: fixture.groceries)
    }

    @Test func theNewestTransferBetweenTheTwoAccountsGivesTheCategory() {
        #expect(
            fixture.budget.lastTransferCategory(budgetAccountId: fixture.girokonto, trackingAccountId: fixture.depot)
                == household)
        #expect(
            fixture.budget.lastTransferCategory(budgetAccountId: fixture.tagesgeld, trackingAccountId: fixture.depot)
                == fixture.groceries)
    }

    @Test func aTransferWithTheTrackingAccountSuggestsIt() {
        #expect(
            fixture.budget.autoFillCategory(payeeName: "Transfer : Depot", accountId: fixture.girokonto) == household)
    }

    @Test func aTransferBetweenBudgetAccountsSuggestsNothing() {
        #expect(fixture.budget.autoFillCategory(payeeName: "Transfer : Tagesgeld", accountId: fixture.girokonto) == nil)
    }

    @Test func noEarlierTransferSuggestsNothing() {
        let fresh = TestBudget()
        #expect(fresh.budget.autoFillCategory(payeeName: "Transfer : Depot", accountId: fresh.girokonto) == nil)
    }
}
