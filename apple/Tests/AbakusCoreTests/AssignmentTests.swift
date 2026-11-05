import Foundation
import Testing

@testable import AbakusCore

@Suite struct AssignmentTests {
    typealias S = ScenarioBudget

    @Test func assignmentsAreRoundedAndStoredOnlyWhileNotZero() throws {
        var scenario = ScenarioBudget()
        try scenario.budget.apply(
            .setAssigned(month: date("2026-10-17"), categoryId: S.kleidung, amount: decimal("12.345")))
        #expect(scenario.budget.assignments.map(\.month) == [date("2026-10-01")])
        #expect(scenario.budget.assigned(in: october24, categoryId: S.kleidung) == decimal("12.35"))
        try scenario.budget(-5, S.notgroschen, in: "2026-08-01")
        #expect(Set(scenario.budget.assignments.map(\.month)) == [date("2026-08-01"), date("2026-10-01")])
        try scenario.budget(0, S.kleidung, in: "2026-10-01")
        try scenario.budget(0, S.notgroschen, in: "2026-08-01")
        #expect(scenario.budget.assignments.isEmpty)
    }

    @Test func anAssignmentIsNamedAfterItsCategoryAndMonth() throws {
        var scenario = ScenarioBudget()
        try scenario.budget(10, S.kleidung, in: "2026-10-01")
        try scenario.budget(20, S.kleidung, in: "2026-10-01")
        let assignment = try #require(scenario.budget.assignments.first)
        #expect(scenario.budget.assignments.count == 1)
        #expect(assignment.id == EntityID.assignment(categoryId: S.kleidung, month: october24))
        #expect(assignment.amount == 20)
    }

    @Test func onlyBudgetCategoriesTakeAssignments() throws {
        var budget = ScenarioBudget().budget
        let refused = [
            budget.readyToAssignCategoryId, EntityID.splitCategory, EntityID.uncategorizedCategory, "MISSING",
        ]
        for id in refused {
            #expect(throws: BudgetError.categoryNotFound(id)) {
                try budget.apply(.setAssigned(month: october24, categoryId: id, amount: 10))
            }
        }
    }

    @Test func amountsThatAreNotFiniteAreRefused() throws {
        var scenario = ScenarioBudget()
        #expect(throws: BudgetError.amountNotFinite) {
            try scenario.budget.apply(.setAssigned(month: october24, categoryId: S.kleidung, amount: .nan))
        }
    }

    @Test func resettingSetsEveryAssignmentOfTheMonthToZero() throws {
        var scenario = ScenarioBudget()
        try scenario.budget(40, S.kleidung, in: "2026-10-01")
        try scenario.budget(-15, S.notgroschen, in: "2026-10-01")
        try scenario.budget(25, S.kleidung, in: "2026-09-01")
        try scenario.budget.apply(.resetAssigned(month: october24))
        #expect(scenario.month("2026-10-01").category(S.kleidung)?.assigned == 0)
        #expect(scenario.month("2026-10-01").category(S.notgroschen)?.assigned == 0)
        #expect(scenario.budget.assigned(in: date("2026-09-01"), categoryId: S.kleidung) == 25)
    }

    @Test func changingAssignedAddsToEachCategoryOfTheMonth() throws {
        var scenario = ScenarioBudget()
        try scenario.budget(40, S.kleidung, in: "2026-10-01")
        try scenario.budget.apply(
            .changeAssigned(
                month: october24,
                [
                    AssignedChange(categoryId: S.kleidung, amount: -15),
                    AssignedChange(categoryId: S.notgroschen, amount: 15),
                ]
            ))
        #expect(scenario.month("2026-10-01").category(S.kleidung)?.assigned == 25)
        #expect(scenario.month("2026-10-01").category(S.notgroschen)?.assigned == 15)
        #expect(throws: BudgetError.categoryNotFound("MISSING")) {
            try scenario.budget.apply(
                .changeAssigned(month: october24, [AssignedChange(categoryId: "MISSING", amount: 1)]))
        }
        #expect(scenario.month("2026-10-01").category(S.kleidung)?.assigned == 25)
    }

    @Test func assignmentsSurviveARoundTrip() throws {
        let scenario = try S.scenarioB()
        let loaded = try savedAndLoaded(scenario.budget)
        #expect(Set(loaded.assignments) == Set(scenario.budget.assignments))
        #expect(
            scenario.budget.syncedRows["assignments"]?.values.contains { $0["month"] == .text("2026-10-01") } == true)
    }

    @MainActor
    @Test func assignmentsGoThroughTheStore() throws {
        let store = BudgetStore(budget: ScenarioBudget().budget, today: { october24 })
        try store.perform(.setAssigned(month: october24, categoryId: S.kleidung, amount: 40))
        #expect(store.budget.budgetSheet(today: store.today()).month(october24)?.assigned == 40)
    }
}
