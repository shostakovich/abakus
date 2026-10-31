import Foundation
import Testing

@testable import AbakusCore

@Suite struct QuickBudgetTests {
    typealias S = ScenarioBudget

    /// Lebensmittel spends 10,00 more each month from Okt 2025 to Sep 2026; Kleidung only in Sep 2026.
    private func yearOfHistory() throws -> ScenarioBudget {
        var scenario = ScenarioBudget(income: nil)
        for back in 1...12 {
            let month = date("2026-10-01").addingMonths(-back)
            try scenario.add(-Decimal(130 - back * 10), on: month.addingDays(4).description, category: S.lebensmittel)
        }
        try scenario.add(-60, on: "2026-09-20", category: S.kleidung)
        return scenario
    }

    @Test func averagesLookBackFromTodayAndCoverAFullYear() throws {
        let sheet = try yearOfHistory().sheet
        let options = sheet.quickBudgetOptions(categoryId: S.lebensmittel, month: date("2026-10-01"))
        #expect(
            options.map(\.label) == [
                "Zugewiesen im Vormonat:", "Ausgegeben im Vormonat:", "Im Schnitt ausgegeben, letzte 3 Monate:",
                "Im Schnitt ausgegeben, letztes Jahr:", "Geplante Ausgaben diesen Monat:",
                "Verfügbar auf null bringen:",
            ])
        #expect(options.map(\.amount) == [0, 120, 110, 65, 0, 0])
        let june = sheet.quickBudgetOptions(categoryId: S.lebensmittel, month: date("2026-06-01"))
        #expect(june[1].amount == 80)
        #expect(june[2].amount == 110)
        let future = sheet.quickBudgetOptions(categoryId: S.kleidung, month: date("2027-02-01"))
        #expect(future.map(\.fill).contains(.averageOutflowsLastYear))
        #expect(future[2].label == "Im Schnitt ausgegeben, letzte 3 Monate:")
        #expect(future[2].amount == 20)
    }

    @Test func monthMenuOffersTheAveragesWithTheirMonthCounts() throws {
        let sheet = try yearOfHistory().sheet
        let menu = sheet.quickBudgetMenu(month: date("2026-10-01"), formatter: german)
        #expect(
            menu.map(\.label) == [
                "Leere Zuweisungen füllen mit:", "   Zugewiesen im Vormonat", "   Ausgegeben im Vormonat",
                "   Im Schnitt ausgegeben, letzte 3 Monate", "   Im Schnitt ausgegeben, letztes Jahr",
                "   Geplante Ausgaben diesen Monat", "   Verfügbar auf null bringen", "Alle Zuweisungen setzen auf:",
                "   0,00 (alle Zuweisungen zurücksetzen)",
            ])
        #expect(
            menu.map(\.fill) == [
                nil, .assignedLastMonth, .outflowsLastMonth, .averageOutflows, .averageOutflowsLastYear,
                .scheduledOutflows, .balanceToZero, nil, .zero,
            ])
        #expect(
            menu.compactMap(\.confirmation?.instruction) == [
                "Leere Zuweisungen mit den Zuweisungen aus September '26 füllen?",
                "Leere Zuweisungen mit den Ausgaben aus September '26 füllen?",
                "Leere Zuweisungen mit den durchschnittlichen Ausgaben der letzten 3 Monate füllen?",
                "Leere Zuweisungen mit den durchschnittlichen Ausgaben des letzten Jahres füllen?",
                "Leere Zuweisungen mit den geplanten Ausgaben für Oktober '26 füllen?",
                "Leere Zuweisungen so füllen, dass Verfügbar auf null kommt?",
                "Alle Zuweisungen im Oktober zurücksetzen?",
            ])
        #expect(menu[1].confirmation?.content == "Das lässt sich nicht rückgängig machen.")
        #expect(menu[1].confirmation?.button == "Leere Zuweisungen füllen")
        #expect(
            menu.last?.confirmation
                == QuickBudgetConfirmation(
                    instruction: "Alle Zuweisungen im Oktober zurücksetzen?",
                    content: "<i>Jede</i> Kategorie bekommt 0,00 zugewiesen. Das lässt sich nicht rückgängig machen.",
                    button: "Zurücksetzen"))
    }

    @Test func monthMenuUsesTheThreeMonthCountLikeTheCellList() throws {
        var scenario = ScenarioBudget(income: nil)
        try scenario.add(-30, on: "2026-05-10", category: S.lebensmittel)
        try scenario.add(-50, on: "2026-04-10", category: S.lebensmittel)
        let menu = scenario.sheet.quickBudgetMenu(month: date("2026-10-01"), formatter: german).map(\.label)
        #expect(!menu.contains { $0.contains("letzte 3 Monate") || $0.contains("letzte 0") })
        #expect(menu.contains("   Im Schnitt ausgegeben, letztes Jahr (nur 6 Monate)"))
        let cells = scenario.sheet.quickBudgetOptions(categoryId: S.lebensmittel, month: date("2026-10-01"))
        #expect(cells.map(\.label).contains("Im Schnitt ausgegeben, letztes Jahr (nur 6 Monate):"))
        #expect(cells.first { $0.fill == .averageOutflowsLastYear }?.amount == decimal("13.33"))
    }

    @Test func aFillsConfirmationIsTheMenusWithoutTheMenu() throws {
        var scenario = ScenarioBudget(income: nil)
        try scenario.add(-30, on: "2026-09-10", category: S.lebensmittel)
        let sheet = scenario.sheet
        let october = date("2026-10-01")
        let menu = sheet.quickBudgetMenu(month: october, formatter: german)
        for fill in QuickBudgetFill.allCases {
            #expect(
                sheet.quickBudgetConfirmation(fill, month: october, formatter: german)
                    == menu.first { $0.fill == fill }?.confirmation)
        }
        #expect(sheet.quickBudgetConfirmation(.averageOutflows, month: october, formatter: german) == nil)
        let cells = sheet.quickBudgetOptions(categoryId: S.lebensmittel, month: october).map(\.fill)
        #expect(cells == menu.compactMap(\.fill).filter { $0 != .zero })
    }

    @Test func averagesRoundHalvesTowardsPlusInfinity() throws {
        var scenario = ScenarioBudget(income: nil)
        try scenario.budget(1, S.kleidung, in: "2026-08-01")
        try scenario.add(decimal("-0.01"), on: "2026-08-03", category: S.lebensmittel)
        try scenario.add(decimal("0.01"), on: "2026-08-04", category: S.notgroschen)
        let sheet = scenario.sheet
        #expect(
            sheet.quickBudgetAmount(.averageOutflows, categoryId: S.lebensmittel, month: october24) == decimal("0.01"))
        #expect(sheet.quickBudgetAmount(.averageOutflows, categoryId: S.notgroschen, month: october24) == 0)
    }

    @Test func fillsOnlyEmptyCells() throws {
        var scenario = try yearOfHistory()
        try scenario.budget(77, S.notgroschen, in: "2026-10-01")
        try scenario.budget.apply(.setCategoryGroupExpanded(groupId: S.alltag, false))
        try scenario.add(-9, on: "2026-09-12", category: nil)
        try scenario.budget.apply(.quickBudget(month: october24, fill: .outflowsLastMonth, today: october24))
        let october = scenario.month("2026-10-01")
        #expect(october.category(S.lebensmittel)?.assigned == 120)
        #expect(october.category(S.notgroschen)?.assigned == 77)
        #expect(october.category(EntityID.uncategorizedCategory)?.assigned == 0)
        try scenario.budget.apply(.quickBudget(month: october24, fill: .zero, today: october24))
        #expect(scenario.month("2026-10-01").assigned == 0)
    }

    @Test func aFillReachesAMonthOutsideTheSheet() throws {
        var scenario = try yearOfHistory()
        try scenario.budget(50, S.notgroschen, in: "2026-10-01")
        let far = date("2030-03-01")
        #expect(scenario.sheet.month(far) == nil)
        try scenario.budget.apply(.quickBudget(month: far, fill: .balanceToZero, today: october24))
        #expect(scenario.budget.assigned(in: far, categoryId: S.notgroschen) == -50)
    }

    @Test func eachFillTakesItsFigure() throws {
        var scenario = try yearOfHistory()
        try scenario.budget(40, S.lebensmittel, in: "2026-09-01")
        try scenario.add(-25, on: "2026-10-02", category: S.lebensmittel)
        let expected: [(QuickBudgetFill, Decimal)] = [
            (.assignedLastMonth, 40), (.outflowsLastMonth, 120), (.averageOutflows, 110),
            (.averageOutflowsLastYear, 65), (.scheduledOutflows, 0), (.balanceToZero, 25),
        ]
        for (fill, amount) in expected {
            var budget = scenario.budget
            try budget.apply(.quickBudget(month: october24, fill: fill, today: october24))
            #expect(
                budget.budgetSheet(today: october24).month(october24)?.category(S.lebensmittel)?.assigned == amount,
                "\(fill)")
        }
    }

    @Test func balanceToZeroMakesTheBalanceZero() throws {
        var scenario = try S.scenarioB()
        let options = scenario.sheet.quickBudgetOptions(categoryId: S.kleidung, month: october24)
        let balanceToZero = try #require(options.first { $0.fill == .balanceToZero })
        #expect(balanceToZero.amount == 80)
        try scenario.budget(balanceToZero.amount, S.kleidung, in: "2026-10-01")
        #expect(scenario.month("2026-10-01").category(S.kleidung)?.balance == 0)
    }

    @Test func scheduledOutflowsCountEveryOccurrenceOfTheMonth() throws {
        var scenario = ScenarioBudget()
        try scenario.budget.apply(
            .addAccount(
                NewAccount(
                    id: "DEPOT", name: "Depot", kind: .tracking, startingBalance: 0,
                    startDate: date("2026-10-01"))))
        scenario.budget.scheduledTransactions = [
            ScheduledTransaction(
                accountId: S.giro, nextDate: date("2026-11-03"), frequency: .monthly, categoryId: S.lebensmittel,
                amount: -25),
            ScheduledTransaction(
                accountId: S.giro, nextDate: date("2026-10-27"), frequency: .weekly, categoryId: S.lebensmittel,
                amount: -10),
            ScheduledTransaction(
                accountId: S.giro, nextDate: date("2026-10-30"), frequency: .once, categoryId: S.lebensmittel,
                amount: 99),
            ScheduledTransaction(
                accountId: "DEPOT", nextDate: date("2026-10-30"), frequency: .monthly, categoryId: S.lebensmittel,
                amount: -500),
            ScheduledTransaction(
                id: "SPLIT", accountId: S.giro, nextDate: date("2026-10-15"), frequency: .everyOtherMonth,
                categoryId: EntityID.splitCategory, amount: -60,
                subtransactions: [
                    Subtransaction(transactionId: "SPLIT", amount: -45, categoryId: S.lebensmittel),
                    Subtransaction(transactionId: "SPLIT", amount: -15, categoryId: S.kleidung),
                ]),
        ]
        let sheet = scenario.sheet
        #expect(sheet.scheduledOutflows(categoryId: S.lebensmittel, month: date("2026-10-01")) == 85)
        #expect(sheet.scheduledOutflows(categoryId: S.lebensmittel, month: date("2026-11-01")) == 65)
        #expect(sheet.scheduledOutflows(categoryId: S.lebensmittel, month: date("2026-12-01")) == 120)
        #expect(sheet.scheduledOutflows(categoryId: S.kleidung, month: date("2026-12-01")) == 15)
        #expect(sheet.scheduledOutflows(categoryId: S.lebensmittel, month: date("2026-09-01")) == 0)
    }

    @Test(arguments: [
        (ScheduledTransactionFrequency.weekly, "2026-10-27", 4), (.monthly, "2026-11-03", 0),
        (.monthly, "2026-10-31", 1), (.everyOtherWeek, "2026-10-20", 2), (.twiceAMonth, "2026-10-17", 2),
        (.twiceAMonth, "2026-11-02", 0), (.daily, "2026-10-30", 31), (.yearly, "2025-10-05", 1),
        (.every4Weeks, "2026-09-01", 1), (.once, "2026-10-01", 1), (.once, "2026-09-30", 0),
    ])
    func occurrencesInOctober(frequency: ScheduledTransactionFrequency, next: String, count: Int) {
        let scheduled = ScheduledTransaction(accountId: "A", nextDate: date(next), frequency: frequency, amount: -1)
        #expect(scheduled.occurrences(from: date("2026-10-01"), through: date("2026-10-31")) == count)
    }
}
