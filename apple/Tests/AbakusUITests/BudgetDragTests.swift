import AbakusCore
import CoreGraphics
import Foundation
import Testing

@testable import AbakusUI

/// Row tops: Alltag 0, Lebensmittel 32, Kleidung 64, Sparen 96, Notgroschen 128, Freizeit 160, Kino 192.
@MainActor
@Suite struct BudgetDragTests {
    typealias F = BudgetScreenFixture

    private func dragged(_ rowId: String, from y: CGFloat, to target: CGFloat, fixture: F = F()) -> (
        model: BudgetViewModel, store: SpyBudgetStore
    ) {
        let (model, store) = fixture.model()
        model.dragPressed(rowId: rowId, at: CGPoint(x: 40, y: y))
        model.dragMoved(to: CGPoint(x: 60, y: target))
        return (model, store)
    }

    @Test func nothingMovesBeforeElevenPoints() {
        let model = F().model().model
        model.dragPressed(rowId: F.kleidung, at: CGPoint(x: 40, y: 80))
        model.dragMoved(to: CGPoint(x: 51, y: 91))
        #expect(model.drag?.isActive == false)
        model.dragMoved(to: CGPoint(x: 40, y: 92))
        #expect(model.drag?.isActive == true)
        #expect(model.drag?.proxyOffset == CGSize(width: 0, height: 64 + 12))
        model.dragPressed(rowId: EntityID.uncategorizedMasterCategory, at: CGPoint(x: 40, y: 232))
        #expect(model.drag?.rowId == F.kleidung)
    }

    @Test func aSubDroppedOnASubOfItsMaster() {
        let bottom = dragged(F.kleidung, from: 80, to: 54).model
        #expect(
            bottom.drag?.target
                == BudgetDropTarget(
                    lineBelow: F.lebensmittel,
                    command: .moveCategory(categoryId: F.kleidung, toGroupId: F.alltag, index: 1)))
        let top = dragged(F.kino, from: 204, to: 36).model
        #expect(
            top.drag?.target
                == BudgetDropTarget(
                    lineBelow: nil,
                    command: .moveCategory(categoryId: F.kino, toGroupId: F.alltag, index: 0)))
        let second = dragged(F.kino, from: 204, to: 68).model
        #expect(second.drag?.target?.lineBelow == F.lebensmittel)
        #expect(dragged(F.kleidung, from: 80, to: 87).model.drag?.target == nil)
    }

    @Test func aSubWhoseNameIsTakenShowsNoLineButStillTargetsTheMaster() throws {
        var fixture = F()
        try fixture.budget.apply(.renameCategory(categoryId: F.notgroschen, name: "kino"))
        #expect(
            dragged(F.kino, from: 204, to: 150, fixture: fixture).model.drag?.target
                == BudgetDropTarget(
                    lineBelow: nil, command: .moveCategory(categoryId: F.kino, toGroupId: F.sparen, index: 1)))
        #expect(
            dragged(F.kino, from: 204, to: 116, fixture: fixture).model.drag?.target?.command
                == .moveCategory(categoryId: F.kino, toGroupId: F.sparen, index: 0))
        #expect(
            dragged(F.kino, from: 204, to: 54, fixture: fixture).model.drag?.target
                == BudgetDropTarget(
                    lineBelow: F.lebensmittel,
                    command: .moveCategory(categoryId: F.kino, toGroupId: F.alltag, index: 1)))
    }

    @Test func aSubOverAMasterHeaderJoinsThePreviousMasterOrHeadsThisOne() throws {
        let top = dragged(F.kino, from: 204, to: 102).model
        #expect(
            top.drag?.target
                == BudgetDropTarget(
                    lineBelow: nil,
                    command: .moveCategory(categoryId: F.kino, toGroupId: F.alltag, index: 2)))
        let bottom = dragged(F.kino, from: 204, to: 119).model
        #expect(
            bottom.drag?.target
                == BudgetDropTarget(
                    lineBelow: nil,
                    command: .moveCategory(categoryId: F.kino, toGroupId: F.sparen, index: 0)))
        let first = dragged(F.kino, from: 204, to: 6).model
        #expect(first.drag?.target?.command == .moveCategory(categoryId: F.kino, toGroupId: F.alltag, index: 0))
        var fixture = F()
        try fixture.budget.apply(.renameCategory(categoryId: F.kleidung, name: "Kino"))
        let clash = dragged(F.kino, from: 204, to: 102, fixture: fixture).model
        #expect(clash.drag?.target?.command == .moveCategory(categoryId: F.kino, toGroupId: F.alltag, index: 2))
    }

    @Test func aMasterGoesBeforeOrAfterTheGroupUnderThePointer() {
        let before = dragged(F.freizeit, from: 167, to: 15).model
        #expect(
            before.drag?.target
                == BudgetDropTarget(
                    lineBelow: nil, command: .moveCategoryGroup(groupId: F.freizeit, index: 0))
        )
        let after = dragged(F.freizeit, from: 167, to: 73).model
        #expect(
            after.drag?.target
                == BudgetDropTarget(
                    lineBelow: nil, command: .moveCategoryGroup(groupId: F.freizeit, index: 1))
        )
        let last = dragged(F.alltag, from: 7, to: 204).model
        #expect(
            last.drag?.target
                == BudgetDropTarget(
                    lineBelow: F.kino, command: .moveCategoryGroup(groupId: F.alltag, index: 3)))
        #expect(dragged(F.freizeit, from: 167, to: 204).model.drag?.target == nil)
        #expect(dragged(F.freizeit, from: 167, to: 232).model.drag?.target == nil)
    }

    @Test func onlyTheCategoryRowsAcceptADrop() {
        let model = F().model().model
        model.dragPressed(rowId: F.kino, at: CGPoint(x: 40, y: 204))
        for point in [CGPoint(x: 400, y: 119), CGPoint(x: 190, y: 119), CGPoint(x: -1, y: 119), CGPoint(x: 60, y: -5)] {
            model.dragMoved(to: point)
            #expect(model.drag?.target == nil)
        }
        model.dragMoved(to: CGPoint(x: 189, y: 119))
        #expect(model.drag?.target?.command == .moveCategory(categoryId: F.kino, toGroupId: F.sparen, index: 0))
        model.dragMoved(to: CGPoint(x: 400, y: 119))
        model.dragReleased()
        #expect(model.store.budget.category(withId: F.kino)?.categoryGroupId == F.freizeit)
    }

    @Test func releasingMovesThroughTheStore() {
        let (model, store) = dragged(F.kino, from: 204, to: 119)
        model.dragReleased()
        #expect(model.drag == nil)
        #expect(store.commands == [.moveCategory(categoryId: F.kino, toGroupId: F.sparen, index: 0)])
        let click = F().model()
        click.model.dragPressed(rowId: F.kino, at: CGPoint(x: 40, y: 204))
        click.model.dragMoved(to: CGPoint(x: 45, y: 209))
        click.model.dragReleased()
        #expect(click.store.commands.isEmpty)
    }

    @Test func aCancelledDragMovesNothingAndLeavesNoDragBehind() {
        let (model, store) = dragged(F.kino, from: 204, to: 119)
        model.dragCancelled()
        #expect(model.drag == nil)
        model.dragReleased()
        #expect(store.commands.isEmpty)
    }

    @Test func droppingIntoAMasterThatHasTheNameShowsTheDuplicatePrompt() throws {
        var fixture = F()
        try fixture.budget.apply(.renameCategory(categoryId: F.kleidung, name: "kino"))
        for target: CGFloat in [54, 102] {
            let (model, store) = dragged(F.kino, from: 204, to: target, fixture: fixture)
            model.dragReleased()
            #expect(store.budget.category(withId: F.kino)?.categoryGroupId == F.freizeit)
            let dialog = model.dialogs.presented.last?.dialog
            #expect(
                dialog?.content
                    == "Es gibt schon eine Kategorie „Alltag: Kino“.\nBitte eine der beiden umbenennen und es erneut versuchen."
            )
            #expect(dialog?.buttons.map(\.title) == ["OK"])
        }
    }

    @Test func autoScrollingSpeedsUpTowardsTheWindowEdges() {
        #expect(BudgetViewModel.autoScrollDepth(windowY: 150, windowHeight: 783) == -50)
        #expect(BudgetViewModel.autoScrollDepth(windowY: 400, windowHeight: 783) == 0)
        #expect(BudgetViewModel.autoScrollDepth(windowY: 733, windowHeight: 783) == 50)
        let model = F().model(panel: CGSize(width: 1076, height: 300)).model
        model.scroll(to: 50)
        model.dragPressed(rowId: F.kino, at: CGPoint(x: 40, y: 90))
        model.dragMoved(to: CGPoint(x: 40, y: 40), edgeDepth: 14)
        #expect(model.drag?.autoScrolls == true)
        model.autoScrollTick()
        #expect(model.scrollOffset == 54)
        model.dragMoved(to: CGPoint(x: 40, y: 40), edgeDepth: -3)
        model.autoScrollTick()
        #expect(model.scrollOffset == 53)
        model.dragMoved(to: CGPoint(x: 40, y: 40), edgeDepth: 0)
        model.autoScrollTick()
        #expect(model.scrollOffset == 53)
    }
}
