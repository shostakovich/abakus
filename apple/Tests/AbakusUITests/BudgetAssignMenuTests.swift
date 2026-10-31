import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct BudgetAssignMenuTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    /// 100,00 income in October; Kleidung asks 40,00 a month, Notgroschen 120,00.
    private func fixture(income: Decimal = 100) -> F {
        var fixture = F()
        if income != 0 { fixture.spend(-income, BudgetScreenFixture.readyToAssign, on: "2026-10-01") }
        for (category, amount) in [(F.kleidung, Decimal(40)), (F.notgroschen, 120)] {
            try! fixture.budget.apply(.setTarget(month: october, categoryId: category, target: .monthly(amount)))
        }
        return fixture
    }

    @Test func theMenuStartsWithFillingTheUnderfundedAndAssigningToOneCategory() {
        let model = fixture().model().model
        let items = model.callouts.quickBudgetMenu(month: october)
        #expect(items.prefix(3).map(\.title) == ["Unterfinanzierte füllen (160,00€)", "In eine Kategorie …", ""])
        #expect(items[0].kind == .action(.fillUnderfunded))
        #expect(items[1].kind == .action(.assignToCategory))
        #expect(items[2].kind == .separator)
        #expect(items.prefix(2).map(\.isEnabled) == [true, true])
        #expect(items[3].title == "Leere Zuweisungen füllen mit:")
    }

    @Test func withoutMoneyToAssignBothAreDisabled() {
        let model = fixture(income: 0).model().model
        let items = model.callouts.quickBudgetMenu(month: october)
        #expect(items[0].title == "Unterfinanzierte füllen (160,00€)")
        #expect(items.prefix(2).map(\.isEnabled) == [false, false])
    }

    @Test func withNothingUnderfundedFillingIsDisabled() {
        var fixture = F()
        fixture.spend(-100, BudgetScreenFixture.readyToAssign, on: "2026-10-01")
        let model = fixture.model().model
        let items = model.callouts.quickBudgetMenu(month: october)
        #expect(items[0].title == "Unterfinanzierte füllen")
        #expect(!items[0].isEnabled)
        #expect(items[1].isEnabled)
    }

    @Test func fillUnderfundedWithTooLittleZuVerteilenFillsInBudgetOrderAndSkipsASnoozedTarget() throws {
        var fixture = fixture()
        try fixture.budget.apply(.setTarget(month: october, categoryId: F.lebensmittel, target: .monthly(30)))
        try fixture.budget.apply(.setTargetSnoozed(month: october, categoryId: F.lebensmittel, true))
        let (model, store) = fixture.model()
        model.present(.monthQuickBudget(month: october))
        model.callouts.quickBudgetMenuChosen(.fillUnderfunded, month: october)
        model.callouts.quickBudgetMenuClosed()
        #expect(store.commands == [.fillUnderfunded(month: october, today: F.today)])
        #expect(!model.dialogs.isPresenting)
        #expect(model.presentedPopup == nil)
        let month = try #require(model.month(october))
        #expect(month.category(F.lebensmittel)?.assigned == 0)
        #expect(month.category(F.kleidung)?.assigned == 40)
        #expect(month.category(F.notgroschen)?.assigned == 60)
        #expect(month.available == 0)
    }

    @Test func assigningToOneCategoryOpensAtTheMenuAndSuggestsTheFirstUnderfunded() throws {
        let (model, _) = fixture().model()
        model.present(.monthQuickBudget(month: october))
        model.callouts.quickBudgetMenuChosen(.assignToCategory, month: october)
        model.callouts.quickBudgetMenuClosed()
        #expect(model.presentedPopup == .assignToCategory(month: october))
        #expect(model.popupAnchor == .monthQuickBudget(october))
        let form = try #require(model.callouts.assignForm)
        #expect(form.monthTitle == "Oktober 2026")
        #expect(form.freeText == "Frei zu verteilen: 100,00€")
        #expect(form.categoryId == F.kleidung)
        #expect(form.amount == "40,00")
        #expect(form.categories.map(\.name) == ["Alltag", "Sparen", "Freizeit"])
        #expect(form.categories[0].categories.map(\.id) == [F.lebensmittel, F.kleidung])
    }

    @Test func choosingACategorySuggestsWhatItStillNeedsAsFarAsZuVerteilenReaches() {
        let (model, store) = fixture().model()
        model.present(.assignToCategory(month: october))
        model.callouts.assignCategoryId = F.notgroschen
        #expect(model.callouts.assignForm?.amount == "100,00")
        model.callouts.assignCategoryId = F.kino
        #expect(model.callouts.assignForm?.amount == "100,00")
        model.callouts.assignAmount = "25"
        model.callouts.assignClicked()
        #expect(
            store.commands
                == [.moveAssigned(month: october, from: BudgetScreenFixture.readyToAssign, to: F.kino, amount: 25)])
        #expect(model.presentedPopup == nil)
        #expect(model.month(october)?.available == 75)
    }

    @Test func theAmountReadsLikeTheBudgetCells() {
        let (model, store) = fixture().model()
        model.present(.assignToCategory(month: october))
        model.callouts.assignCategoryId = F.kino
        model.callouts.assignAmount = "2.5"
        model.callouts.assignClicked()
        #expect(
            store.commands.last
                == .moveAssigned(month: october, from: BudgetScreenFixture.readyToAssign, to: F.kino, amount: 25))
    }

    @Test func withoutATargetAnywhereTheFirstCategoryGetsAllOfZuVerteilen() throws {
        var fixture = F()
        fixture.spend(-100, BudgetScreenFixture.readyToAssign, on: "2026-10-01")
        let (model, _) = fixture.model()
        model.present(.assignToCategory(month: october))
        let form = try #require(model.callouts.assignForm)
        #expect(form.categoryId == F.lebensmittel)
        #expect(form.amount == "100,00")
    }

    @Test func anEmptyFirstGroupFallsBackToTheFirstCategoryOverall() throws {
        var fixture = F()
        fixture.spend(-100, BudgetScreenFixture.readyToAssign, on: "2026-10-01")
        try fixture.budget.apply(.addCategoryGroup(groupId: "EMPTY"))
        let (model, _) = fixture.model()
        model.present(.assignToCategory(month: october))
        let form = try #require(model.callouts.assignForm)
        #expect(form.categoryId == F.lebensmittel)
    }

    @Test func anAssignmentNeedsAnAmountAboveZero() {
        let (model, store) = fixture().model()
        model.present(.assignToCategory(month: october))
        model.callouts.assignAmount = ""
        model.callouts.assignClicked()
        #expect(model.callouts.assignForm?.error == "Bitte einen Betrag angeben.")
        model.callouts.assignAmount = "0"
        #expect(model.callouts.assignForm?.error == nil)
        model.callouts.assignClicked()
        #expect(model.callouts.assignForm?.error == "Bitte einen Betrag über null angeben, etwa 12,50.")
        #expect(store.commands.isEmpty)
        #expect(model.presentedPopup == .assignToCategory(month: october))
    }

    @Test func escapeCancelAndAClickOutsideClose() {
        let (model, store) = fixture().model()
        model.present(.assignToCategory(month: october))
        #expect(model.callouts.escapePressed())
        #expect(model.presentedPopup == nil)
        model.present(.assignToCategory(month: october))
        model.callouts.mouseDownOutside()
        #expect(model.presentedPopup == nil)
        model.present(.assignToCategory(month: october))
        model.callouts.assignCancelled()
        #expect(model.presentedPopup == nil)
        #expect(model.callouts.assignForm == nil)
        #expect(store.commands.isEmpty)
    }
}
