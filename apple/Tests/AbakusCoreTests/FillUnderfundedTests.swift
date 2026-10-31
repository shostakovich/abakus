import Foundation
import Testing

@testable import AbakusCore

/// Abakus's `fill_underfunded/4` tests in `test/abakus/budget_test.exs`, its amounts in euros instead of cents.
@Suite struct FillUnderfundedTests {
    typealias S = ScenarioBudget
    let september = date("2026-09-01")
    let october = date("2026-10-01")
    let november = date("2026-11-01")

    private func scenario(income: Decimal, on day: String = "2026-10-01") throws -> ScenarioBudget {
        var scenario = ScenarioBudget(income: nil, start: "2026-09-01")
        try scenario.add(income, on: day, category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        return scenario
    }

    private func target(_ amount: Decimal, _ category: String, from month: String = "2026-09-01", on scenario: inout S)
        throws
    {
        try scenario.budget.apply(.setTarget(month: date(month), categoryId: category, target: .monthly(amount)))
    }

    private func fills(_ scenario: S, in month: DateWithoutTime) -> [BudgetFill] {
        scenario.sheet.underfundedFills(in: month)
    }

    @Test func fillUnderfundedWithTooLittleZuVerteilenFillsInBudgetOrderAndSkipsASnoozedTarget() throws {
        var scenario = try scenario(income: 50)
        try target(30, S.lebensmittel, on: &scenario)
        try target(40, S.kleidung, on: &scenario)
        try target(40, S.notgroschen, on: &scenario)
        try scenario.budget.apply(.setTargetSnoozed(month: october, categoryId: S.lebensmittel, true))
        try scenario.budget(10, S.kleidung, in: "2026-10-01")
        try scenario.budget.apply(.fillUnderfunded(month: october, today: scenario.today))
        let month = scenario.month("2026-10-01")
        #expect(month.category(S.lebensmittel)?.assigned == 0)
        #expect(month.category(S.kleidung)?.assigned == 40)
        #expect(month.category(S.notgroschen)?.assigned == 10)
        #expect(month.available == 0)
        #expect(month.category(S.notgroschen)?.target?.underfunded == 30)
    }

    @Test func fillsInBudgetOrderAsFarAsZuVerteilenReaches() throws {
        var scenario = try scenario(income: 80)
        try scenario.budget(10, S.kleidung, in: "2026-10-01")
        try target(30, S.lebensmittel, on: &scenario)
        try target(40, S.kleidung, on: &scenario)
        try target(40, S.notgroschen, on: &scenario)
        #expect(
            fills(scenario, in: october) == [
                BudgetFill(categoryId: S.lebensmittel, amount: 30), BudgetFill(categoryId: S.kleidung, amount: 30),
                BudgetFill(categoryId: S.notgroschen, amount: 10),
            ])
    }

    @Test func skipsSnoozedCategories() throws {
        var scenario = try scenario(income: 100)
        try target(40, S.lebensmittel, on: &scenario)
        try target(30, S.kleidung, on: &scenario)
        try scenario.budget.apply(.setTargetSnoozed(month: october, categoryId: S.lebensmittel, true))
        #expect(fills(scenario, in: october) == [BudgetFill(categoryId: S.kleidung, amount: 30)])
    }

    @Test func keepsWhatLaterMonthsHaveAndAssignsNothingWithoutMoney() throws {
        var scenario = try scenario(income: 50)
        try scenario.budget(50, S.kleidung, in: "2026-11-01")
        try target(40, S.lebensmittel, on: &scenario)
        #expect(fills(scenario, in: october).isEmpty)
        let before = scenario.budget
        try scenario.budget.apply(.fillUnderfunded(month: october, today: scenario.today))
        #expect(scenario.budget == before)
    }

    @Test func takesNothingThatLaterMonthsHaveInAClosedMonthEither() throws {
        var scenario = try scenario(income: 50, on: "2026-09-01")
        try scenario.budget(50, S.kleidung, in: "2026-10-01")
        try target(40, S.lebensmittel, on: &scenario)
        #expect(fills(scenario, in: september).isEmpty)
    }

    @Test func theUnderfundedTotalLeavesOutSnoozedTargets() throws {
        var scenario = try scenario(income: 20)
        try target(40, S.lebensmittel, on: &scenario)
        try target(30, S.kleidung, on: &scenario)
        try target(5, S.notgroschen, on: &scenario)
        try scenario.budget.apply(.setTargetSnoozed(month: october, categoryId: S.notgroschen, true))
        try scenario.budget(10, S.kleidung, in: "2026-10-01")
        #expect(scenario.sheet.underfunded(in: october) == 60)
        #expect(scenario.month("2026-10-01").free == 10)
        #expect(scenario.sheet.underfunded(in: november) == 75)
    }

    @Test func freeIsWhatZuVerteilenHasLessLaterAssignmentsAndNeverBelowZero() throws {
        var scenario = try scenario(income: 50, on: "2026-09-01")
        try scenario.budget(30, S.kleidung, in: "2026-10-01")
        #expect(scenario.month("2026-09-01").free == 20)
        try scenario.budget(30, S.kleidung, in: "2026-11-01")
        #expect(scenario.month("2026-09-01").free == 0)
    }

    /// Abakus's "Verteilen › In eine Kategorie …" test in `test/abakus_web/live/budget_details_test.exs`.
    @Test func assigningToOneCategorySuggestsTheFirstUnderfundedWithWhatItStillNeeds() throws {
        var scenario = try scenario(income: 1000)
        try target(120, S.kleidung, on: &scenario)
        let sheet = scenario.sheet
        #expect(sheet.firstUnderfunded(in: october) == S.kleidung)
        #expect(sheet.assignSuggestion(categoryId: S.kleidung, in: october) == 120)
        #expect(sheet.assignSuggestion(categoryId: S.lebensmittel, in: october) == 1000)
    }

    @Test func theSuggestionReachesOnlyAsFarAsZuVerteilenAndSkipsSnoozedTargets() throws {
        var scenario = try scenario(income: 50)
        try target(120, S.lebensmittel, on: &scenario)
        try target(80, S.kleidung, on: &scenario)
        try scenario.budget.apply(.setTargetSnoozed(month: october, categoryId: S.lebensmittel, true))
        #expect(scenario.sheet.firstUnderfunded(in: october) == S.kleidung)
        #expect(scenario.sheet.assignSuggestion(categoryId: S.kleidung, in: october) == 50)
        #expect(scenario.sheet.assignSuggestion(categoryId: S.lebensmittel, in: october) == 50)
        #expect(ScenarioBudget().sheet.firstUnderfunded(in: october) == nil)
    }
}
