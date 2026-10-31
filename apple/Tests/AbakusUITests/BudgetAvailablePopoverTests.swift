import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct BudgetAvailablePopoverTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    /// 100,00 income, Kino −25,00 and Kleidung 60,00 Verfügbar in October.
    private func fixture() -> F {
        var fixture = F()
        fixture.spend(-100, BudgetScreenFixture.readyToAssign, on: "2026-10-01")
        fixture.spend(25, F.kino, on: "2026-10-10")
        fixture.budget(60, F.kleidung, in: "2026-10-01")
        return fixture
    }

    private func figures(_ model: BudgetViewModel, _ category: String) -> BudgetCategoryFigures? {
        model.month(october)?.category(category)
    }

    @Test func coverFromAnotherCategory() throws {
        let (model, _) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        #expect(model.presentedPopup == .available(month: october, categoryId: F.kino))
        #expect(model.popupAnchor == .balance(october, F.kino))
        model.callouts.coverSourceId = F.kleidung
        model.callouts.coverClicked()
        #expect(model.presentedPopup == nil)
        #expect(figures(model, F.kino)?.balance == 0)
        #expect(figures(model, F.kleidung)?.balance == 35)
    }

    @Test func anOverspentCategoryOpensOnCoverFromZuVerteilen() throws {
        let (model, _) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        let form = try #require(model.callouts.availableForm)
        #expect(form.categoryName == "Kino")
        #expect(form.monthTitle == "Oktober 2026")
        #expect(form.isOverspent)
        #expect(form.mode == .cover)
        #expect(form.sources.map(\.categoryId) == [BudgetScreenFixture.readyToAssign, F.kleidung])
        #expect(model.callouts.coverLabel == "Decke 25,00€ aus")
        #expect(model.callouts.coverSourceLabel(try #require(form.sources.first)) == "Zu verteilen · 40,00€")
        #expect(model.callouts.remainingLabel == "Zu verteilen danach")
        #expect(model.callouts.remainingText == "15,00€")
        model.callouts.coverSourceId = F.kleidung
        #expect(model.callouts.remainingLabel == "Kleidung danach")
        #expect(model.callouts.remainingText == "35,00€")
    }

    @Test func coveringFromZuVerteilenRaisesOnlyTheAssignment() {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.coverClicked()
        #expect(
            store.commands.last
                == .moveAssigned(month: october, from: BudgetScreenFixture.readyToAssign, to: F.kino, amount: 25))
        #expect(figures(model, F.kino)?.assigned == 25)
    }

    @Test func withoutMoneyAnywhereThereIsNothingToCoverFrom() throws {
        var fixture = F()
        fixture.spend(25, F.kino, on: "2026-10-10")
        let (model, store) = fixture.model()
        model.balanceClicked(month: october, categoryId: F.kino)
        #expect(try #require(model.callouts.availableForm).sources.isEmpty)
        model.callouts.coverClicked()
        #expect(store.commands.isEmpty)
        #expect(model.callouts.availableForm?.error == "Daraus lässt sich nichts decken.")
    }

    @Test func aCategoryWithMoneyOpensOnMoveToZuVerteilen() throws {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kleidung)
        let form = try #require(model.callouts.availableForm)
        #expect(!form.isOverspent)
        #expect(form.mode == .move)
        #expect(form.amount == "60,00")
        #expect(form.direction == .give)
        #expect(form.otherId == BudgetScreenFixture.readyToAssign)
        #expect(form.others.map(\.name) == ["Alltag", "Sparen", "Freizeit"])
        #expect(form.others[0].categories.map(\.id) == [F.lebensmittel])
        model.callouts.moveAmount = "12,5"
        model.callouts.moveClicked()
        #expect(
            store.commands.last
                == .moveAssigned(month: october, from: F.kleidung, to: BudgetScreenFixture.readyToAssign, amount: 12.5))
        #expect(model.presentedPopup == nil)
    }

    @Test func movingCanTakeFromAnotherCategory() {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.availableMode = .move
        #expect(model.callouts.availableForm?.amount == "25,00")
        #expect(model.callouts.availableForm?.direction == .take)
        model.callouts.moveOtherId = F.kleidung
        model.callouts.moveClicked()
        #expect(store.commands.last == .moveAssigned(month: october, from: F.kleidung, to: F.kino, amount: 25))
    }

    @Test func withoutMoneyAMoveSuggestsWhatTheTargetStillNeeds() throws {
        var fixture = fixture()
        try fixture.budget.apply(.setTarget(month: october, categoryId: F.lebensmittel, target: .monthly(30)))
        try fixture.budget.apply(.setTarget(month: october, categoryId: F.kino, target: .monthly(40)))
        let (model, _) = fixture.model()
        model.balanceClicked(month: october, categoryId: F.lebensmittel)
        #expect(model.callouts.availableForm?.amount == "30,00")
        #expect(model.callouts.availableForm?.direction == .take)
        model.dismissPopup()
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.availableMode = .move
        #expect(model.callouts.availableForm?.amount == "40,00")
    }

    @Test func aMoveNeedsAnAmountAboveZero() {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kleidung)
        model.callouts.moveAmount = "abc"
        model.callouts.moveClicked()
        #expect(model.callouts.availableForm?.error == "Bitte einen Betrag angeben.")
        model.callouts.moveAmount = "-5"
        #expect(model.callouts.availableForm?.error == nil)
        model.callouts.moveClicked()
        #expect(model.callouts.availableForm?.error == "Bitte einen Betrag über null angeben, etwa 12,50.")
        #expect(store.commands.isEmpty)
        #expect(model.presentedPopup == .available(month: october, categoryId: F.kleidung))
    }

    @Test func editCategoryOpensTheCategoryCallout() {
        let (model, _) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.editCategoryClicked()
        #expect(model.presentedPopup == .editCategory(categoryId: F.kino, month: october))
        #expect(model.callouts.category?.categoryId == F.kino)
        #expect(model.callouts.category?.month == october)
        #expect(model.callouts.availableForm == nil)
    }

    @Test func escapeCancelAndAClickOutsideClose() {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        #expect(model.callouts.escapePressed())
        #expect(model.presentedPopup == nil)
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.mouseDownOutside()
        #expect(model.presentedPopup == nil)
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.availableCancelled()
        #expect(model.presentedPopup == nil)
        #expect(model.callouts.availableForm == nil)
        #expect(store.commands.isEmpty)
    }

    @Test func anUnknownCategoryOpensNothing() {
        let (model, _) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.alltag)
        #expect(model.presentedPopup == nil)
    }
}
