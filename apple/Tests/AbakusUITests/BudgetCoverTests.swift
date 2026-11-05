import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct BudgetCoverTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    /// Kino is overspent by 40,00 in October; Kleidung has 20,00 available, Notgroschen 300,00.
    private func fixture(income: Decimal = 0) -> F {
        var fixture = F()
        if income != 0 { fixture.spend(-income, F.readyToAssign, on: "2026-10-01") }
        fixture.spend(40, F.kino, on: "2026-10-10")
        fixture.budget(20, F.kleidung, in: "2026-10-01")
        fixture.budget(300, F.notgroschen, in: "2026-10-01")
        return fixture
    }

    private func available(_ model: BudgetViewModel, _ category: String) -> Decimal? {
        model.month(october)?.category(category)?.balance
    }

    @Test func coveringTakesAsMuchAsTheSourceHolds() throws {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        #expect(model.presentedPopup == .available(month: october, categoryId: F.kino))
        #expect(model.popupAnchor == .balance(october, F.kino))
        model.callouts.cover(from: F.kleidung)
        #expect(model.presentedPopup == nil)
        #expect(store.commands.last == .moveAssigned(month: october, from: F.kleidung, to: F.kino, amount: 20))
        #expect(available(model, F.kleidung) == 0)
        #expect(available(model, F.kino) == -20)
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.cover(from: F.notgroschen)
        #expect(available(model, F.notgroschen) == 280)
        #expect(available(model, F.kino) == 0)
    }

    @Test func theListOffersZuVerteilenFirstThenTheCategoriesWithTheMostFirst() throws {
        let (model, store) = fixture(income: 440).model()
        model.balanceClicked(month: october, categoryId: F.kino)
        let list = try #require(model.callouts.availableForm)
        #expect(model.callouts.coverTitle == "40,00\u{00A0}€ decken aus")
        #expect(list.sources.map(\.categoryId) == [F.readyToAssign, F.notgroschen, F.kleidung])
        #expect(list.sources.map(\.available) == [120, 300, 20])
        model.callouts.cover(from: F.readyToAssign)
        #expect(store.commands.last == .moveAssigned(month: october, from: F.readyToAssign, to: F.kino, amount: 40))
        #expect(available(model, F.kino) == 0)
        #expect(model.month(october)?.free == 80)
    }

    @Test func coveringTakesTheAmountsAsTheyAreWhenTheSourceIsChosen() throws {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        try store.budget.apply(.setAssigned(month: october, categoryId: F.kino, amount: 30))
        try store.budget.apply(.setAssigned(month: october, categoryId: F.kleidung, amount: 5))
        model.callouts.cover(from: F.kleidung)
        #expect(store.commands == [.moveAssigned(month: october, from: F.kleidung, to: F.kino, amount: 5)])
        model.balanceClicked(month: october, categoryId: F.kino)
        try store.budget.apply(.setAssigned(month: october, categoryId: F.kino, amount: 40))
        model.callouts.cover(from: F.notgroschen)
        #expect(store.commands.count == 1)
    }

    @Test func onlySourcesWithMoneyAreOffered() throws {
        let (model, _) = fixture(income: 320).model()
        #expect(model.month(october)?.free == 0)
        model.balanceClicked(month: october, categoryId: F.kino)
        let list = try #require(model.callouts.availableForm)
        #expect(list.sources.map(\.categoryId) == [F.notgroschen, F.kleidung])
    }

    @Test func withoutMoneyAnywhereThereIsNothingToChoose() throws {
        var fixture = F()
        fixture.spend(25, F.kino, on: "2026-10-10")
        let (model, store) = fixture.model()
        model.balanceClicked(month: october, categoryId: F.kino)
        #expect(try #require(model.callouts.availableForm).sources.isEmpty)
        model.callouts.cover(from: F.readyToAssign)
        #expect(store.commands.isEmpty)
    }

    @Test func aVerfuegbarThatIsNotOverspentOpensNothing() {
        let (model, _) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kleidung)
        model.balanceClicked(month: october, categoryId: F.lebensmittel)
        #expect(model.presentedPopup == nil)
    }

    @Test func escapeAndAClickOutsideClose() {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        #expect(model.callouts.escapePressed())
        #expect(model.presentedPopup == nil)
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.mouseDownOutside()
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
