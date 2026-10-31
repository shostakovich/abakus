import Foundation
import Testing

@testable import AbakusCore

@Suite struct TargetCommandTests {
    typealias S = ScenarioBudget
    let october = date("2026-10-01")
    let november = date("2026-11-01")

    private func set(_ target: Target, in month: DateWithoutTime, on budget: inout Budget) throws {
        try budget.apply(.setTarget(month: month, categoryId: S.kleidung, target: target))
    }

    @Test func aChangedTargetStartsANewVersionSoEarlierMonthsKeepTheirs() throws {
        var budget = ScenarioBudget().budget
        try set(.monthly(50), in: october, on: &budget)
        try set(.monthly(80, setAside: false), in: november, on: &budget)
        #expect(budget.target(in: date("2026-09-30"), categoryId: S.kleidung) == nil)
        #expect(budget.target(in: date("2026-10-15"), categoryId: S.kleidung) == .monthly(50))
        #expect(budget.target(in: date("2027-03-01"), categoryId: S.kleidung) == .monthly(80, setAside: false))
        try set(.ended, in: date("2027-01-01"), on: &budget)
        #expect(budget.target(in: date("2027-03-01"), categoryId: S.kleidung) == nil)
        #expect(budget.target(in: date("2026-12-01"), categoryId: S.kleidung) == .monthly(80, setAside: false))
    }

    @Test func settingATargetAgainInTheSameMonthReplacesItsVersion() throws {
        var budget = ScenarioBudget().budget
        try set(.monthly(50), in: october, on: &budget)
        try set(.byDate(600, due: date("2027-01-15"), repeatsYearly: true), in: date("2026-10-20"), on: &budget)
        #expect(budget.targetVersions.count == 1)
        #expect(budget.targetVersions.first?.id == EntityID.targetVersion(categoryId: S.kleidung, fromMonth: october))
        #expect(budget.target(in: october, categoryId: S.kleidung)?.cadence == .byDate)
    }

    @Test func endingATargetSetInTheSameMonthLeavesNothingBehind() throws {
        var budget = ScenarioBudget().budget
        try set(.monthly(50), in: october, on: &budget)
        try set(.ended, in: october, on: &budget)
        #expect(budget.targetVersions.isEmpty)
    }

    @Test func aMonthlyTargetDropsItsDateAndRepeat() throws {
        var budget = ScenarioBudget().budget
        try set(
            Target(cadence: .monthly, amount: 50, dueOn: date("2027-01-01"), repeatsYearly: true), in: october,
            on: &budget)
        #expect(budget.target(in: october, categoryId: S.kleidung) == .monthly(50))
    }

    @Test func refusesATargetWithoutAPositiveAmountOrDueBeforeItsFirstMonth() throws {
        var budget = ScenarioBudget().budget
        #expect(throws: BudgetError.targetAmountNotPositive) { try set(.monthly(0), in: october, on: &budget) }
        #expect(throws: BudgetError.targetDueBeforeStart) {
            try set(.byDate(100, due: date("2026-09-30")), in: october, on: &budget)
        }
        #expect(throws: BudgetError.targetDueBeforeStart) {
            try set(Target(cadence: .byDate, amount: 100), in: october, on: &budget)
        }
        #expect(throws: BudgetError.categoryNotFound(ScenarioBudget.readyToAssign)) {
            try budget.apply(
                .setTarget(month: october, categoryId: ScenarioBudget.readyToAssign, target: .monthly(10)))
        }
        try set(.byDate(100, due: date("2026-10-01")), in: october, on: &budget)
    }

    @Test func aSnoozeIsPerCategoryAndMonth() throws {
        var budget = ScenarioBudget().budget
        try budget.apply(.setTargetSnoozed(month: date("2026-10-09"), categoryId: S.kleidung, true))
        #expect(budget.isTargetSnoozed(in: october, categoryId: S.kleidung))
        #expect(budget.targetSnoozes.map(\.month) == [october])
        try budget.apply(.setTargetSnoozed(month: october, categoryId: S.kleidung, false))
        #expect(budget.targetSnoozes.isEmpty)
    }

    @Test func targetsAndSnoozesSaveAndLoad() throws {
        var budget = ScenarioBudget().budget
        try set(.byDate(600, due: date("2027-01-15"), repeatsYearly: true, setAside: false), in: october, on: &budget)
        try set(.ended, in: november, on: &budget)
        try budget.apply(.setTargetSnoozed(month: october, categoryId: S.kleidung, true))
        let loaded = try savedAndLoaded(budget)
        #expect(Set(loaded.targetVersions) == Set(budget.targetVersions))
        #expect(loaded.targetSnoozes == budget.targetSnoozes)
        #expect(budget.targetVersions.map(\.cadence) == [.byDate, .ended])
    }

    @Test func aRepeatingDueDateMovesOnToItsNextDueDate() {
        let target = Target.byDate(600, due: date("2025-01-15"), repeatsYearly: true)
        #expect(target.nextDue(from: date("2026-10-01")) == date("2027-01-15"))
        #expect(target.nextDue(from: date("2027-01-01")) == date("2027-01-15"))
        #expect(Target.byDate(600, due: date("2025-01-15")).nextDue(from: october) == date("2025-01-15"))
    }
}
