import Foundation
import Testing

@testable import AbakusCore
@testable import AbakusUI

@MainActor
@Suite struct BudgetTargetTests {
    typealias F = BudgetScreenFixture
    let june = day("2026-06-01")
    let october = day("2026-10-01")

    private func opened(_ fixture: F, month: DateWithoutTime? = nil) -> (BudgetViewModel, SpyBudgetStore) {
        let (model, store) = fixture.model()
        model.present(.editCategory(categoryId: F.kleidung, month: month))
        return (model, store)
    }

    private func withTarget(_ target: Target, from month: String = "2026-10-01") -> F {
        var fixture = F()
        fixture.spend(-500, BudgetScreenFixture.readyToAssign, on: "2026-09-01")
        try! fixture.budget.apply(.setTarget(month: day(month), categoryId: F.kleidung, target: target))
        return fixture
    }

    @Test func refillTarget() throws {
        var fixture = withTarget(.monthly(150, setAside: false), from: "2026-05-01")
        try fixture.budget.apply(.renameCategory(categoryId: F.kleidung, name: "Tanken"))
        fixture.budget(40, F.kleidung, in: "2026-05-01")
        let (model, _) = fixture.model()
        model.perform(.setAssigned(month: june, categoryId: F.kleidung, amount: 80))
        model.present(.editCategory(categoryId: F.kleidung, month: june))
        let display = try #require(model.callouts.targetDisplay)
        #expect(display.status.text == "Noch 30,00\u{00A0}€ im Juni")
        #expect(display.status.state == .underfunded)
        let row = model.subRowDisplay(F.kleidung, in: try #require(model.month(june)))
        #expect(row.marker == .underfunded)
        #expect(row.fundedPercent == 72)
        #expect(row.accessibilityValue == "120,00, unterfinanziert, 72 % finanziert")
    }

    @Test func theCalloutShowsTheTargetInTodaysMonthWhenShownElseInTheFirstShownMonth() {
        let (model, _) = opened(F())
        #expect(model.callouts.category?.month == october)
        #expect(model.callouts.targetMonthTitle == "Oktober 2026")
        model.dismissPopup()
        model.select(day("2027-02-01"))
        model.present(.editCategory(categoryId: F.kleidung))
        #expect(model.callouts.category?.month == day("2027-02-01"))
    }

    @Test func onlyAnExistingCategoryHasATarget() {
        let (model, _) = opened(F())
        #expect(model.callouts.category?.hasTarget == true)
        #expect(model.callouts.targetDisplay == nil)
        model.present(.editCategory(categoryId: F.alltag))
        #expect(model.callouts.category?.hasTarget == false)
        model.addSubCategoryClicked(masterId: F.alltag)
        #expect(model.callouts.category?.hasTarget == false)
    }

    @Test func settingANewTargetSavesItFromTheCalloutsMonth() throws {
        let (model, store) = opened(F())
        model.callouts.editTargetClicked()
        let editor = try #require(model.callouts.category?.target)
        #expect(editor.isNew)
        #expect(editor.amount == "")
        #expect(editor.cadence == .monthly)
        #expect(editor.kind == .setAside)
        #expect(editor.dueOn == day("2026-12-31"))
        model.callouts.targetAmount = "150"
        model.callouts.targetKind = .refill
        model.callouts.targetSaveClicked()
        #expect(
            store.commands.last
                == .setTarget(month: october, categoryId: F.kleidung, target: .monthly(150, setAside: false)))
        #expect(model.callouts.category?.target == nil)
        #expect(model.presentedPopup == .editCategory(categoryId: F.kleidung))
        let display = try #require(model.callouts.targetDisplay)
        #expect(display.head == "Jeden Monat auffüllen bis 150,00\u{00A0}€")
        #expect(display.status.text == "Noch 150,00\u{00A0}€ im Oktober")
        #expect(display.assignLabel == nil)
        #expect(display.progress == nil)
    }

    @Test func aTargetByADateShowsItsProgressAndWhereItShouldStand() throws {
        var fixture = withTarget(.byDate(1200, due: day("2027-06-01")))
        fixture.budget(80, F.kleidung, in: "2026-10-01")
        let (model, _) = opened(fixture)
        let display = try #require(model.callouts.targetDisplay)
        #expect(display.head == "Bis zum 1. Juni 2027 weitere 1.200,00\u{00A0}€ zurücklegen")
        #expect(display.status.text == "Noch 53,34\u{00A0}€ im Oktober")
        let progress = try #require(display.progress)
        #expect(progress.label == "80,00 von 1.200,00\u{00A0}€ zurückgelegt")
        #expect(abs(progress.value - 80.0 / 1200) < 1e-9)
        #expect(progress.mark.map { ($0 * 100).rounded() } == 11)
    }

    @Test func aTargetByADateNamesTheMonthsStatusBelowItsBar() throws {
        let byDate = Target.byDate(1200, due: day("2027-06-01"))
        let status = { (assigned: Decimal, spent: Decimal, snoozed: Bool) throws -> (BudgetTargetState, String) in
            var fixture = withTarget(byDate)
            fixture.budget(assigned, F.kleidung, in: "2026-10-01")
            if spent != 0 { fixture.spend(spent, F.kleidung, on: "2026-10-05") }
            if snoozed {
                try fixture.budget.apply(.setTargetSnoozed(month: october, categoryId: F.kleidung, true))
            }
            let (model, _) = opened(fixture)
            let display = try #require(model.callouts.targetDisplay)
            #expect(display.progress != nil)
            return (display.status.state, display.status.text)
        }
        #expect(try status(80, 0, false) == (BudgetTargetState.underfunded, "Noch 53,34\u{00A0}€ im Oktober"))
        #expect(try status(200, 0, false) == (BudgetTargetState.onTrack, "Im Plan"))
        #expect(try status(1200, 0, false) == (BudgetTargetState.met, "Erfüllt"))
        #expect(
            try status(10, 22, false) == (BudgetTargetState.overspent, "Überzogen um 12,00\u{00A0}€"))
        #expect(try status(80, 0, true) == (BudgetTargetState.snoozed, "Pausiert im Oktober"))
    }

    @Test func aTargetByADateWithoutAnAmountIsMetWithAFullBarAndNoMark() throws {
        var fixture = withTarget(.byDate(240, due: day("2027-06-01")))
        // Commands refuse a target without an amount; only a synced row can bring one.
        fixture.budget.targetVersions[0].amount = 0
        let (model, _) = opened(fixture)
        let display = try #require(model.callouts.targetDisplay)
        #expect(display.status.state == .met)
        #expect(display.status.text == "Erfüllt")
        let progress = try #require(display.progress)
        #expect(progress.label == "0,00 von 0,00\u{00A0}€ zurückgelegt")
        #expect(progress.value == 1)
        #expect(progress.mark == nil)
    }

    @Test func aTargetThatSavesUpToAnAmountCountsWhatIsSaved() throws {
        var fixture = withTarget(.byDate(3000, due: day("2027-06-01"), setAside: false))
        fixture.budget(decimal("415.39"), F.kleidung, in: "2026-10-01")
        let (model, _) = opened(fixture)
        let display = try #require(model.callouts.targetDisplay)
        #expect(display.head == "Bis zum 1. Juni 2027 auf 3.000,00\u{00A0}€ ansparen")
        #expect(display.progress?.label == "415,39 von 3.000,00\u{00A0}€ angespart")
    }

    @Test func aMonthlyTargetShowsOnlyItsStatus() throws {
        var fixture = withTarget(.monthly(50))
        fixture.budget(10, F.kleidung, in: "2026-10-01")
        fixture.spend(22, F.kleidung, on: "2026-10-05")
        let (model, _) = opened(fixture)
        let display = try #require(model.callouts.targetDisplay)
        #expect(display.progress == nil)
        #expect(display.status.state == .overspent)
        #expect(display.status.text == "Überzogen um 12,00\u{00A0}€")
        #expect(display.assignLabel == nil)
    }

    @Test func editingARepeatingTargetStartsFromItsNextDueDate() throws {
        let (model, store) = opened(
            withTarget(.byDate(600, due: day("2026-01-15"), repeatsYearly: true, setAside: false), from: "2026-01-01"))
        model.callouts.editTargetClicked()
        let editor = try #require(model.callouts.category?.target)
        #expect(!editor.isNew)
        #expect(editor.amount == "600,00")
        #expect(editor.cadence == .byDate)
        #expect(editor.dueOn == day("2027-01-15"))
        #expect(editor.repeatsYearly)
        #expect(editor.kind == .refill)
        model.callouts.targetAmount = "720"
        model.callouts.targetSaveClicked()
        #expect(
            store.commands.last
                == .setTarget(
                    month: october, categoryId: F.kleidung,
                    target: .byDate(720, due: day("2027-01-15"), repeatsYearly: true, setAside: false)))
    }

    @Test func theEditorShowsTheCoresRefusalInline() throws {
        let (model, store) = opened(F())
        model.callouts.editTargetClicked()
        model.callouts.targetSaveClicked()
        #expect(model.callouts.category?.target?.error == "Bitte einen Betrag angeben.")
        model.callouts.targetAmount = "0"
        #expect(model.callouts.category?.target?.error == nil)
        model.callouts.targetSaveClicked()
        #expect(model.callouts.category?.target?.error == BudgetError.targetAmountNotPositive.localizedDescription)
        model.callouts.targetAmount = "100"
        model.callouts.targetCadence = .byDate
        model.callouts.targetDueOn = day("2026-09-30")
        model.callouts.targetSaveClicked()
        #expect(model.callouts.category?.target?.error == BudgetError.targetDueBeforeStart.localizedDescription)
        #expect(model.dialogs.presented.isEmpty)
        #expect(store.commands.isEmpty)
        model.callouts.targetDueOn = day("2026-10-01")
        model.callouts.targetSaveClicked()
        #expect(
            store.commands.last
                == .setTarget(month: october, categoryId: F.kleidung, target: .byDate(100, due: day("2026-10-01"))))
    }

    @Test func theTargetAmountTakesASumAndRefusesAnotherOperator() throws {
        let (model, store) = opened(F())
        model.callouts.editTargetClicked()
        model.callouts.targetAmount = "60*2"
        model.callouts.targetSaveClicked()
        #expect(store.commands.isEmpty)
        #expect(model.callouts.category?.target?.error == InvalidAmount.content("60*2"))
        #expect(!model.dialogs.isPresenting)
        model.callouts.targetAmount = "50+20"
        model.callouts.targetSaveClicked()
        #expect(store.commands == [.setTarget(month: october, categoryId: F.kleidung, target: .monthly(70))])
    }

    @Test func fertigSavesAnOpenTargetEditorAndStaysOpenWhenItRefuses() throws {
        let (model, store) = opened(F())
        model.callouts.editTargetClicked()
        model.callouts.mouseDownOutside()
        #expect(model.presentedPopup == .editCategory(categoryId: F.kleidung))
        model.callouts.targetAmount = "0"
        model.callouts.categoryDone()
        #expect(model.callouts.category?.target?.error == BudgetError.targetAmountNotPositive.localizedDescription)
        #expect(model.presentedPopup == .editCategory(categoryId: F.kleidung))
        model.callouts.targetAmount = "150"
        model.callouts.categoryDone()
        #expect(store.commands == [.setTarget(month: october, categoryId: F.kleidung, target: .monthly(150))])
        #expect(model.presentedPopup == nil)
    }

    @Test func deletingATargetAsksThenEndsItFromTheMonth() throws {
        let (model, store) = opened(withTarget(.monthly(50), from: "2026-09-01"))
        model.callouts.editTargetClicked()
        model.callouts.deleteTargetClicked()
        let dialog = try #require(model.dialogs.presented.last)
        #expect(dialog.dialog.instruction == "Ziel löschen?")
        #expect(dialog.dialog.content == "Die Kategorie hat ab diesem Monat kein Ziel mehr.")
        dialog.answer(TargetDeleteChoice.cancel)
        #expect(store.commands.isEmpty)
        model.callouts.deleteTargetClicked()
        try #require(model.dialogs.presented.last).answer(TargetDeleteChoice.delete)
        #expect(store.commands == [.setTarget(month: october, categoryId: F.kleidung, target: .ended)])
        #expect(model.callouts.targetDisplay == nil)
        #expect(model.month(day("2026-09-01"))?.category(F.kleidung)?.target != nil)
    }

    @Test func snoozingPausesTheTargetForTheMonth() throws {
        let (model, store) = opened(withTarget(.monthly(50)))
        #expect(model.callouts.targetDisplay?.snoozeTitle == "Pausieren")
        model.callouts.snoozeClicked()
        #expect(store.commands == [.setTargetSnoozed(month: october, categoryId: F.kleidung, true)])
        let display = try #require(model.callouts.targetDisplay)
        #expect(display.status.text == "Pausiert im Oktober")
        #expect(display.snoozeTitle == "Fortsetzen")
        #expect(display.assignLabel == nil)
        #expect(model.subRowDisplay(F.kleidung, in: try #require(model.month(october))).marker == .snoozed)
        model.callouts.snoozeClicked()
        #expect(store.commands.last == .setTargetSnoozed(month: october, categoryId: F.kleidung, false))
        #expect(model.callouts.targetDisplay?.snoozeTitle == "Pausieren")
    }

    @Test func zuweisenAssignsWhatIsStillMissingFromZuVerteilen() throws {
        var fixture = withTarget(.monthly(50))
        fixture.budget(20, F.kleidung, in: "2026-10-01")
        let (model, store) = opened(fixture)
        model.callouts.assignTargetClicked()
        #expect(
            store.commands
                == [.moveAssigned(month: october, from: BudgetScreenFixture.readyToAssign, to: F.kleidung, amount: 30)])
        #expect(model.callouts.targetDisplay?.status.text == "Erfüllt")
        #expect(model.subRowDisplay(F.kleidung, in: try #require(model.month(october))).marker == .funded)
    }

    @Test func zuweisenAssignsNoMoreThanZuVerteilenHas() {
        var fixture = withTarget(.monthly(50))
        fixture.budget(480, F.lebensmittel, in: "2026-10-01")
        let (model, store) = opened(fixture)
        #expect(model.callouts.targetDisplay?.assignLabel == "20,00\u{00A0}€ zuweisen")
        model.callouts.assignTargetClicked()
        #expect(
            store.commands
                == [.moveAssigned(month: october, from: BudgetScreenFixture.readyToAssign, to: F.kleidung, amount: 20)])
        #expect(model.callouts.targetDisplay?.status.text == "Noch 30,00\u{00A0}€ im Oktober")
        #expect(model.callouts.targetDisplay?.assignLabel == nil)
        model.callouts.assignTargetClicked()
        #expect(store.commands.count == 1)
    }

    @Test func anUnderfundedTargetIsMarkedOnlyInAMonthBeingBudgeted() throws {
        let (model, _) = withTarget(.monthly(50)).model()
        #expect(model.subRowDisplay(F.kleidung, in: try #require(model.month(october))).marker == .underfunded)
        #expect(model.subRowDisplay(F.kleidung, in: try #require(model.month(day("2026-11-01")))).marker == nil)
    }

    @Test func escapeClosesTheTargetEditorBeforeTheCallout() {
        let (model, _) = opened(F())
        model.callouts.editTargetClicked()
        #expect(model.callouts.escapePressed())
        #expect(model.callouts.category?.target == nil)
        #expect(model.presentedPopup == .editCategory(categoryId: F.kleidung))
        #expect(model.callouts.escapePressed())
        #expect(model.presentedPopup == nil)
    }
}
