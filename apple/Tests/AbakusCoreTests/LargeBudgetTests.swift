import Foundation
import Testing

@testable import AbakusCore

@MainActor
@Suite struct LargeBudgetTests {
    static func largeBudget(transactions count: Int) -> Budget {
        var budget = TestBudget().budget
        let category = budget.budgetCategoryGroups[0].categories[0].id
        let account = budget.accounts[0].id
        let payee = Payee(name: "Rewe")
        budget.payees.append(payee)
        for index in 0..<count {
            budget.transactions.append(
                Transaction(
                    accountId: account, date: date("2024-01-01").addingDays(index % 1000), payeeId: payee.id,
                    categoryId: category, memo: "Einkauf \(index)", amount: -Decimal(index % 97 + 1)))
        }
        return budget
    }

    @Test func aCommandOnTwentyThousandTransactionsStaysResponsive() throws {
        let database = try BudgetDatabase()
        var snapshot = SyncSnapshot(of: Self.largeBudget(transactions: 20_000))
        for (table, rows) in snapshot.tables {
            snapshot.tables[table] = rows.enumerated().map { index, row in
                var clocked = row
                let clock = "2026-10-01T10:00:00.\(String(format: "%03d", index % 1000))Z-0000-server"
                clocked.clocks = row.fields.mapValues { _ in clock }
                return clocked
            }
        }
        try database.adopt(
            snapshot, deviceId: "mac-1", serverURL: FakeAbakus.url, settings: LocalBudgetSettings(budgetName: ""))
        let store = try BudgetStore.open(database, today: { october23 })
        let id = store.budget.transactions[10_000].id

        let start = Date()
        try store.perform(.setCleared([id], .cleared))
        let elapsed = Date().timeIntervalSince(start)

        #expect(try database.outbox().last?.rowId == id)
        #expect(try database.fieldClocks().count > 200_000)
        #expect(elapsed < 0.15, "a command took \(elapsed) s")
    }
}
