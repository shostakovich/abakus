import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct BudgetUndoTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    /// Kino is overspent by 40,00 in October; 👕 Kleidung has 20,00, Notgroschen 300,00, Zu verteilen 100,00.
    private func fixture() -> F {
        var fixture = F()
        try! fixture.budget.apply(.renameCategory(categoryId: F.kleidung, name: "👕 Kleidung"))
        fixture.spend(-420, F.readyToAssign, on: "2026-10-01")
        fixture.spend(40, F.kino, on: "2026-10-10")
        fixture.budget(20, F.kleidung, in: "2026-10-01")
        fixture.budget(300, F.notgroschen, in: "2026-10-01")
        return fixture
    }

    private func assigned(_ model: BudgetViewModel, _ category: String) -> Decimal? {
        model.month(october)?.category(category)?.assigned
    }

    @Test func coveringOffersToUndoWhatItMoved() throws {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.cover(from: F.kleidung)
        let notice = try #require(model.undoNotice)
        #expect(notice.message == "20,00\u{00A0}€ aus Kleidung gedeckt.")
        model.undoNoticeClicked()
        #expect(
            store.commands.last
                == .changeAssigned(
                    month: october,
                    [
                        AssignedChange(categoryId: F.kleidung, amount: 20),
                        AssignedChange(categoryId: F.kino, amount: -20),
                    ]))
        #expect(assigned(model, F.kleidung) == 20)
        #expect(assigned(model, F.kino) == 0)
        #expect(model.undoNotice == nil)
    }

    @Test func coveringFromZuVerteilenGivesItBack() throws {
        let (model, _) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.cover(from: F.readyToAssign)
        #expect(model.undoNotice?.message == "40,00\u{00A0}€ aus „Zu verteilen“ gedeckt.")
        #expect(model.month(october)?.free == 60)
        model.undoNoticeClicked()
        #expect(model.month(october)?.free == 100)
        #expect(model.month(october)?.category(F.kino)?.balance == -40)
    }

    @Test func afterUndoTheCategoryCanBeCoveredAgain() throws {
        let (model, _) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.cover(from: F.notgroschen)
        model.undoNoticeClicked()
        model.balanceClicked(month: october, categoryId: F.kino)
        let form = try #require(model.callouts.availableForm)
        #expect(form.readyToAssign?.available == 100)
        #expect(form.categories.map(\.categoryId) == [F.notgroschen, F.kleidung])
        model.callouts.cover(from: F.notgroschen)
        #expect(assigned(model, F.notgroschen) == 260)
        #expect(model.month(october)?.category(F.kino)?.balance == 0)
    }

    @Test func fillingOffersToUndoEveryCategoryItFilled() throws {
        var fixture = fixture()
        for (category, amount) in [(F.lebensmittel, Decimal(30)), (F.kleidung, 50)] {
            try fixture.budget.apply(.setTarget(month: october, categoryId: category, target: .monthly(amount)))
        }
        let (model, _) = fixture.model()
        model.callouts.monthMenuChosen(.fillUnderfunded, month: october)
        #expect(model.undoNotice?.message == "Ziele mit 60,00\u{00A0}€ gefüllt.")
        #expect(assigned(model, F.lebensmittel) == 30)
        #expect(assigned(model, F.kleidung) == 50)
        model.undoNoticeClicked()
        #expect(assigned(model, F.lebensmittel) == 0)
        #expect(assigned(model, F.kleidung) == 20)
        #expect(model.month(october)?.free == 100)
    }

    @Test func zuweisenOffersToUndo() throws {
        var fixture = fixture()
        try fixture.budget.apply(.setTarget(month: october, categoryId: F.kleidung, target: .monthly(50)))
        let (model, _) = fixture.model()
        model.present(.editCategory(categoryId: F.kleidung))
        model.callouts.assignTargetClicked()
        #expect(model.undoNotice?.message == "30,00\u{00A0}€ Kleidung zugewiesen.")
        model.undoNoticeClicked()
        #expect(assigned(model, F.kleidung) == 20)
    }

    @Test func theNoticeEndsWithTheNextChangeOrWhenItExpires() throws {
        let (model, store) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.cover(from: F.kleidung)
        model.assign("5", to: model.cell(F.lebensmittel))
        #expect(model.undoNotice == nil)
        model.undoNoticeClicked()
        #expect(assigned(model, F.kleidung) == 0)
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.cover(from: F.notgroschen)
        let notice = try #require(model.undoNotice)
        model.undoNoticeExpired(notice.id)
        #expect(model.undoNotice == nil)
        #expect(store.commands.filter { if case .changeAssigned = $0 { true } else { false } }.isEmpty)
    }

    @Test func aNoticeEndedByItsViewNeverComesBack() async throws {
        let (model, _) = fixture().model()
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.cover(from: F.kleidung)
        let notice = try #require(model.undoNotice)
        let shown = Task { await model.undoNoticeShown(notice) }
        shown.cancel()
        await shown.value
        #expect(model.undoNotice == nil)
        model.balanceClicked(month: october, categoryId: F.kino)
        model.callouts.cover(from: F.notgroschen)
        model.leave()
        #expect(model.undoNotice == nil)
    }

    @Test func nothingMovedOffersNothing() {
        var fixture = F()
        fixture.spend(25, F.kino, on: "2026-10-10")
        let (model, _) = fixture.model()
        model.callouts.monthMenuChosen(.fillUnderfunded, month: october)
        #expect(model.undoNotice == nil)
    }

    @Test func theWindowsUndoManagerUndoesAndRedoesIt() throws {
        let (model, _) = fixture().model()
        let manager = UndoManager()
        manager.groupsByEvent = false
        model.undoManager = manager
        model.balanceClicked(month: october, categoryId: F.kino)
        manager.beginUndoGrouping()
        model.callouts.cover(from: F.kleidung)
        manager.endUndoGrouping()
        #expect(manager.undoActionName == "Decken")
        manager.undo()
        #expect(assigned(model, F.kleidung) == 20)
        #expect(model.undoNotice == nil)
        #expect(manager.canRedo)
        manager.redo()
        #expect(assigned(model, F.kleidung) == 0)
        #expect(assigned(model, F.kino) == 20)
    }

    @Test func undoingFromTheNoticeTakesItOffTheUndoManager() throws {
        let (model, _) = fixture().model()
        let manager = UndoManager()
        manager.groupsByEvent = false
        model.undoManager = manager
        model.balanceClicked(month: october, categoryId: F.kino)
        manager.beginUndoGrouping()
        model.callouts.cover(from: F.kleidung)
        manager.endUndoGrouping()
        model.undoNoticeClicked()
        #expect(!manager.canUndo)
        #expect(assigned(model, F.kleidung) == 20)
    }

    private func coveredWithUndoManager() -> (BudgetViewModel, SpyBudgetStore, UndoManager) {
        let (model, store) = fixture().model()
        let manager = UndoManager()
        manager.groupsByEvent = false
        model.undoManager = manager
        model.balanceClicked(month: october, categoryId: F.kino)
        manager.beginUndoGrouping()
        model.callouts.cover(from: F.kleidung)
        manager.endUndoGrouping()
        return (model, store, manager)
    }

    @Test func aLaterEditTakesTheActionOffTheUndoManager() {
        let (model, _, manager) = coveredWithUndoManager()
        model.assign("5", to: model.cell(F.lebensmittel))
        #expect(!manager.canUndo)
        #expect(assigned(model, F.kleidung) == 0)
        #expect(assigned(model, F.kino) == 20)
    }

    @Test func aResetTakesTheActionOffTheUndoManager() throws {
        let (model, _, manager) = coveredWithUndoManager()
        model.callouts.monthMenuChosen(.resetAssigned, month: october)
        try #require(model.dialogs.presented.last).answer(ResetAssignedChoice.reset)
        #expect(!manager.canUndo)
        #expect(assigned(model, F.kleidung) == 0)
        #expect(assigned(model, F.kino) == 0)
    }

    @Test func undoAfterAWriteFromElsewhereChangesNothing() throws {
        let (model, store, manager) = coveredWithUndoManager()
        store.budget = try store.budget.applying(
            .setAssigned(month: october, categoryId: F.lebensmittel, amount: 5))
        manager.undo()
        #expect(assigned(model, F.kleidung) == 0)
        #expect(assigned(model, F.kino) == 20)
        #expect(!manager.canRedo)
    }
}
