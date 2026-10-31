import Foundation
import Testing

@testable import AbakusCore

/// Budgets from Abakus's own tests (`test/fixtures/budget/overspending.json`, `test/abakus/budget_test.exs`),
/// with the figures Abakus computes for them.
@Suite struct AbakusParityTests {
    private static func budget(
        income: [(String, Decimal)], activity: [(String, String?, Decimal)], assigned: [(String, String, Decimal)]
    ) throws -> ScenarioBudget {
        var scenario = ScenarioBudget(
            income: nil,
            masters: [
                (
                    id: "FIXTURE", name: "Fixture",
                    subs: [(id: "RENT", name: "Rent"), (id: "GROCERIES", name: "Groceries"), (id: "FUN", name: "Fun")]
                )
            ])
        for (day, amount) in income {
            try scenario.add(amount, on: day, category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        }
        for (day, category, amount) in activity { try scenario.add(amount, on: day, category: category) }
        for (month, category, amount) in assigned { try scenario.budget(amount, category, in: month) }
        return scenario
    }

    @Test func overspendingFixtureMatchesAbakus() throws {
        var scenario = try Self.budget(
            income: [("2026-09-01", 2000), ("2026-10-01", 1500)],
            activity: [
                ("2026-09-03", "RENT", -800), ("2026-09-10", "GROCERIES", -450), ("2026-09-12", "FUN", -50),
                ("2026-09-20", nil, -30), ("2026-10-03", "RENT", -800), ("2026-10-11", "GROCERIES", -300),
                ("2026-10-25", "FUN", -400), ("2026-11-04", "GROCERIES", -20),
            ],
            assigned: [
                ("2026-09-01", "RENT", 800), ("2026-09-01", "GROCERIES", 400), ("2026-09-01", "FUN", 200),
                ("2026-10-01", "RENT", 800), ("2026-10-01", "GROCERIES", 400), ("2026-10-01", "FUN", 100),
                ("2026-11-01", "RENT", 800), ("2026-11-01", "GROCERIES", -50),
            ])
        scenario.today = date("2026-11-15")
        let expected: [(month: String, income: Decimal, readyToAssign: Decimal, rows: [String: [Decimal]])] = [
            (
                "2026-09-01", 2000, 600,
                [
                    "RENT": [800, -800, 0], "GROCERIES": [400, -450, -50], "FUN": [200, -50, 150],
                    EntityID.uncategorizedCategory: [0, -30, -30],
                ]
            ),
            (
                "2026-10-01", 1500, 720,
                [
                    "RENT": [800, -800, 0], "GROCERIES": [400, -300, 100], "FUN": [100, -400, -150],
                    EntityID.uncategorizedCategory: [0, 0, 0],
                ]
            ),
            (
                "2026-11-01", 0, -180,
                [
                    "RENT": [800, 0, 800], "GROCERIES": [-50, -20, 30], "FUN": [0, 0, 0],
                    EntityID.uncategorizedCategory: [0, 0, 0],
                ]
            ),
        ]
        for month in expected {
            let figures = scenario.month(month.month)
            #expect(figures.income == month.income, "\(month.month)")
            #expect(figures.readyToAssign == month.readyToAssign, "\(month.month)")
            for (id, row) in month.rows {
                let category = try #require(figures.category(id))
                #expect([category.assigned, category.outflows, category.balance] == row, "\(month.month) \(id)")
            }
        }
    }

    @Test func zuVerteilenLeavesOutLaterAssignmentsExceptInAClosedMonth() throws {
        var scenario = try Self.budget(
            income: [("2026-09-01", 100)], activity: [],
            assigned: [("2026-10-01", "RENT", 10), ("2026-12-01", "RENT", 30)])
        scenario.today = date("2026-10-15")
        let september = scenario.month("2026-09-01")
        #expect([september.assignedInFuture, september.available] == [40, 100])
        let october = scenario.month("2026-10-01")
        #expect([october.assignedInFuture, october.available] == [30, 60])
        #expect(scenario.month("2026-11-01").available == 60)
        let december = scenario.month("2026-12-01")
        #expect([december.assignedInFuture, december.available] == [0, 60])
    }

    @Test func laterMonthsThatAreNotCoveredAreListedUpToTheLastChange() throws {
        var scenario = try Self.budget(
            income: [("2026-10-01", 100)], activity: [("2026-10-05", "RENT", -80)],
            assigned: [("2026-10-01", "RENT", 40), ("2026-11-01", "GROCERIES", 50), ("2026-12-01", "GROCERIES", 20)])
        scenario.today = date("2026-10-15")
        #expect(
            scenario.month("2026-10-01").uncovered == [
                BudgetShortfall(month: date("2026-11-01"), amount: 30),
                BudgetShortfall(month: date("2026-12-01"), amount: 50),
            ])
        #expect(scenario.month("2026-11-01").uncovered == [BudgetShortfall(month: date("2026-12-01"), amount: 50)])
        #expect(scenario.month("2026-12-01").uncovered.isEmpty)
    }

    @Test func aMonthWithDataThatOnlyRepeatsTheShortfallIsListedButNotTheEmptyMonthsAfterIt() throws {
        var scenario = try Self.budget(
            income: [("2026-10-01", 100), ("2026-12-01", 20)], activity: [("2026-10-05", "RENT", -80)],
            assigned: [("2026-10-01", "RENT", 40), ("2026-11-01", "GROCERIES", 90), ("2026-12-01", "GROCERIES", 20)])
        scenario.today = date("2026-10-15")
        #expect(
            scenario.month("2026-10-01").uncovered == [
                BudgetShortfall(month: date("2026-11-01"), amount: 70),
                BudgetShortfall(month: date("2026-12-01"), amount: 70),
            ])
        #expect(scenario.month("2027-01-01").readyToAssign == -70)
        #expect(
            scenario.month("2026-10-01").headerLines(formatter: german).suffix(2).map(\.text) == [
                "Nicht gedeckt im Nov", "Nicht gedeckt im Dez",
            ])
        #expect(scenario.month("2026-12-01").uncovered.isEmpty)
    }

    @Test func aShortfallInAnotherYearNamesItsYear() throws {
        var scenario = try Self.budget(
            income: [("2026-12-01", 10)], activity: [], assigned: [("2027-01-01", "FUN", 25)])
        scenario.today = date("2026-12-10")
        let line = try #require(scenario.month("2026-12-01").headerLines(formatter: german).last)
        #expect([line.amount, line.text] == ["-15,00", "Nicht gedeckt im Jan 2027"])
    }
}
