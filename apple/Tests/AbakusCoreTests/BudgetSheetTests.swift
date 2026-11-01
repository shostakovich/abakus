import Foundation
import Testing

@testable import AbakusCore

@Suite struct BudgetSheetTests {
    typealias S = ScenarioBudget

    @Test func rangeCoversThirteenMonthsAroundTodayAndEveryTransaction() throws {
        var scenario = ScenarioBudget()
        #expect(scenario.budget.monthRange(today: october24).first == date("2025-09-01"))
        #expect(scenario.budget.monthRange(today: october24).last == date("2027-11-01"))
        try scenario.add(-5, on: "1999-03-15", category: S.lebensmittel)
        try scenario.add(-5, on: "2040-06-15", category: S.lebensmittel)
        try scenario.budget(10, S.notgroschen, in: "2045-01-01")
        let range = scenario.budget.monthRange(today: october24)
        #expect(range.first == date("1999-02-01"))
        #expect(range.last == date("2045-01-01"))
        #expect(zip(range, range.dropFirst()).allSatisfy { $0.addingMonths(1) == $1 })
        #expect(
            scenario.budget.monthRange(today: october24, including: [date("2050-05-17")]).last == date("2050-05-01"))
        #expect(scenario.sheet.month(date("2040-06-01"))?.category(S.lebensmittel)?.spent == 5)
    }

    @Test func registerBalancesMatchTheSheetWithoutBuildingFarMonths() throws {
        var scenario = ScenarioBudget()
        try scenario.add(-5, on: "1026-03-15", category: S.lebensmittel)
        try scenario.add(-7, on: "2602-06-15", category: S.kleidung)
        try scenario.add(-40, on: "2026-06-15", category: S.kleidung)
        try scenario.add(-30, on: "2026-05-10", category: S.notgroschen)
        try scenario.budget(10, S.notgroschen, in: "2026-08-01")
        try scenario.budget(10, S.kleidung, in: "2400-01-01")
        let expected = try #require(scenario.sheet.month(october24)).categories.mapValues(\.balance)
        var balances: [String: Decimal] = [:]
        let elapsed = ContinuousClock().measure {
            for _ in 0..<20 { balances = scenario.budget.categoryBalances(today: october24) }
        }
        #expect(balances == expected)
        #expect(balances[S.notgroschen] == 10)
        #expect(elapsed < .seconds(1))
    }

    @Test func theFirstMonthWithDataIsTheFirstWithRealData() throws {
        var scenario = ScenarioBudget(income: nil)
        #expect(scenario.sheet.firstMonthWithData == nil)
        try scenario.budget(10, S.kleidung, in: "2026-08-01")
        #expect(scenario.sheet.firstMonthWithData == date("2026-08-01"))
        try scenario.add(-3, on: "2026-03-15", category: S.lebensmittel)
        #expect(scenario.sheet.firstMonthWithData == date("2026-03-01"))
    }

    @Test func monthsAreTimedAgainstToday() {
        let sheet = ScenarioBudget().sheet
        #expect(sheet.month(date("2026-09-30"))?.timing == .past)
        #expect(sheet.month(date("2026-10-01"))?.timing == .current)
        #expect(sheet.month(date("2026-11-01"))?.timing == .future)
        #expect(sheet.month(date("2026-12-01"))?.timing == .future)
        #expect(sheet.month(date("2020-01-01")) == nil)
    }

    @Test func theFirstMonthTakesItsMissingPreviousMonthAsZero() throws {
        var scenario = ScenarioBudget()
        try scenario.budget(-50, S.kleidung, in: "2025-09-01")
        let first = try #require(scenario.sheet.months.first)
        #expect(first.month == date("2025-09-01"))
        #expect(
            first.headerText == [
                "0,00 Nicht verteilt im Aug", "0,00 Überzogen im Aug", "0,00 Einnahmen im Sep",
                "+50,00 Zugewiesen im Sep", "= 50,00€", "Nicht verteilt am Monatsende",
            ])
        #expect(scenario.sheet.quickBudgetAmount(.assignedLastMonth, categoryId: S.kleidung, month: first.month) == 0)
    }

    @Test func aClosedMonthThatAssignedTooMuchSaysSoAndTheNextMonthWarns() throws {
        var scenario = ScenarioBudget(income: nil)
        try scenario.budget(100, S.kleidung, in: "2025-09-01")
        let september = scenario.month("2025-09-01")
        #expect(september.isClosed && september.resultLabel == "Zu viel verteilt")
        let october = scenario.month("2025-10-01").headerLines(formatter: german)
        #expect(october[0].text == "Nicht verteilt im Sep" && october[0].isWarning)
        #expect(!october[1].isWarning)
    }

    @Test func onlyOnBudgetActivityCountsAndFutureOrUnapprovedTransactionsDo() throws {
        var scenario = ScenarioBudget()
        try scenario.budget.apply(
            .addAccount(
                NewAccount(
                    id: "DEPOT", name: "Depot", kind: .tracking, startingBalance: 0,
                    startDate: date("2026-10-01"))))
        try scenario.add(-99, on: "2026-10-03", category: S.lebensmittel, account: "DEPOT")
        try scenario.add(50, on: "2026-10-03", category: ScenarioBudget.readyToAssign, account: "DEPOT")
        try scenario.add(-20, on: "2026-12-24", category: S.lebensmittel)
        let unapproved = Transaction(
            accountId: S.giro, date: date("2026-10-08"), categoryId: S.kleidung, amount: -15, approved: false,
            source: .bank)
        try scenario.budget.apply(.addTransaction(unapproved, payeeName: "Bank"))
        let sheet = scenario.sheet
        #expect(sheet.month(date("2026-10-01"))?.category(S.lebensmittel)?.spent == 0)
        #expect(sheet.month(date("2026-10-01"))?.income == 1000)
        #expect(sheet.month(date("2026-10-01"))?.category(S.kleidung)?.spent == 15)
        #expect(sheet.month(date("2026-12-01"))?.category(S.lebensmittel)?.spent == 20)
    }

    @Test func refundsAreNegativeOutflowsShownWithAPlus() throws {
        var scenario = ScenarioBudget()
        try scenario.add(20, on: "2026-10-09", category: S.kleidung)
        let october = scenario.month("2026-10-01")
        #expect(october.category(S.kleidung)?.spent == -20)
        #expect(october.rowText(S.kleidung) == ["", "+20,00", "20,00"])
        #expect(october.masterText(S.alltag) == ["0,00", "+20,00", "20,00"])
        #expect(october.totalsText[1] == "20,00€")
    }

    @Test func zeroBalancesAfterActivityShowAndUntouchedCategoriesStayBlank() throws {
        var scenario = ScenarioBudget()
        try scenario.budget(25, S.kleidung, in: "2026-10-01")
        try scenario.add(-25, on: "2026-10-09", category: S.kleidung)
        let october = scenario.month("2026-10-01")
        #expect(october.rowText(S.kleidung) == ["25,00", "-25,00", "0,00"])
        #expect(october.rowText(S.notgroschen) == ["", "", ""])
        #expect(october.category(S.notgroschen)?.hasTransactions == false)
    }

    @Test func uncategorizedTransactionsFollowTheirOwnFilter() throws {
        var scenario = ScenarioBudget()
        try scenario.budget.apply(
            .addAccount(
                NewAccount(
                    id: "SPAR", name: "Sparkonto", kind: .savings, startingBalance: 0,
                    startDate: date("2026-10-01"))))
        let transfer = Transaction(
            accountId: S.giro, date: date("2026-10-02"), amount: -200
        ).transferring(to: "SPAR")
        try scenario.budget.apply(.addTransaction(transfer))
        try scenario.add(0, on: "2026-10-03", category: nil)
        #expect(!scenario.sheet.showsUncategorizedRow)
        try scenario.add(100, on: "2026-10-04", category: nil)
        try scenario.split([(-30, S.kleidung), (-12, nil)], on: "2026-10-06", payee: "Markt")
        let sheet = scenario.sheet
        #expect(sheet.showsUncategorizedRow)
        let october = try #require(sheet.month(date("2026-10-01")))
        #expect(october.uncategorized.spent == -88)
        #expect(october.uncategorized.balance == 88)
        #expect(october.uncategorized.transactionCount == 2)
        #expect(october.available == 1000)
        #expect(sheet.month(date("2026-11-01"))?.uncategorized.balance == 88)
    }

    @Test func masterAndMonthCountsAreDistinctTransactions() throws {
        var scenario = ScenarioBudget()
        try scenario.split([(-70, S.lebensmittel), (-30, S.kleidung)], on: "2026-10-15", payee: "Kaufhaus")
        try scenario.add(-10, on: "2026-10-16", category: S.notgroschen)
        let october = scenario.month("2026-10-01")
        #expect(october.master(S.alltag)?.transactionCount == 1)
        #expect(october.category(S.lebensmittel)?.transactionCount == 1)
        #expect(october.transactionCount == 2)
        #expect(october.hasTransactions)
        #expect(!scenario.month("2026-11-01").hasTransactions)
    }

    /// Category balances and Zu verteilen before what later months assign add up to the money.
    @Test func everyMonthOfTheDemoBudgetBalancesWithTheAccounts() {
        let budget = DemoBudget.make(today: october23)
        let onBudget = Set(budget.accounts.filter(\.onBudget).map(\.id))
        for month in budget.budgetSheet(today: october23).months {
            let money = Amount.sum(
                budget.transactions.filter { onBudget.contains($0.accountId) && $0.date <= month.month.lastOfMonth }
                    .map(\.amount))
            #expect(Amount.round(month.balance + month.readyToAssign) == money, "\(month.month)")
        }
    }

    @Test func staysFastForThousandsOfTransactions() throws {
        let masters = (0..<10).map { master in
            (
                id: "M\(master)", name: "Master \(master)",
                subs: (0..<10).map { (id: "C\(master)-\($0)", name: "Sub \($0)") }
            )
        }
        var scenario = ScenarioBudget(masters: masters)
        let start = date("2022-01-01")
        for index in 0..<5000 {
            let day = start.addingDays(index * 365 * 5 / 5000)
            scenario.budget.transactions.append(
                Transaction(
                    accountId: S.giro, date: day, categoryId: "C\(index % 10)-\(index % 7)",
                    amount: -Decimal(index % 90 + 1)))
        }
        for month in 0..<60 {
            for category in masters.flatMap(\.subs) {
                try scenario.budget(25, category.id, in: start.addingMonths(month).description)
            }
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = scenario.budget.budgetSheet(today: october24) }
        #expect(scenario.sheet.months.count >= 60)
        #expect(elapsed < .seconds(1))
    }
}
