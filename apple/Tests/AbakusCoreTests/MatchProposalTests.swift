import Foundation
import Testing

@testable import AbakusCore

@MainActor
@Suite struct MatchProposalTests {
    private let clock = "2026-11-04T10:00:00.000Z-0000-server"

    private func proposal(for targetId: String, in fixture: TestBudget, amount: Int = -4210) -> [SyncMessage] {
        func field(_ table: String, _ id: String, _ column: String, _ value: SyncValue) -> SyncMessage {
            SyncMessage(table: table, rowId: id, column: column, value: value, clock: clock)
        }
        return [
            field("payees", "BANK-PAYEE", "name", .text("REWE SAGT DANKE")),
            field("transactions", "BANK", "account_id", .text(fixture.girokonto)),
            field("transactions", "BANK", "date", .text("2026-10-10")),
            field("transactions", "BANK", "amount", .integer(amount)),
            field("transactions", "BANK", "payee_id", .text("BANK-PAYEE")),
            field("transactions", "BANK", "category_id", .text(fixture.groceries)),
            field("transactions", "BANK", "source", .text("bank")),
            field("transactions", "BANK", "matched_transaction_id", .text(targetId)),
        ]
    }

    private func synced(_ fixture: TestBudget, target: String) throws -> (BudgetStore, BudgetDatabase) {
        let database = try BudgetDatabase()
        try database.save(fixture.budget, over: nil, now: Date())
        let store = try BudgetStore.open(database, today: { october23 })
        try store.receive(proposal(for: target, in: fixture))
        return (store, database)
    }

    private func outbox(of store: BudgetStore, in database: BudgetDatabase, after command: BudgetCommand) throws
        -> [SyncMessage]
    {
        let before = try database.outbox().count
        try store.perform(command)
        return Array(try database.outbox().dropFirst(before))
    }

    @Test func aProposalCountsNowhere() throws {
        var fixture = TestBudget()
        let rewe = try fixture.add(fixture.girokonto, -42.10, payee: "Rewe", category: fixture.groceries)
        let (store, _) = try synced(fixture, target: rewe)
        let budget = store.budget
        #expect(budget.transactions.map(\.id).contains(rewe))
        #expect(budget.transaction(withId: "BANK") == nil)
        #expect(budget.matchProposals.map(\.id) == ["BANK"])
        #expect(budget.balances(forAccount: fixture.girokonto).working == decimal("957.90"))
        let groceries = budget.budgetSheet(today: october23).month(october23)?.category(fixture.groceries)
        #expect(groceries?.outflows == decimal("-42.10"))
        #expect(budget.payeeUseCount("BANK-PAYEE") == 0)
    }

    @Test func savingAfterSyncingWritesNothingForTheProposal() throws {
        var fixture = TestBudget()
        let rewe = try fixture.add(fixture.girokonto, -42.10, payee: "Rewe")
        let (store, database) = try synced(fixture, target: rewe)
        let messages = try outbox(of: store, in: database, after: .setCleared([rewe], .cleared))
        #expect(messages.map(\.rowId) == [rewe])
        #expect(try database.budget().matchProposals == store.budget.matchProposals)
    }

    @Test func deletingTheTargetLeavesTheProposalAndItsPayee() throws {
        var fixture = TestBudget()
        let rewe = try fixture.add(fixture.girokonto, -42.10, payee: "Rewe")
        let (store, database) = try synced(fixture, target: rewe)
        let messages = try outbox(of: store, in: database, after: .deleteTransactions([rewe]))
        #expect(!messages.contains { $0.rowId == "BANK" || $0.rowId == "BANK-PAYEE" })
        #expect(store.budget.matchProposals.map(\.id) == ["BANK"])
        #expect(store.budget.payee(withId: "BANK-PAYEE") != nil)
    }

    @Test func aProposalKeepsItsPartsInTheRows() {
        let fixture = TestBudget()
        let proposal = Transaction(
            id: "BANK", accountId: fixture.girokonto, date: october23, amount: -10, source: .bank,
            matchedTransactionId: "REWE",
            subtransactions: [Subtransaction(id: "P1", transactionId: "BANK", amount: -10)])
        let budget = Budget(budgetName: "Test", accounts: fixture.budget.accounts, transactions: [proposal])
        #expect(budget.transactions.isEmpty)
        #expect(budget.syncedRows["transactions"]?["BANK"] != nil)
        #expect(budget.syncedRows["subtransactions"]?["P1"] != nil)
        let loaded = Budget(syncedRows: budget.syncedRows, local: budget.localSettings)
        #expect(loaded.matchProposals == [proposal])
    }
}
