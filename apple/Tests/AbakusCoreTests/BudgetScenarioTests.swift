import Foundation
import Testing

@testable import AbakusCore

/// The worked budget examples A–N.
@Suite struct BudgetScenarioTests {
    typealias S = ScenarioBudget

    @Test func aPositiveBalanceCarriesOver() throws {
        var scenario = ScenarioBudget()
        try scenario.budget(300, S.lebensmittel, in: "2026-10-01")
        try scenario.add(-120, on: "2026-10-05", category: S.lebensmittel)
        #expect(scenario.month("2026-10-01").rowText(S.lebensmittel) == ["300,00", "-120,00", "180,00"])
        #expect(scenario.month("2026-11-01").rowText(S.lebensmittel) == ["", "", "180,00"])
    }

    @Test func bOverspendingIsPaidByNextMonthsZuVerteilen() throws {
        let scenario = try S.scenarioB()
        let october = scenario.month("2026-10-01")
        #expect(october.rowText(S.kleidung)[2] == "-30,00")
        #expect(october.category(S.kleidung)?.isOverspent == true)
        #expect(
            october.headerText == [
                "0,00 Nicht verteilt im Sep", "-0,00 Überzogen im Sep", "+1.000,00 Einnahmen im Okt",
                "-350,00 Zugewiesen im Okt", "= 650,00€", "Zu verteilen",
            ])
        #expect(october.totalsText == ["350,00€", "-200,00€", "150,00€"])
        let november = scenario.month("2026-11-01")
        #expect(
            november.headerText == [
                "650,00 Nicht verteilt im Okt", "-30,00 Überzogen im Okt", "+0,00 Einnahmen im Nov",
                "-0,00 Zugewiesen im Nov",
                "= 620,00€", "Zu verteilen",
            ])
        #expect(november.rowText(S.kleidung)[2] == "")
        #expect(november.totalsText == ["0,00€", "0,00€", "180,00€"])
    }

    @Test func cAnOverspentCategoryStartsTheNextMonthAtZero() throws {
        var scenario = ScenarioBudget(income: nil)
        try scenario.add(800, on: "2026-03-02", category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        try scenario.budget(300, S.lebensmittel, in: "2026-03-01")
        try scenario.add(-340, on: "2026-03-14", category: S.lebensmittel)
        #expect(scenario.month("2026-03-01").category(S.lebensmittel)?.balance == -40)
        #expect(scenario.month("2026-03-01").readyToAssign == 500)
        let april = scenario.month("2026-04-01")
        #expect(april.category(S.lebensmittel)?.balance == 0)
        #expect(april.headerText[1] == "-40,00 Überzogen im Mrz")
        #expect(april.headerLines(formatter: german)[1].isWarning)
        #expect(april.available == 460)
        try scenario.budget(10, S.lebensmittel, in: "2026-04-01")
        #expect(scenario.month("2026-04-01").category(S.lebensmittel)?.balance == 10)
    }

    @Test func dALaterMonthThatIsNotCovered() throws {
        var scenario = ScenarioBudget(
            income: nil, masters: [(id: "REISEN", name: "Reisen", subs: [(id: "URLAUB", name: "Urlaub")])],
            start: "2026-04-01")
        scenario.today = date("2026-04-20")
        try scenario.add(200, on: "2026-04-02", category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        try scenario.budget(250, "URLAUB", in: "2026-05-01")
        let april = scenario.month("2026-04-01")
        #expect(april.readyToAssign == 200)
        #expect(
            april.headerText == [
                "0,00 Nicht verteilt im Mrz", "-0,00 Überzogen im Mrz", "+200,00 Einnahmen im Apr",
                "-0,00 Zugewiesen im Apr", "-250,00 Für spätere Monate", "-50,00 Nicht gedeckt im Mai", "= -50,00€",
                "Zu verteilen",
            ])
        #expect(try #require(april.headerLines(formatter: german).last).isWarning)
        #expect(scenario.month("2026-05-01").uncovered.isEmpty)
        #expect(scenario.budget.assigned(in: date("2026-05-01"), categoryId: "URLAUB") == 250)
    }

    @Test func eIncomeGoesToZuVerteilenInTheMonthItIsBooked() throws {
        var scenario = try S.scenarioB()
        try scenario.add(2000, on: "2026-10-28", category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        #expect(scenario.budget.categoryDisplayName(ScenarioBudget.readyToAssign) == "Zu verteilen")
        let october = scenario.month("2026-10-01")
        #expect(october.headerText[2] == "+3.000,00 Einnahmen im Okt")
        #expect(october.headerText[4] == "= 2.650,00€")
        let november = scenario.month("2026-11-01")
        #expect(november.headerText[2] == "+0,00 Einnahmen im Nov")
        #expect(november.headerText[4...5] == ["= 2.620,00€", "Zu verteilen"])
    }

    @Test func fOverbudgetingCarriesIntoTheNextMonths() throws {
        var scenario = ScenarioBudget(
            income: nil, masters: [(id: "KRAM", name: "Kram", subs: [(id: "FESTPLATTEN", name: "Festplatten")])])
        try scenario.budget(100, "FESTPLATTEN", in: "2026-10-01")
        #expect(
            scenario.month("2026-10-01").headerText == [
                "0,00 Nicht verteilt im Sep", "-0,00 Überzogen im Sep", "+0,00 Einnahmen im Okt",
                "-100,00 Zugewiesen im Okt", "= -100,00€", "Zu verteilen",
            ])
        #expect(
            scenario.month("2026-11-01").headerText == [
                "-100,00 Nicht verteilt im Okt", "-0,00 Überzogen im Okt", "+0,00 Einnahmen im Nov",
                "-0,00 Zugewiesen im Nov",
                "= -100,00€", "Zu verteilen",
            ])
        let december = scenario.month("2026-12-01").headerText
        #expect(december[0] == "-100,00 Nicht verteilt im Nov")
        #expect(december[4...5] == ["= -100,00€", "Zu verteilen"])
    }

    @Test func gBudgetingInAFutureMonth() throws {
        var scenario = try S.scenarioB()
        try scenario.budget(200, S.lebensmittel, in: "2026-12-01")
        #expect(scenario.month("2026-10-01").headerText[4...5] == ["-200,00 Für spätere Monate", "= 450,00€"])
        #expect(scenario.month("2026-11-01").headerText[4...5] == ["-200,00 Für spätere Monate", "= 420,00€"])
        let december = scenario.month("2026-12-01")
        #expect(
            december.headerText == [
                "620,00 Nicht verteilt im Nov", "-0,00 Überzogen im Nov", "+0,00 Einnahmen im Dez",
                "-200,00 Zugewiesen im Dez",
                "= 420,00€", "Zu verteilen",
            ])
        #expect(december.rowText(S.lebensmittel) == ["200,00", "", "380,00"])
    }

    @Test func hASplitAcrossTwoCategories() throws {
        var scenario = ScenarioBudget()
        try scenario.split([(-70, S.lebensmittel), (-30, S.kleidung)], on: "2026-10-15", payee: "Kaufhaus")
        let october = scenario.month("2026-10-01")
        #expect(october.rowText(S.lebensmittel) == ["", "-70,00", "-70,00"])
        #expect(october.rowText(S.kleidung) == ["", "-30,00", "-30,00"])
        #expect(october.masterText(S.alltag) == ["0,00", "-100,00", "-100,00"])
        let summary = scenario.budget.outflowSummary(
            .category(S.lebensmittel), month: date("2026-10-01"), today: october24, formatter: german)
        #expect(summary.message == "70,00€ ausgegeben in 1 Buchung:")
        let row = try #require(summary.rows.first)
        #expect(summary.rows.count == 1)
        #expect(
            [german.dateShort(row.date), row.accountName, row.payee, german.currencyNoSymbol(row.amount)] == [
                "15.10.26", "Giro", "[Aufgeteilt] Kaufhaus ", "-70,00",
            ])
        #expect(scenario.month("2026-11-01").headerText[1] == "-100,00 Überzogen im Okt")
    }

    @Test func iATransferToAnOffBudgetAccount() throws {
        var scenario = ScenarioBudget()
        try scenario.budget.apply(
            .addAccount(
                NewAccount(
                    id: "DEPOT", name: "Depot", kind: .tracking, startingBalance: 0,
                    startDate: date("2026-10-01"))))
        let transfer = Transaction(
            id: "TR", accountId: S.giro, date: date("2026-10-20"), categoryId: S.notgroschen, amount: -500
        ).transferring(to: "DEPOT")
        try scenario.budget.apply(.addTransaction(transfer))
        let october = scenario.month("2026-10-01")
        #expect(october.rowText(S.notgroschen) == ["", "-500,00", "-500,00"])
        #expect(october.income == 1000)
        #expect(october.spent == 500)
        #expect(!scenario.sheet.showsUncategorizedRow)
        try scenario.budget.apply(.categorizeTransactions(["TR"], categoryId: nil))
        let sheet = scenario.sheet
        #expect(sheet.showsUncategorizedRow)
        let uncategorized = sheet.month(date("2026-10-01"))!.uncategorized
        #expect(
            [german.budgetAmount(uncategorized.outflows, prefix: "+"), german.currencyNoSymbol(uncategorized.balance)]
                == ["-500,00", "-500,00"])
        #expect(sheet.month(date("2026-11-01"))?.headerText[1] == "-500,00 Überzogen im Okt")
    }

    @Test func kDeletingACategoryIntoAnother() throws {
        var scenario = ScenarioBudget(
            income: nil,
            masters: [("FREIZEIT", "Freizeit", [("ZEITSCHRIFTEN", "Zeitschriften"), ("BUECHER", "Bücher")])],
            start: "2026-06-01")
        try scenario.add(500, on: "2026-06-01", category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        try scenario.budget(30, "ZEITSCHRIFTEN", in: "2026-06-01")
        try scenario.budget(20, "BUECHER", in: "2026-06-01")
        try scenario.add(-5, on: "2026-06-03", category: "BUECHER")
        let issues = try ["2026-06-02", "2026-06-12", "2026-06-22"].map {
            try scenario.add(-6, on: $0, category: "ZEITSCHRIFTEN")
        }
        #expect(scenario.month("2026-06-01").category("ZEITSCHRIFTEN")?.balance == 12)
        #expect(scenario.month("2026-06-01").category("BUECHER")?.balance == 15)
        try scenario.budget.apply(.deleteCategory(categoryId: "ZEITSCHRIFTEN", into: "BUECHER"))
        #expect(
            issues.map { scenario.budget.transaction(withId: $0)?.categoryId } == ["BUECHER", "BUECHER", "BUECHER"])
        let june = scenario.month("2026-06-01")
        #expect(june.category("BUECHER")?.balance == 27)
        #expect(june.category("ZEITSCHRIFTEN") == nil)
        #expect(june.headerText[4] == "= 450,00€")
    }

    @Test func lTheDropDownShowsTheBalanceOfTodaysMonth() throws {
        var scenario = try S.scenarioB()
        try scenario.budget(200, S.lebensmittel, in: "2026-12-01")
        let balances = scenario.budget.categoryBalances(today: october24)
        #expect(balances[S.lebensmittel] == 180)
        #expect(balances[S.kleidung] == -30)
        #expect(balances[S.notgroschen] == 0)
    }

    @Test func nQuickBudgetFiguresInTheCurrentAndAFutureMonth() throws {
        var scenario = ScenarioBudget(income: nil)
        for (month, assigned, outflow) in [("07", 100, -90), ("08", 120, -120), ("09", 140, -150)]
            as [(String, Decimal, Decimal)]
        {
            try scenario.budget(assigned, S.lebensmittel, in: "2026-\(month)-01")
            try scenario.add(outflow, on: "2026-\(month)-10", category: S.lebensmittel)
        }
        try scenario.add(-40, on: "2026-10-10", category: S.lebensmittel)
        let sheet = scenario.sheet
        let october = sheet.quickBudgetOptions(categoryId: S.lebensmittel, month: date("2026-10-01"))
        #expect(
            october.map { "\($0.label)\(german.currencyNoSymbol($0.amount))" } == [
                "Zugewiesen im Vormonat:140,00", "Ausgegeben im Vormonat:150,00",
                "Im Schnitt ausgegeben, letzte 3 Monate:120,00", "Geplante Ausgaben diesen Monat:0,00",
                "Verfügbar auf null bringen:40,00",
            ])
        let december = sheet.quickBudgetOptions(categoryId: S.lebensmittel, month: date("2026-12-01"))
        #expect(
            december.dropFirst().map { "\($0.label)\(german.currencyNoSymbol($0.amount))" }.prefix(3) == [
                "Ausgegeben im Vormonat:0,00", "Im Schnitt ausgegeben, letzte 3 Monate:103,33",
                "Im Schnitt ausgegeben, letztes Jahr (nur 4 Monate):100,00",
            ])
    }
}
