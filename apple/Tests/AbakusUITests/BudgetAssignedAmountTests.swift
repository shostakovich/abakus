import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct BudgetAssignedAmountTests {
    typealias F = BudgetScreenFixture

    private func assigned(_ model: BudgetViewModel) -> Decimal? {
        model.month(day("2026-10-01"))?.category(F.kleidung)?.assigned
    }

    @Test func zugewiesenWorksOutPlusAndMinus() {
        let (model, _) = F().model()
        model.assign("50+20", to: model.cell(F.kleidung))
        #expect(assigned(model) == 70)
        model.assign("70 − 5,50", to: model.cell(F.kleidung))
        #expect(assigned(model) == decimal("64.5"))
        model.assign("", to: model.cell(F.kleidung))
        #expect(assigned(model) == 0)
        #expect(!model.dialogs.isPresenting)
    }

    static let refusal = "„60*2“ ist kein gültiger Betrag.\nRechnen geht mit +\u{00A0}und\u{00A0}−, etwa\u{00A0}50+20."

    @Test func theEditedCellKeepsWhatWasTypedAndSaysWhyInsteadOfADialog() throws {
        let (model, store) = F().model()
        model.assign("50", to: model.cell(F.kleidung))
        model.beginEdit(model.cell(F.kleidung))
        model.cellTextChanged("60*2")
        model.commitEdit()
        #expect(assigned(model) == 50)
        #expect(store.assignedCommands.count == 1)
        #expect(!model.dialogs.isPresenting)
        let edit = try #require(model.editor)
        #expect(edit.cell == model.cell(F.kleidung))
        #expect(edit.text == "60*2")
        #expect(edit.error == Self.refusal)
        model.cellKey(.tab)
        #expect(model.editor?.cell == model.cell(F.kleidung))
        model.beginEdit(model.cell(F.notgroschen))
        #expect(model.editor?.cell == model.cell(F.kleidung))
        model.present(.editCategory(categoryId: F.kino))
        #expect(model.presentedPopup == nil)
        model.cellTextChanged("60+2")
        #expect(model.editor?.error == nil)
        model.cellKey(.tab)
        #expect(assigned(model) == 62)
        #expect(model.editor?.cell == model.cell(F.notgroschen))
    }

    @Test func everyRefusalCountsAlsoOfTheSameText() {
        let (model, _) = F().model()
        model.beginEdit(model.cell(F.kleidung))
        model.cellTextChanged("60*2")
        model.commitEdit()
        model.commitEdit()
        #expect(model.editor?.refusals == 2)
        #expect(model.editor?.error == Self.refusal)
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.sheetAssignedChanged("60*2", in: model.cell(F.kleidung))
        model.commitSheetAssigned()
        model.commitSheetAssigned()
        #expect(model.sheetAssignedRefusals == 2)
    }

    @Test func turningToThePhoneLayoutDropsARefusedCellAmount() {
        let (model, store) = F().model()
        model.touchLayout = .wide(months: 2, categoryWidth: 224)
        model.beginEdit(model.cell(F.kleidung))
        model.cellTextChanged("60*2")
        #expect(!model.commitEdit())
        model.touchLayout = .phone
        #expect(model.editor == nil)
        model.categoryTapped(F.kino)
        #expect(model.presentedPopup == .category(month: day("2026-10-01"), categoryId: F.kino))
        #expect(store.assignedCommands.isEmpty)
    }

    @Test func escapePutsBackTheStoredAmount() {
        let (model, store) = F().model()
        model.beginEdit(model.cell(F.kleidung))
        model.cellTextChanged("10*2")
        model.commitEdit()
        model.cellKey(.escape)
        #expect(model.editor == nil)
        #expect(store.assignedCommands.isEmpty)
    }

    @Test func leavingTheBudgetDropsARefusedAmount() {
        let (model, store) = F().model()
        model.beginEdit(model.cell(F.kleidung))
        model.cellTextChanged("10*2")
        model.leave()
        #expect(model.editor == nil)
        #expect(store.assignedCommands.isEmpty)
        #expect(!model.dialogs.isPresenting)
    }

    @Test func anAmountTooLargeToStoreIsRefused() {
        let (model, store) = F().model()
        model.beginEdit(model.cell(F.kleidung))
        model.cellTextChanged(String(repeating: "9", count: 16))
        model.commitEdit()
        #expect(model.editor?.error != nil)
        model.cellTextChanged(String(repeating: "9", count: 15) + "+1")
        model.commitEdit()
        #expect(model.editor?.error != nil)
        #expect(store.assignedCommands.isEmpty)
        #expect(!model.dialogs.isPresenting)
    }

    @Test func theSheetsZugewiesenSaysWhyBelowTheField() {
        let (model, store) = F().model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.sheetAssignedChanged("60*2", in: model.cell(F.kleidung))
        model.commitSheetAssigned()
        #expect(model.sheetAssignedError == Self.refusal)
        #expect(store.assignedCommands.isEmpty)
        #expect(!model.dialogs.isPresenting)
        model.sheetAssignedChanged("60+2", in: model.cell(F.kleidung))
        #expect(model.sheetAssignedError == nil)
        model.commitSheetAssigned()
        #expect(assigned(model) == 62)
    }

    @Test func theSheetsFieldHandingBackItsTextOnLeavingKeepsTheRefusal() {
        let (model, _) = F().model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.sheetAssignedChanged("60*2", in: model.cell(F.kleidung))
        model.commitSheetAssigned()
        model.sheetAssignedChanged("60*2", in: model.cell(F.kleidung))
        #expect(model.sheetAssignedError == Self.refusal)
    }

    @Test func theCellHandingBackItsTextOnLeavingKeepsTheRefusal() {
        let (model, _) = F().model()
        model.beginEdit(model.cell(F.kleidung))
        model.cellTextChanged("60*2")
        model.beginEdit(model.cell(F.notgroschen))
        model.cellTextChanged("60*2")
        #expect(model.editor?.cell == model.cell(F.kleidung))
        #expect(model.editor?.error == Self.refusal)
    }

    @Test func closingTheSheetDropsARefusedAmount() {
        let (model, store) = F().model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.sheetAssignedChanged("60*2", in: model.cell(F.kleidung))
        model.touchSheetDismissed()
        #expect(model.presentedPopup == nil)
        #expect(model.sheetAssignedError == nil)
        #expect(store.assignedCommands.isEmpty)
    }

    @Test func theSheetsZugewiesenWorksOutPlusAndMinus() {
        let (model, _) = F().model()
        model.touchLayout = .phone
        model.categoryTapped(F.kleidung)
        model.sheetAssignedChanged("50+20", in: model.cell(F.kleidung))
        model.commitSheetAssigned()
        #expect(assigned(model) == 70)
        #expect(model.callouts.availableForm?.available == 70)
    }
}
