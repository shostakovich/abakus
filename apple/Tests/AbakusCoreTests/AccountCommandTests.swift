import Testing

@testable import AbakusCore

@Suite struct AccountCommandTests {
    @Test func newAccountGetsAStartingBalanceCategorizedAsIncome() throws {
        let fixture = TestBudget()
        let start = try #require(fixture.budget.transactions(inAccount: fixture.girokonto).first)
        #expect(start.amount == 1000)
        #expect(start.cleared == .cleared)
        #expect(start.categoryId == fixture.budget.readyToAssignCategoryId)
        #expect(fixture.budget.payeeName(of: start) == "Anfangssaldo")
        #expect(fixture.budget.payee(withId: start.payeeId!)?.hidden == true)
    }

    @Test func negativeStartingBalanceAlsoGoesToIncome() throws {
        var budget = Budget(budgetName: "Test")
        try budget.apply(
            .addAccount(
                NewAccount(
                    id: "KARTE", name: "Kreditkarte", kind: .checking, startingBalance: -300,
                    startDate: october23)))
        let start = try #require(budget.transactions.first)
        #expect(start.amount == -300)
        #expect(start.categoryId == budget.readyToAssignCategoryId)
        #expect(budget.categoryGroups.count == DefaultCategories.categoryGroups(for: .personal).count)
    }

    @Test func trackingStartingBalanceStaysUncategorized() throws {
        let fixture = TestBudget()
        #expect(fixture.budget.account(withId: fixture.depot)?.onBudget == false)
        #expect(try #require(fixture.budget.transactions(inAccount: fixture.depot).first).categoryId == nil)
    }

    @Test func everyAccountHasATransferPayee() throws {
        let fixture = TestBudget()
        let payee = try #require(fixture.budget.payee(withId: EntityID.transferPayee(accountId: fixture.tagesgeld)))
        #expect(payee.name == "Transfer : Tagesgeld")
        #expect(payee.transferAccountId == fixture.tagesgeld)
    }

    @Test(arguments: [
        ("  ", BudgetError.emptyAccountName), ("girokonto", .duplicateAccountName),
        ("Giro`2", .invalidAccountNameCharacter),
    ])
    func rejectsInvalidNames(name: String, error: BudgetError) {
        var fixture = TestBudget()
        #expect(throws: error) {
            try fixture.budget.apply(
                .addAccount(NewAccount(name: name, kind: .cash, startingBalance: 0, startDate: october23))
            )
        }
    }

    @Test func renamingUpdatesTheTransferPayee() throws {
        var fixture = TestBudget()
        var account = try #require(fixture.budget.account(withId: fixture.tagesgeld))
        account.name = " Sparbuch "
        try fixture.budget.apply(.editAccount(account))
        #expect(fixture.budget.account(withId: fixture.tagesgeld)?.name == "Sparbuch")
        #expect(
            fixture.budget.payee(withId: EntityID.transferPayee(accountId: fixture.tagesgeld))?.name
                == "Transfer : Sparbuch")
    }

    @Test func aBudgetAccountMayChangeItsTypeButNotBecomeATrackingAccount() throws {
        var fixture = TestBudget()
        var account = try #require(fixture.budget.account(withId: fixture.girokonto))
        account.kind = .cash
        try fixture.budget.apply(.editAccount(account))
        #expect(fixture.budget.account(withId: fixture.girokonto)?.kind == .cash)
        account.kind = .tracking
        #expect(throws: BudgetError.budgetStateIsFixed) { try fixture.budget.apply(.editAccount(account)) }
        var depot = try #require(fixture.budget.account(withId: fixture.depot))
        depot.kind = .savings
        #expect(throws: BudgetError.budgetStateIsFixed) { try fixture.budget.apply(.editAccount(depot)) }
    }

    @Test func closingStopsSuggestingTheTransferPayee() throws {
        var fixture = TestBudget()
        var account = try #require(fixture.budget.account(withId: fixture.tagesgeld))
        account.closed = true
        try fixture.budget.apply(.editAccount(account))
        let payee = try #require(fixture.budget.payee(withId: EntityID.transferPayee(accountId: fixture.tagesgeld)))
        #expect(!fixture.budget.isSuggested(payee))
        #expect(!payee.hidden)
    }
}
