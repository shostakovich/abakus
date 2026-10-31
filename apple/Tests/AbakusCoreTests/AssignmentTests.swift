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
        let half = try #require(Decimal(string: "2" + String(repeating: "0", count: 165)))
        try scenario.add(-half, on: "2026-09-10", category: S.kleidung)
        try scenario.add(-half, on: "2026-09-11", category: S.kleidung)
        try scenario.budget.apply(.quickBudget(month: october24, fill: .outflowsLastMonth, today: october24))
        #expect(scenario.budget.assignments.allSatisfy { $0.amount.isFinite })
        #expect(scenario.budget.assigned(in: october24, categoryId: S.kleidung) == 0)
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
