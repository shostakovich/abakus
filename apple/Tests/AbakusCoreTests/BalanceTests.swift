import Testing

@testable import AbakusCore

@Suite struct BalanceTests {
    @Test func splitsBalancesByClearedState() throws {
        var fixture = TestBudget()
        _ = try fixture.add(fixture.girokonto, -100, cleared: .cleared)
        _ = try fixture.add(fixture.girokonto, -20.5, cleared: .uncleared)
        _ = try fixture.add(fixture.girokonto, -30, cleared: .reconciled)
        let balances = fixture.budget.balances(forAccount: fixture.girokonto)
        #expect(balances.cleared == 870)
        #expect(balances.uncleared == decimal("-20.5"))
        #expect(balances.reconciled == -30)
        #expect(balances.working == decimal("849.5"))
    }

    @Test func balanceThroughDateIgnoresLaterTransactions() throws {
        var fixture = TestBudget()
        _ = try fixture.add(fixture.girokonto, -100, on: "2026-10-05")
        _ = try fixture.add(fixture.girokonto, -50, on: "2026-11-05")
        #expect(fixture.budget.balances(forAccount: fixture.girokonto, through: date("2026-10-31")).working == 900)
        #expect(fixture.budget.balances(forAccount: fixture.girokonto).working == 850)
    }

    @Test func allAccountsCoversEveryAccount() {
        let fixture = TestBudget()
        #expect(fixture.budget.balances(forAccount: EntityID.allAccounts).working == 3500)
    }

    @Test func scheduledTransactionsDoNotCount() {
        var fixture = TestBudget()
        fixture.budget.scheduledTransactions.append(
            ScheduledTransaction(accountId: fixture.girokonto, nextDate: date("2026-10-30"), amount: -500))
        #expect(fixture.budget.balances(forAccount: fixture.girokonto).working == 1000)
    }

    @Test func sidebarGroupsSplitByBudgetAndClosedState() throws {
        var fixture = TestBudget()
        var tagesgeld = try #require(fixture.budget.account(withId: fixture.tagesgeld))
        tagesgeld.closed = true
        try fixture.budget.apply(.editAccount(tagesgeld))
        #expect(fixture.budget.accounts(in: .budgetAccounts).map(\.name) == ["Girokonto"])
        #expect(fixture.budget.accounts(in: .offBudgetAccounts).map(\.name) == ["Depot"])
        #expect(fixture.budget.accounts(in: .closedAccounts).map(\.name) == ["Tagesgeld"])
    }

    @Test func groupsFollowSortableIndex() throws {
        var fixture = TestBudget()
        var girokonto = try #require(fixture.budget.account(withId: fixture.girokonto))
        girokonto.position = 99
        try fixture.budget.apply(.editAccount(girokonto))
        #expect(fixture.budget.accounts(in: .budgetAccounts).map(\.name) == ["Tagesgeld", "Girokonto"])
    }
}

@Suite struct OrderingTests {
    @Test func ordersByDateThenInflowsFirst() throws {
        var fixture = TestBudget()
        let outflow = try fixture.add(fixture.girokonto, -10, on: "2026-10-10")
        let inflow = try fixture.add(
            fixture.girokonto, 20, on: "2026-10-10", category: fixture.budget.readyToAssignCategoryId)
        let earlier = try fixture.add(fixture.girokonto, -5, on: "2026-10-02")
        let ids = fixture.budget.transactionsInDefaultOrder(forAccount: fixture.girokonto).map(\.id)
        #expect(Array(ids.dropFirst()) == [earlier, inflow, outflow])
    }

    @Test func breaksTiesByPayeeThenClearedState() throws {
        var fixture = TestBudget()
        let zebra = try fixture.add(fixture.girokonto, -10, payee: "Zebra")
        let alpha = try fixture.add(fixture.girokonto, -10, payee: "alpha")
        let alphaReconciled = try fixture.add(fixture.girokonto, -10, payee: "Alpha", cleared: .reconciled)
        let ids = fixture.budget.transactionsInDefaultOrder(forAccount: fixture.girokonto).map(\.id)
        #expect(Array(ids.dropFirst()) == [alphaReconciled, alpha, zebra])
    }

    @Test func runningBalanceAccumulatesInDefaultOrder() throws {
        var fixture = TestBudget()
        let later = try fixture.add(fixture.girokonto, -100, on: "2026-10-20")
        let earlier = try fixture.add(fixture.girokonto, decimal("-0.5"), on: "2026-10-05")
        let running = fixture.budget.runningBalances(forAccount: fixture.girokonto)
        #expect(running[earlier] == decimal("999.5"))
        #expect(running[later] == decimal("899.5"))
    }

    @Test func allAccountsRunningBalanceSpansAccounts() {
        let fixture = TestBudget()
        let running = fixture.budget.runningBalances(forAccount: EntityID.allAccounts)
        #expect(running.count == 3)
        #expect(running.values.max() == 3500)
    }
}

@Suite struct ErrorStateTests {
    @Test func uncategorizedOnBudgetTransactionNeedsCategory() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10)
        let state = fixture.budget.errorState(of: try #require(fixture.budget.transaction(withId: id)))
        #expect(state.level == .needsCategory)
        #expect(state.message == ErrorMessages.needsCategory)
    }

    @Test func zeroAmountsAndOffBudgetAccountsNeedNoCategory() throws {
        var fixture = TestBudget()
        let zero = try fixture.add(fixture.girokonto, 0)
        let offBudget = try fixture.add(fixture.depot, -10)
        #expect(fixture.budget.errorState(of: fixture.budget.transaction(withId: zero)!).level == .none)
        #expect(fixture.budget.errorState(of: fixture.budget.transaction(withId: offBudget)!).level == .none)
    }

    @Test func onBudgetTransfersMustStayUncategorized() throws {
        var fixture = TestBudget()
        let plain = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -50, id: "PLAIN")
        let categorized = try fixture.transfer(
            from: fixture.girokonto, to: fixture.tagesgeld, -50, id: "CAT", category: fixture.groceries)
        #expect(fixture.budget.errorState(of: fixture.budget.transaction(withId: plain)!).level == .none)
        #expect(fixture.budget.errorState(of: fixture.budget.transaction(withId: categorized)!).level == .error)
    }

    @Test func transfersToOffBudgetNeedACategoryOnTheBudgetSide() throws {
        var fixture = TestBudget()
        let id = try fixture.transfer(from: fixture.girokonto, to: fixture.depot, -50)
        let source = try #require(fixture.budget.transaction(withId: id))
        let counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR")))
        #expect(fixture.budget.errorState(of: source).message == ErrorMessages.offBudgetTransferNeedsCategory)
        #expect(fixture.budget.errorState(of: counterpart).level == .none)
    }

    @Test func splitAggregatesItsLines() throws {
        var fixture = TestBudget()
        let parent = Transaction(
            id: "SPLIT", accountId: fixture.girokonto, date: october23, amount: -30,
            subtransactions: [
                Subtransaction(transactionId: "SPLIT", amount: -10, categoryId: fixture.groceries),
                Subtransaction(transactionId: "SPLIT", amount: -20),
            ])
        try fixture.budget.apply(.addTransaction(parent, payeeName: "Kaufland"))
        let state = fixture.budget.errorState(of: try #require(fixture.budget.transaction(withId: "SPLIT")))
        #expect(state.level == .needsCategory)
        #expect(state.message == ErrorMessages.splitPrefix + "\t- " + ErrorMessages.needsCategory + "\n\n")
    }

    @Test func unapprovedSchedulerEntriesNeedReview() throws {
        var fixture = TestBudget()
        let entered = Transaction(
            accountId: fixture.depot, date: october23, amount: -10, approved: false,
            source: .scheduled)
        try fixture.budget.apply(.addTransaction(entered))
        #expect(fixture.budget.errorState(of: entered).message == ErrorMessages.enteredByScheduler)
        #expect(
            fixture.budget.errorSummary(forAccount: fixture.depot)
                == AccountErrorSummary(count: 1, maxLevel: .forReview))
    }

    @Test func accountSummaryCountsRowsWithAnyError() throws {
        var fixture = TestBudget()
        _ = try fixture.add(fixture.girokonto, -10)
        _ = try fixture.add(fixture.girokonto, -20, category: fixture.groceries)
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -5, category: fixture.groceries)
        let summary = fixture.budget.errorSummary(forAccount: fixture.girokonto)
        #expect(summary == AccountErrorSummary(count: 2, maxLevel: .error))
    }

    @Test func needsCategoryOutranksReviewForTheAccountBadge() throws {
        var fixture = TestBudget()
        _ = try fixture.add(fixture.girokonto, -10)
        let review = Transaction(
            accountId: fixture.girokonto, date: october23, categoryId: fixture.groceries, amount: -5, approved: false,
            source: .scheduled)
        try fixture.budget.apply(.addTransaction(review))
        #expect(fixture.budget.errorSummary(forAccount: fixture.girokonto).maxLevel == .needsCategory)
        #expect(fixture.budget.errorSummary(for: .budgetAccounts).count == 2)
    }
}
