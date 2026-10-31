import Testing

@testable import AbakusCore

@Suite struct DemoBudgetTests {
    let budget = DemoBudget.make(today: october23)

    private func account(_ name: String) -> Account { budget.account(named: name)! }

    private func category(_ fullName: String) throws -> Category {
        try #require(budget.category(fullName: fullName))
    }

    @Test func hasTheDemoNameAndGermanCategories() {
        #expect(budget.budgetName == "Demo-Budget")
        #expect(
            budget.budgetCategoryGroups.map(\.name) == ["🏠 Wohnen", "🛒 Alltag", "🛟 Rücklagen", "🎯 Sparziele"])
        #expect(budget.category(fullName: "🛒 Alltag: 🛒 Lebensmittel") != nil)
        #expect(budget.category(withId: budget.readyToAssignCategoryId)?.isInternal == true)
    }

    @Test func hasEveryAccountKind() {
        #expect(Set(budget.accounts.map(\.kind)) == [.checking, .savings, .cash, .tracking])
    }

    @Test func accountsLandInTheirSidebarGroups() {
        #expect(
            budget.accounts(in: .budgetAccounts).map(\.name) == [
                "Girokonto", "Tagesgeld", "Kreditkarte", "Bargeld",
            ])
        #expect(budget.accounts(in: .offBudgetAccounts).map(\.name) == ["Depot", "Bausparvertrag"])
        #expect(budget.accounts(in: .closedAccounts).map(\.name) == ["Altes Sparbuch"])
    }

    @Test func kreditkarteIsOverdrawn() {
        #expect(budget.balances(forAccount: account("Kreditkarte").id).working < 0)
        #expect(budget.balances(forAccount: account("Altes Sparbuch").id).working == 0)
    }

    @Test func coversThreeMonthsUpToToday() {
        let dates = budget.transactions.map(\.date)
        #expect(dates.max()! <= october23)
        #expect(dates.min()! == october23.addingMonths(-3))
        #expect(budget.transactions.count > 60)
    }

    @Test func containsEveryKindOfRow() {
        #expect(budget.transactions.contains { budget.isTransfer($0) })
        #expect(budget.transactions.contains { $0.isSplit })
        for status in ClearedStatus.allCases {
            #expect(budget.transactions.contains { $0.cleared == status })
        }
        #expect(budget.transactions.count { !$0.approved } == 1)
        let uncategorized = budget.transactions.filter { budget.errorState(of: $0).level == .needsCategory }
        #expect(uncategorized.count == 1)
        #expect(budget.scheduledTransactions.count == 2)
        #expect(budget.scheduledTransactions.allSatisfy { $0.nextDate > october23 })
    }

    @Test func transfersAreLinkedBothWays() {
        for transaction in budget.transactions where budget.isTransfer(transaction) {
            let counterpart = budget.transaction(withId: transaction.transferTransactionId ?? "")
            #expect(counterpart?.transferTransactionId == transaction.id)
            #expect(counterpart?.amount == -transaction.amount)
        }
    }

    @Test func budgetsSeveralMonthsAndLeavesMoneyToBudget() throws {
        let sheet = budget.budgetSheet(today: october23)
        let october = try #require(sheet.month(october23))
        #expect(Set(budget.assignments.map(\.month)) == Set((0...4).map { date("2026-07-01").addingMonths($0) }))
        #expect(october.available > 0 && !october.isOverassigned)
        #expect(october.assignedInFuture == 950)
        #expect(sheet.month(date("2026-09-01"))?.income == 3180 + 4.12)
    }

    @Test func showsAnOverspending() throws {
        let sheet = budget.budgetSheet(today: october23)
        let october = try #require(sheet.month(october23))
        let rent = try category("🏠 Wohnen: 🏠 Miete")
        let overspent = sheet.categoryGroups.flatMap(\.categories).filter {
            october.category($0.id)?.isOverspent == true
        }
        #expect(overspent.map(\.id) == [rent.id])
    }

    @Test func showsEveryTargetStatus() throws {
        let october = try #require(budget.budgetSheet(today: october23).month(october23))
        let states = try [
            "🏠 Wohnen: 🏠 Miete", "🛒 Alltag: 🛒 Lebensmittel", "🛒 Alltag: ⛽ Tanken", "🛟 Rücklagen: 🎄 Weihnachten",
            "🛟 Rücklagen: 🛟 Notgroschen", "🎯 Sparziele: 🏖️ Urlaub",
        ].map { name in
            let figures = try #require(october.category(try category(name).id))
            return german.targetStatus(figures, month: october23)?.state
        }
        #expect(states == [.overspent, .met, .met, .underfunded, .onTrack, .snoozed])
    }

    @Test(arguments: ["2026-01-01", "2024-02-29", "2026-03-31", "2026-12-31"])
    func buildsForAnyToday(today: String) throws {
        let budget = DemoBudget.make(today: date(today))
        #expect(budget.accounts.count == 7)
        #expect(budget.transactions.allSatisfy { $0.date <= date(today) })
        #expect(budget.transactions.count { !$0.approved } == 1)
        let month = try #require(budget.budgetSheet(today: date(today)).month(date(today)))
        #expect(month.available > 0)
        let rent = try #require(budget.category(fullName: "🏠 Wohnen: 🏠 Miete"))
        #expect(month.category(rent.id)?.isOverspent == true)
    }
}
