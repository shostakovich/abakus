import Foundation
import Testing

@testable import AbakusCore

@MainActor
@Suite struct CommandMessageTests {
    private struct Field: Hashable, CustomStringConvertible {
        let table: String
        let rowId: String
        let column: String
        let value: SyncValue

        var description: String { "\(table)/\(rowId).\(column) = \(value)" }
    }

    private let now = Date(timeIntervalSince1970: 1_793_700_000.123)
    private var deletedAt: SyncValue { .text(SyncFormat.moment(now)) }
    private func messages(of command: BudgetCommand, in budget: Budget) throws -> [SyncMessage] {
        let database = try BudgetDatabase()
        try database.save(budget, over: nil, now: now.addingTimeInterval(-60))
        let store = try BudgetStore.open(database, today: { october23 }, now: { now })
        let before = try database.outbox().count
        try store.perform(command)
        #expect(!store.hasUnsavedChanges)
        return Array(try database.outbox().dropFirst(before))
    }

    private func fields(_ messages: [SyncMessage]) -> Set<Field> {
        Set(messages.map { Field(table: $0.table, rowId: $0.rowId, column: $0.column, value: $0.value) })
    }

    private func expectOneClock(_ messages: [SyncMessage]) {
        #expect(Set(messages.map(\.clock)) == [SyncClock.tick(after: nil, now: now, device: "local").description])
    }

    private func field(_ table: String, _ rowId: String, _ column: String, _ value: SyncValue) -> Field {
        Field(table: table, rowId: rowId, column: column, value: value)
    }

    @Test func savingASplitMakesTheTransactionAndItsParts() throws {
        let fixture = TestBudget()
        let household = fixture.category("Everyday Expenses", "Household Goods")
        let split = Transaction(
            id: "SPLIT", accountId: fixture.girokonto, date: date("2026-10-15"), amount: -50,
            subtransactions: [
                Subtransaction(id: "L1", transactionId: "SPLIT", amount: -30, categoryId: fixture.groceries),
                Subtransaction(id: "L2", transactionId: "SPLIT", amount: -20, categoryId: household),
            ])
        let messages = try messages(
            of: .saveTransaction(TransactionSave(transaction: split, payeeName: nil, isNew: true)), in: fixture.budget)
        expectOneClock(messages)
        #expect(
            fields(messages) == [
                field("transactions", "SPLIT", "account_id", .text(fixture.girokonto)),
                field("transactions", "SPLIT", "date", .text("2026-10-15")),
                field("transactions", "SPLIT", "amount", .integer(-5000)),
                field("transactions", "SPLIT", "cleared", .text("uncleared")),
                field("transactions", "SPLIT", "approved", .bool(true)),
                field("transactions", "SPLIT", "source", .text("manual")),
                field("subtransactions", "L1", "transaction_id", .text("SPLIT")),
                field("subtransactions", "L1", "position", .integer(0)),
                field("subtransactions", "L1", "amount", .integer(-3000)),
                field("subtransactions", "L1", "category_id", .text(fixture.groceries)),
                field("subtransactions", "L2", "transaction_id", .text("SPLIT")),
                field("subtransactions", "L2", "position", .integer(1)),
                field("subtransactions", "L2", "amount", .integer(-2000)),
                field("subtransactions", "L2", "category_id", .text(household)),
            ])
    }

    @Test func savingATransferMakesBothSides() throws {
        let fixture = TestBudget()
        let transfer = Transaction(id: "TR", accountId: fixture.girokonto, date: date("2026-10-12"), amount: -50)
            .transferring(to: fixture.tagesgeld)
        let counterpart = EntityID.transferCounterpart(of: "TR")
        let messages = try messages(
            of: .saveTransaction(TransactionSave(transaction: transfer, payeeName: nil, isNew: true)),
            in: fixture.budget)
        expectOneClock(messages)
        #expect(
            fields(messages) == [
                field("transactions", "TR", "account_id", .text(fixture.girokonto)),
                field("transactions", "TR", "date", .text("2026-10-12")),
                field("transactions", "TR", "amount", .integer(-5000)),
                field("transactions", "TR", "cleared", .text("uncleared")),
                field("transactions", "TR", "approved", .bool(true)),
                field("transactions", "TR", "source", .text("manual")),
                field("transactions", "TR", "payee_id", .text(EntityID.transferPayee(accountId: fixture.tagesgeld))),
                field("transactions", "TR", "transfer_transaction_id", .text(counterpart)),
                field("transactions", counterpart, "account_id", .text(fixture.tagesgeld)),
                field("transactions", counterpart, "date", .text("2026-10-12")),
                field("transactions", counterpart, "amount", .integer(5000)),
                field("transactions", counterpart, "cleared", .text("uncleared")),
                field("transactions", counterpart, "approved", .bool(true)),
                field("transactions", counterpart, "source", .text("manual")),
                field(
                    "transactions", counterpart, "payee_id", .text(EntityID.transferPayee(accountId: fixture.girokonto))
                ),
                field("transactions", counterpart, "transfer_transaction_id", .text("TR")),
            ])
    }

    @Test func deletingACategoryIntoAnotherLeavesATombstoneWithItsSuccessor() throws {
        var fixture = TestBudget()
        let household = fixture.category("Everyday Expenses", "Household Goods")
        let groceries = fixture.groceries
        let spent = try fixture.add(fixture.girokonto, -30, payee: nil, category: groceries, id: "SPENT")
        try fixture.budget.apply(.setAssigned(month: october23, categoryId: groceries, amount: 100))
        try fixture.budget.apply(.setAssigned(month: october23, categoryId: household, amount: 50))
        let messages = try messages(of: .deleteCategory(categoryId: groceries, into: household), in: fixture.budget)
        expectOneClock(messages)
        #expect(
            fields(messages) == [
                field("categories", groceries, "deleted_at", deletedAt),
                field("categories", groceries, "successor_id", .text(household)),
                field("transactions", spent, "category_id", .text(household)),
                field(
                    "assignments", EntityID.assignment(categoryId: groceries, month: october23), "deleted_at", deletedAt
                ),
                field(
                    "assignments", EntityID.assignment(categoryId: household, month: october23), "amount",
                    .integer(15000)),
            ])
    }

    @Test func aRestoredRowComesBackFromItsTombstone() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -30, payee: nil, category: fixture.groceries, id: "GONE")
        let gone = try #require(fixture.budget.transaction(withId: id))
        let database = try BudgetDatabase()
        try database.save(fixture.budget, over: nil, now: now.addingTimeInterval(-60))
        let store = try BudgetStore.open(database, today: { october23 }, now: { now })
        try store.perform(.deleteTransactions([id]))
        let before = try database.outbox().count
        try store.perform(.restoreTransactions([gone], payees: []))
        #expect(
            fields(Array(try database.outbox().dropFirst(before))) == [field("transactions", id, "deleted_at", .null)])
        #expect(try database.budget().transaction(withId: id) != nil)
    }

    @Test func receivedMessagesShowInTheBudget() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -30, payee: nil, category: fixture.groceries, id: "SEEN")
        let database = try BudgetDatabase()
        try database.save(fixture.budget, over: nil, now: now)
        let store = try BudgetStore.open(database, today: { october23 }, now: { now })
        try store.receive([
            SyncMessage(
                table: "transactions", rowId: id, column: "memo", value: .text("Wocheneinkauf"),
                clock: "2026-11-04T10:05:00.000Z-0000-web"),
            SyncMessage(
                table: "transactions", rowId: id, column: "memo", value: .text("Älter"),
                clock: "2026-11-04T10:00:00.000Z-0000-web"),
        ])
        #expect(store.budget.transaction(withId: id)?.memo == "Wocheneinkauf")
        try store.perform(.setCleared([id], .cleared))
        let clock = try #require(SyncClock(try database.outbox().last?.clock ?? ""))
        #expect(clock.description == "2026-11-04T10:05:00.000Z-0001-local")
    }

    @Test func assigningToASuccessorCountsWhatTheDeletedCategoryHad() throws {
        var fixture = TestBudget()
        let household = fixture.category("Everyday Expenses", "Household Goods")
        let groceries = fixture.groceries
        try fixture.budget.apply(.setAssigned(month: october23, categoryId: groceries, amount: 12))
        let database = try BudgetDatabase()
        try database.save(fixture.budget, over: nil, now: now)
        let store = try BudgetStore.open(database, today: { october23 }, now: { now })
        let web = "2026-11-04T10:00:00.000Z-0000-web"
        try store.receive([
            SyncMessage(table: "categories", rowId: groceries, column: "deleted_at", value: deletedAt, clock: web),
            SyncMessage(
                table: "categories", rowId: groceries, column: "successor_id", value: .text(household), clock: web),
        ])
        #expect(store.budget.assigned(in: october23, categoryId: household) == 12)
        let before = try database.outbox().count
        try store.perform(.setAssigned(month: october23, categoryId: household, amount: 20))
        #expect(
            fields(Array(try database.outbox().dropFirst(before))) == [
                field(
                    "assignments", EntityID.assignment(categoryId: household, month: october23), "category_id",
                    .text(household)),
                field(
                    "assignments", EntityID.assignment(categoryId: household, month: october23), "month",
                    .text("2026-10-01")),
                field(
                    "assignments", EntityID.assignment(categoryId: household, month: october23), "amount", .integer(800)
                ),
            ])
        #expect(store.budget.budgetSheet(today: october23).month(october23)?.category(household)?.assigned == 20)
    }
}
