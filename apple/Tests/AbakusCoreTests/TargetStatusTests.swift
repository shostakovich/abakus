import Foundation
import Testing

@testable import AbakusCore

/// Abakus's `test/abakus_web/live/budget_live/status_test.exs`, its amounts in euros instead of cents.
@Suite struct TargetStatusTests {
    let october = date("2026-10-01")

    private func row(
        balance: Decimal = 0, underfunded: Decimal = 0, snoozed: Bool = false, saved: Decimal? = nil,
        target: Target? = .monthly(50)
    ) -> BudgetCategoryFigures {
        BudgetCategoryFigures(
            assigned: 0, spent: 0, balance: balance, transactionCount: 0,
            target: target.map {
                BudgetTargetFigures(
                    target: $0, needed: underfunded, underfunded: underfunded, progress: 0, saved: saved,
                    isSnoozed: snoozed)
            })
    }

    @Test func verfuegbarIsAmberWhileUnderfundedCheckedWhenFundedAndPausedWhenSnoozed() {
        #expect(row(balance: -1, underfunded: 0.5).availableMarker(isBeingBudgeted: true) == nil)
        #expect(row(balance: 1, underfunded: 0.5).availableMarker(isBeingBudgeted: true) == .underfunded)
        #expect(row(balance: 1).availableMarker(isBeingBudgeted: true) == .funded)
        #expect(row(balance: 1, underfunded: 0.5, snoozed: true).availableMarker(isBeingBudgeted: true) == .snoozed)
        #expect(row(snoozed: true).availableMarker(isBeingBudgeted: true) == .snoozed)
        #expect(row(balance: 1, target: nil).availableMarker(isBeingBudgeted: true) == nil)
        #expect(row(balance: 0).availableMarker(isBeingBudgeted: true) == nil)
    }

    @Test func anUnderfundedTargetStaysUnmarkedInAMonthNotBeingBudgeted() {
        #expect(row(balance: 1, underfunded: 0.5).availableMarker(isBeingBudgeted: false) == nil)
        #expect(row(balance: 1).availableMarker(isBeingBudgeted: false) == .funded)
        #expect(row(underfunded: 0.5, snoozed: true).availableMarker(isBeingBudgeted: false) == .snoozed)
    }

    @Test func aMonthIsBeingBudgetedWhenItIsCurrentOrHasMoneyAssigned() throws {
        var scenario = ScenarioBudget()
        try scenario.budget(-5, ScenarioBudget.kleidung, in: "2026-09-01")
        #expect(scenario.month("2026-10-01").isBeingBudgeted)
        #expect(!scenario.month("2026-11-01").isBeingBudgeted)
        #expect(scenario.month("2026-09-01").isBeingBudgeted)
        #expect(!scenario.month("2026-08-01").isBeingBudgeted)
    }

    @Test func aMonthlyTargetInOneSentence() {
        #expect(german.targetHead(.monthly(50)) == "Jeden Monat weitere 50,00€ zurücklegen")
        #expect(german.targetHead(.monthly(650, setAside: false)) == "Jeden Monat auffüllen bis 650,00€")
    }

    @Test func aTargetByADateNamesItsDateARepeatingOneWithoutTheYear() {
        #expect(
            german.targetHead(.byDate(1200, due: date("2027-06-01")))
                == "Bis zum 1. Juni 2027 weitere 1.200,00€ zurücklegen")
        #expect(
            german.targetHead(.byDate(1200, due: date("2027-06-01"), repeatsYearly: true, setAside: false))
                == "Jedes Jahr bis zum 1. Juni auf 1.200,00€ ansparen")
    }

    @Test func theStatusIsOneSentenceOverspentFirstThenPausedStillMissingFunded() {
        #expect(german.targetStatus(row(balance: 5, target: nil), month: october) == nil)
        #expect(
            german.targetStatus(row(balance: decimal("-180.20"), snoozed: true), month: october)
                == BudgetTargetStatus(state: .overspent, text: "Überzogen um 180,20€."))
        #expect(
            german.targetStatus(row(underfunded: 0.10, snoozed: true), month: october)
                == BudgetTargetStatus(state: .snoozed, text: "Pausiert im Oktober."))
        #expect(
            german.targetStatus(row(underfunded: decimal("68.34")), month: october)
                == BudgetTargetStatus(state: .underfunded, text: "Noch 68,34€ diesen Monat."))
        #expect(german.targetStatus(row(), month: october) == BudgetTargetStatus(state: .met, text: "Erfüllt."))
    }

    @Test func aTargetByADateIsOnTrackUntilItsAmountIsSaved() {
        let byDate = Target.byDate(1200, due: date("2027-06-01"))
        #expect(german.targetStatus(row(balance: 80, saved: 80, target: byDate), month: october)?.text == "Im Plan.")
        #expect(
            german.targetStatus(row(balance: 1200, saved: 1200, target: byDate), month: october)?.text == "Erfüllt.")
    }

    @Test func theBarMarksWhereATargetByADateShouldStandAfterThisMonth() throws {
        let byDate = Target.byDate(1200, due: date("2027-06-01"))
        let open = try #require(row(underfunded: decimal("53.34"), saved: 80, target: byDate).target?.mark)
        #expect((open * 100).rounded() == 11)
        let snoozed = try #require(
            row(underfunded: decimal("53.34"), snoozed: true, saved: 80, target: byDate).target?.mark)
        #expect((snoozed * 100).rounded() == 7)
        #expect(
            german.targetSavedLabel(try #require(row(saved: 80, target: byDate).target))
                == "Angespart 80,00 von 1.200,00€")
    }
}
