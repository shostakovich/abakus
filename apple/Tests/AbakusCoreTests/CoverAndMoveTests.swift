import Foundation
import Testing

@testable import AbakusCore

@Suite struct CoverAndMoveTests {
    typealias S = ScenarioBudget
    static let restaurant = "RESTAURANT"
    static let june = date("2026-06-01")

    /// Alltag (Restaurant, Kleidung), Sparen (Notgroschen) with 100,00 income in June 2026.
    private func june() throws -> ScenarioBudget {
        var scenario = ScenarioBudget(
            income: nil,
            masters: [
                (S.alltag, "Alltag", [(Self.restaurant, "Restaurant"), (S.kleidung, "Kleidung")]),
                (S.sparen, "Sparen", [(S.notgroschen, "Notgroschen")]),
            ],
            start: "2026-06-01")
        scenario.today = date("2026-06-20")
        try scenario.add(100, on: "2026-06-01", category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        try scenario.add(-25, on: "2026-06-10", category: Self.restaurant)
        try scenario.budget(60, S.kleidung, in: "2026-06-01")
        return scenario
    }

    @Test func coverFromAnotherCategory() throws {
        var scenario = try june()
        #expect(scenario.month("2026-06-01").category(Self.restaurant)?.balance == -25)
        #expect(scenario.month("2026-06-01").category(S.kleidung)?.balance == 60)
        let source = try #require(
            scenario.sheet.coverSources(for: Self.restaurant, in: Self.june).first { $0.categoryId == S.kleidung })
        try scenario.budget.apply(
            .moveAssigned(
                month: Self.june, from: S.kleidung, to: Self.restaurant, amount: source.coverAmount(overspent: -25)))
        #expect(scenario.month("2026-06-01").category(Self.restaurant)?.balance == 0)
        #expect(scenario.month("2026-06-01").category(S.kleidung)?.balance == 35)
    }

    @Test func coverSourcesListZuVerteilenFirstThenCategoriesWithTheMostFirst() throws {
        var scenario = try june()
        try scenario.budget(30, S.notgroschen, in: "2026-06-01")
        let sources = scenario.sheet.coverSources(for: Self.restaurant, in: Self.june)
        #expect(sources.map(\.categoryId) == [ScenarioBudget.readyToAssign, S.kleidung, S.notgroschen])
        #expect(sources.map(\.name) == ["Zu verteilen", "Kleidung", "Notgroschen"])
        #expect(sources.map(\.available) == [10, 60, 30])
        #expect(sources[0].isReadyToAssign)
    }

    @Test func coverSourcesLeaveOutAnEmptyZuVerteilenAndCategoriesWithoutMoney() throws {
        var scenario = try june()
        try scenario.budget(40, S.notgroschen, in: "2026-06-01")
        let sources = scenario.sheet.coverSources(for: Self.restaurant, in: Self.june)
        #expect(sources.map(\.categoryId) == [S.kleidung, S.notgroschen])
        #expect(scenario.sheet.coverSources(for: Self.restaurant, in: date("2020-01-01")).isEmpty)
    }

    @Test func aClosedMonthOffersOnlyWhatLaterMonthsLeaveFreeOfZuVerteilen() throws {
        var scenario = try june()
        scenario.today = date("2026-07-20")
        try scenario.budget(30, S.notgroschen, in: "2026-07-01")
        let june = scenario.month("2026-06-01")
        #expect(june.isClosed && june.available == 40 && june.free == 10)
        let source = try #require(scenario.sheet.coverSources(for: Self.restaurant, in: Self.june).first)
        #expect(source.isReadyToAssign)
        #expect(source.available == 10)
        #expect(source.coverAmount(overspent: -25) == 10)
    }

    @Test func coveringTakesTheOverspendingAsFarAsTheSourceReaches() {
        let source = BudgetFundsSource(categoryId: S.kleidung, name: "Kleidung", available: 15)
        #expect(source.coverAmount(overspent: -25) == 15)
        #expect(source.remaining(afterCovering: -25) == 0)
        #expect(source.coverAmount(overspent: -10) == 10)
        #expect(source.remaining(afterCovering: -10) == 5)
    }

    @Test func coveringFromZuVerteilenOnlyRaisesTheAssignment() throws {
        var scenario = try june()
        try scenario.budget.apply(
            .moveAssigned(month: Self.june, from: ScenarioBudget.readyToAssign, to: Self.restaurant, amount: 10))
        let month = scenario.month("2026-06-01")
        #expect(month.category(Self.restaurant)?.assigned == 10)
        #expect(month.category(Self.restaurant)?.balance == -15)
        #expect(month.available == 30)
    }

    @Test func movingAddsToTheExistingAssignmentsOnBothSides() throws {
        var scenario = try june()
        try scenario.budget(5, S.notgroschen, in: "2026-06-01")
        try scenario.budget.apply(.moveAssigned(month: Self.june, from: S.kleidung, to: S.notgroschen, amount: 12.5))
        try scenario.budget.apply(
            .moveAssigned(month: Self.june, from: S.notgroschen, to: ScenarioBudget.readyToAssign, amount: 2))
        let month = scenario.month("2026-06-01")
        #expect(month.category(S.kleidung)?.assigned == 47.5)
        #expect(month.category(S.notgroschen)?.assigned == 15.5)
        #expect(month.available == 37)
    }

    @Test func aMoveToAnUnknownCategoryChangesNothing() throws {
        var scenario = try june()
        let before = scenario.budget
        #expect(throws: BudgetError.categoryNotFound("NOPE")) {
            try scenario.budget.apply(.moveAssigned(month: Self.june, from: S.kleidung, to: "NOPE", amount: 5))
        }
        #expect(scenario.budget == before)
    }

    @Test func aMoveNeedsAnAmountAboveZeroAndTwoSides() throws {
        var scenario = try june()
        let before = scenario.budget
        try scenario.budget.apply(.moveAssigned(month: Self.june, from: S.kleidung, to: S.notgroschen, amount: 0))
        try scenario.budget.apply(.moveAssigned(month: Self.june, from: S.kleidung, to: S.kleidung, amount: 5))
        #expect(scenario.budget == before)
    }
}
