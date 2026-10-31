import Foundation
import Testing

@testable import AbakusCore

@Suite struct ReconciliationTests {
    private func fixture() throws -> (TestBudget, [String]) {
        var fixture = TestBudget()
        let start = try #require(fixture.budget.transactions(inAccount: fixture.girokonto).first).id
        let cleared = try fixture.add(fixture.girokonto, -100, on: "2026-10-05", cleared: .cleared)
        let uncleared = try fixture.add(fixture.girokonto, -40, on: "2026-10-06")
        let later = try fixture.add(fixture.girokonto, -7, on: "2026-10-30", cleared: .cleared)
        return (fixture, [start, cleared, uncleared, later])
    }

    @Test func listHoldsUnreconciledTransactionsOnOrBeforeTheStatementDate() throws {
        var (fixture, ids) = try fixture()
        fixture.budget.setCleared(.reconciled, for: [ids[0]])
        let list = fixture.budget.reconciliationList(accountId: fixture.girokonto, through: date("2026-10-20"))
        #expect(Set(list.map(\.id)) == [ids[1], ids[2]])
    }

    @Test func differenceIsClearedPlusReconciledMinusStatement() throws {
        var (fixture, ids) = try fixture()
        fixture.budget.setCleared(.reconciled, for: [ids[0]])
        let list = fixture.budget.reconciliationList(accountId: fixture.girokonto, through: date("2026-10-20"))
        let summary = fixture.budget.reconciliationSummary(
            accountId: fixture.girokonto, statementBalance: 950, list: list)
        #expect(summary.reconciledBalance == 1000)
        #expect(summary.clearedAbove == -100)
        #expect(summary.clearedBalance == 900)
        #expect(summary.difference == -50)
        #expect(!summary.isBalanced)
    }

    @Test func finishTurnsClearedRowsOfTheListIntoReconciled() throws {
        var (fixture, ids) = try fixture()
        let statementDate = date("2026-10-20")
        let list = fixture.budget.reconciliationList(accountId: fixture.girokonto, through: statementDate)
        try fixture.budget.apply(
            .finishReconciliation(
                ReconciliationFinish(
                    accountId: fixture.girokonto, statementDate: statementDate, statementBalance: 900,
                    transactionIds: list.map(\.id), createsAdjustment: false, today: october23)))
        let budget = fixture.budget
        #expect(budget.transaction(withId: ids[0])?.cleared == .reconciled)
        #expect(budget.transaction(withId: ids[1])?.cleared == .reconciled)
        #expect(budget.transaction(withId: ids[2])?.cleared == .uncleared)
        #expect(budget.transaction(withId: ids[3])?.cleared == .cleared)
        let account = try #require(budget.account(withId: fixture.girokonto))
        #expect(account.lastReconciledAt == october23.noon())
    }

    @Test func adjustmentBringsTheAccountInLineWithTheStatement() throws {
        var (fixture, _) = try fixture()
        let statementDate = date("2026-10-20")
        let list = fixture.budget.reconciliationList(accountId: fixture.girokonto, through: statementDate)
        let before = Set(fixture.budget.transactions.map(\.id))
        try fixture.budget.apply(
            .finishReconciliation(
                ReconciliationFinish(
                    accountId: fixture.girokonto, statementDate: statementDate, statementBalance: 850,
                    transactionIds: list.map(\.id), createsAdjustment: true, today: october23)))
        let budget = fixture.budget
        let adjustment = try #require(budget.transactions.first { !before.contains($0.id) })
        #expect(adjustment.amount == -50)
        #expect(budget.payeeName(of: adjustment) == "Ausgleichsbuchung")
        #expect(adjustment.memo == "Automatisch angelegt")
        #expect(adjustment.categoryId == fixture.budget.readyToAssignCategoryId)
        #expect(adjustment.date == statementDate)
        #expect(adjustment.cleared == .reconciled)
        #expect(budget.balances(forAccount: fixture.girokonto).reconciled == 850)
    }

    @Test func adjustmentGoesToIncomeAndTrackingGetsNoCategory() throws {
        var budget = Budget(budgetName: "Test")
        try budget.apply(
            .addAccount(
                NewAccount(
                    id: "KARTE", name: "Karte", kind: .checking, startingBalance: -300,
                    startDate: october23)))
        try budget.apply(.adjustBalance(BalanceAdjustment(accountId: "KARTE", workingBalance: -350, today: october23)))
        let karte = budget.transactions(inAccount: "KARTE").last
        #expect(karte?.amount == -50)
        #expect(karte?.categoryId == budget.readyToAssignCategoryId)
        #expect(budget.payeeName(of: karte!) == "Saldoanpassung")
        var fixture = TestBudget()
        try fixture.budget.apply(
            .adjustBalance(BalanceAdjustment(accountId: fixture.depot, workingBalance: 2100, today: october23)))
        #expect(fixture.budget.transactions(inAccount: fixture.depot).last?.categoryId == nil)
    }

    @Test func adjustingToTheCurrentBalanceAddsNothing() throws {
        var fixture = TestBudget()
        let before = fixture.budget
        try fixture.budget.apply(
            .adjustBalance(BalanceAdjustment(accountId: fixture.girokonto, workingBalance: 1000, today: october23)))
        #expect(fixture.budget == before)
    }

    @Test func zeroStartingBalanceOfTodayTakesTheAmount() throws {
        var budget = Budget(budgetName: "Test")
        try budget.apply(
            .addAccount(
                NewAccount(
                    id: "NEW", name: "Neu", kind: .checking, startingBalance: 0,
                    startDate: october23)))
        try budget.apply(.adjustBalance(BalanceAdjustment(accountId: "NEW", workingBalance: 70, today: october23)))
        #expect(budget.transactions.count == 1)
        #expect(budget.transactions.first?.amount == 70)
    }

    @Test func emptyAccountGetsAStartingBalanceDatedToday() throws {
        var fixture = TestBudget()
        fixture.budget.transactions.removeAll { $0.accountId == fixture.tagesgeld }
        try fixture.budget.apply(
            .adjustBalance(BalanceAdjustment(accountId: fixture.tagesgeld, workingBalance: 300, today: october23)))
        let start = try #require(fixture.budget.transactions(inAccount: fixture.tagesgeld).first)
        #expect(fixture.budget.payeeName(of: start) == "Anfangssaldo")
        #expect(start.date == october23)
        #expect(start.memo == nil)
        #expect(start.amount == 300)
    }
}
