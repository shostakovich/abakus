import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct BudgetMonthMenuTests {
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

    @Test func theMenuFillsWithWhatItWillMoveAndResetsTheAssignments() {
        var fixture = fixture()
        fixture.budget(10, F.kino, in: "2026-10-01")
        let model = fixture.model().model
        let items = model.callouts.monthMenu(month: october)
        #expect(items.map(\.title) == ["Ziele füllen", "Zurücksetzen …"])
        #expect(items.map(\.kind) == [.action(.fillUnderfunded), .action(.resetAssigned)])
        #expect(items.map(\.isEnabled) == [true, true])
        #expect(items.map(\.subtitle) == ["90,00\u{00A0}€", "Zuweisungen im Okt"])
        #expect(items.map(\.systemImage) == ["target", "arrow.counterclockwise"])
        #expect(items.map(\.isDestructive) == [false, true])
    }

    @Test func touchResetsWithoutTheMacsEllipsis() {
        let model = fixture().model().model
        model.touchLayout = .phone
        #expect(model.callouts.monthMenu(month: october).map(\.title) == ["Ziele füllen", "Zurücksetzen"])
    }

    @Test func withoutMoneyToAssignFillingIsDimmedWithItsReason() {
        var fixture = fixture(income: 0)
        fixture.budget(10, F.kino, in: "2026-10-01")
        let model = fixture.model().model
        #expect(model.month(october)?.free ?? 0 <= 0)
        let items = model.callouts.monthMenu(month: october)
        #expect(items.map(\.title) == ["Ziele füllen", "Zurücksetzen …"])
        #expect(items.map(\.isEnabled) == [false, true])
        #expect(items.map(\.subtitle) == ["Nichts zu verteilen", "Zuweisungen im Okt"])
    }

    @Test func withNothingUnderfundedFillingIsDimmedWithItsReason() {
        var fixture = F()
        fixture.spend(-100, BudgetScreenFixture.readyToAssign, on: "2026-10-01")
        let model = fixture.model().model
        let items = model.callouts.monthMenu(month: october)
        #expect(items.map(\.title) == ["Ziele füllen", "Zurücksetzen …"])
        #expect(items.map(\.isEnabled) == [false, false])
        #expect(items.map(\.subtitle) == ["Nichts unterfinanziert", "Nichts zugewiesen"])
    }

    @Test func nothingUnderfundedIsTheReasonAlsoWithoutMoney() {
        let model = F().model().model
        #expect(model.callouts.monthMenu(month: october).first?.subtitle == "Nichts unterfinanziert")
    }

    @Test func fillUnderfundedWithTooLittleZuVerteilenFillsInBudgetOrderAndSkipsASnoozedTarget() throws {
        var fixture = fixture()
        try fixture.budget.apply(.setTarget(month: october, categoryId: F.lebensmittel, target: .monthly(30)))
        try fixture.budget.apply(.setTargetSnoozed(month: october, categoryId: F.lebensmittel, true))
        let (model, store) = fixture.model()
        model.present(.monthMenu(month: october))
        model.callouts.monthMenuChosen(.fillUnderfunded, month: october)
        model.callouts.monthMenuClosed()
        #expect(store.commands == [.fillUnderfunded(month: october, today: F.today)])
        #expect(!model.dialogs.isPresenting)
        #expect(model.presentedPopup == nil)
        let month = try #require(model.month(october))
        #expect(month.category(F.lebensmittel)?.assigned == 0)
        #expect(month.category(F.kleidung)?.assigned == 40)
        #expect(month.category(F.notgroschen)?.assigned == 60)
        #expect(month.available == 0)
    }

    @Test func resettingAsksFirstAndSetsEveryAssignmentToZero() throws {
        var fixture = fixture()
        fixture.budget(10, F.kino, in: "2026-10-01")
        fixture.budget(30, F.kleidung, in: "2026-10-01")
        let (model, store) = fixture.model()
        model.present(.monthMenu(month: october))
        model.callouts.monthMenuChosen(.resetAssigned, month: october)
        model.callouts.monthMenuClosed()
        let dialog = try #require(model.dialogs.presented.last)
        #expect(dialog.dialog.instruction == "Alle Zuweisungen im Oktober zurücksetzen?")
        #expect(dialog.dialog.content == "Zu verteilen bekommt das Geld zurück.")
        #expect(dialog.dialog.buttons.map(\.title) == ["Abbrechen", "Zurücksetzen"])
        dialog.answer(ResetAssignedChoice.cancel)
        #expect(store.commands.isEmpty)
        model.callouts.monthMenuChosen(.resetAssigned, month: october)
        try #require(model.dialogs.presented.last).answer(ResetAssignedChoice.reset)
        #expect(store.commands == [.resetAssigned(month: october)])
        #expect(model.month(october)?.category(F.kino)?.assigned == 0)
        #expect(model.month(october)?.category(F.kleidung)?.assigned == 0)
    }
}
