import AbakusCore
import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import AbakusMacUI
@testable import AbakusUI
@testable import AbakusUITests

@MainActor
@Suite struct BudgetEditingTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    private func set(_ amount: Decimal, _ category: String) -> BudgetCommand {
        .setAssigned(month: october, categoryId: category, amount: amount)
    }

    @Test func editingStartsWithTheLabelsTextAllSelected() {
        var fixture = F()
        fixture.budget(1234.5, F.lebensmittel, in: "2026-10-01")
        let model = fixture.model().model
        model.beginEdit(model.cell(F.lebensmittel))
        #expect(model.editor?.text == "1.234,50")
        #expect(model.editor?.selectAllRequest == 1)
        model.beginEdit(model.cell(F.kleidung))
        #expect(model.editor?.text == "")
        model.beginEdit(model.cell(F.alltag))
        #expect(model.editor == nil)
        model.beginEdit(model.cell(F.kino, "2027-03-01"))
        #expect(model.editor == nil)
    }

    @Test func committingStoresWhatParses() {
        var fixture = F()
        fixture.budget(50, F.kleidung, in: "2026-10-01")
        let (model, store) = fixture.model()
        for (text, parses) in [
            ("12,5", true), ("12.5", true), ("125,00", true), ("1,2,3", false), ("-", false), ("", true),
        ] {
            model.beginEdit(model.cell(F.kleidung))
            model.cellTextChanged(text)
            #expect(model.commitEdit() == parses)
            #expect((model.editor?.error == nil) == parses)
            model.cancelEdit()
        }
        #expect(store.commands == [set(12.5, F.kleidung), set(125, F.kleidung), set(0, F.kleidung)])
    }

    @Test func anEditWhoseMonthNoLongerShowsIsCommitted() {
        let (model, store) = F().model(panel: CGSize(width: 1652, height: 600))
        let december = BudgetCellID(month: day("2026-12-01"), categoryId: F.kino)
        model.beginEdit(december)
        model.cellTextChanged("8")
        model.panelSize = CGSize(width: 1400, height: 600)
        #expect(model.editor?.cell == december)
        model.panelSize = CGSize(width: 776, height: 600)
        #expect(model.editor == nil)
        #expect(store.commands == [.setAssigned(month: day("2026-12-01"), categoryId: F.kino, amount: 8)])
    }

    @Test func escapeLeavesWithoutStoring() {
        let (model, store) = F().model()
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("99")
        #expect(model.cellKey(.escape))
        #expect(model.editor == nil)
        #expect(store.commands.isEmpty)
    }

    @Test func tabEnterAndDownMoveDownTheMonthColumnAndWrap() throws {
        var fixture = F()
        try fixture.budget.apply(.setCategoryGroupExpanded(groupId: F.sparen, false))
        let (model, store) = fixture.model()
        let november = BudgetCellID(month: day("2026-11-01"), categoryId: F.kleidung)
        model.beginEdit(november)
        model.cellTextChanged("7")
        model.cellKey(.tab)
        #expect(model.editor?.cell == BudgetCellID(month: day("2026-11-01"), categoryId: F.kino))
        model.cellKey(.enter)
        #expect(model.editor?.cell.categoryId == F.lebensmittel)
        model.cellKey(.down)
        #expect(model.editor?.cell.categoryId == F.kleidung)
        model.cellKey(.backTab)
        #expect(model.editor?.cell.categoryId == F.lebensmittel)
        model.cellKey(.up)
        #expect(model.editor?.cell.categoryId == F.kino)
        #expect(model.editor?.cell.month == day("2026-11-01"))
        #expect(store.commands == [.setAssigned(month: day("2026-11-01"), categoryId: F.kleidung, amount: 7)])
    }

    @Test func tabOnTheOnlyEditableCellCommitsAndStays() throws {
        var fixture = F()
        try fixture.budget.apply(.setCategoryGroupExpanded(groupId: F.alltag, false))
        try fixture.budget.apply(.setCategoryGroupExpanded(groupId: F.sparen, false))
        let (model, store) = fixture.model()
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("3")
        model.cellKey(.tab)
        #expect(model.editor?.cell == model.cell(F.kino))
        #expect(model.editor?.text == "3,00")
        #expect(store.commands == [set(3, F.kino)])
    }

    @Test func pageKeysScrollWhileTheCellStaysInEditMode() {
        let model = F().model(panel: CGSize(width: 1076, height: 198)).model
        model.beginEdit(model.cell(F.lebensmittel))
        #expect(model.cellKey(.pageDown))
        #expect(model.scrollOffset == 100)
        #expect(model.editor != nil)
    }

    @Test func aCellBelowTheViewportScrollsIntoView() {
        let model = F().model(panel: CGSize(width: 1076, height: 184)).model
        #expect(model.layout.viewportHeight == 55)
        model.beginEdit(model.cell(F.kino))
        #expect(model.scrollOffset == 169)
        model.beginEdit(model.cell(F.lebensmittel))
        #expect(model.scrollOffset == 32)
    }

    @Test func theLastMonthsFieldKeepsItsColumnsNarrowerCells() throws {
        let model = F().model().model
        let cell = model.cell(F.kino, "2026-12-01")
        let box = try #require(model.assignedBoxFrame(of: cell))
        let row = try #require(model.rowFrame(of: cell))
        #expect(box == model.layout.cells(at: 2).field.offsetBy(dx: row.minX, dy: row.minY))
    }

    @Test func aRefusedCellAmountKeepsTheStoredOne() {
        var fixture = F()
        fixture.budget(25, F.kino, in: "2026-10-01")
        let (model, store) = fixture.model()
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("99")
        store.fail(with: BudgetError.amountNotFinite, once: true)
        model.commitEdit()
        #expect(model.editor == nil)
        #expect(model.assignedText(model.cell(F.kino)) == "25,00")
        model.beginEdit(model.cell(F.kino))
        #expect(model.editor?.text == "25,00")
    }

    @Test func theCellFieldSwallowsWordCompletion() {
        #expect(BudgetCellField.command(for: #selector(NSTextView.complete(_:))) == .swallow)
        #expect(BudgetCellField.command(for: #selector(NSResponder.insertTab(_:))) == .key(.tab))
        #expect(BudgetCellField.command(for: #selector(NSResponder.moveLeft(_:))) == nil)
    }

    @Test func typingKeepsToTheRestrictedCharacters() {
        #expect("0123456789,.-+ /[]".allSatisfy(BudgetViewModel.allowsTyping))
        #expect(!"aZ€:".contains(where: BudgetViewModel.allowsTyping))
    }

    @Test func aPastedTrueMinusKeepsTheSign() {
        #expect(BudgetViewModel.allowedText("\u{2212}50,00\u{00A0}€") == "-50,00")
    }

    @Test func theEditedFieldSitsInTheAssignedBox() throws {
        let model = F().model().model
        let cell = model.cell(F.kino)
        model.beginEdit(cell)
        let row = try #require(model.rowFrame(of: cell))
        #expect(row.origin == CGPoint(x: 16 + 202, y: 112 + 6 * 32))
        #expect(row.height == 32 && abs(row.width - 272.667) < 0.001)
        #expect(model.assignedBoxFrame(of: cell) == CGRect(x: 218 + 8, y: 304 + 4, width: 72, height: 24))
    }

    @Test func aMouseDownOutsideTheRowCommits() throws {
        let (model, store) = F().model()
        let cell = model.cell(F.kino)
        model.beginEdit(cell)
        model.cellTextChanged("8")
        let row = try #require(model.rowFrame(of: cell))
        model.mouseDown(at: CGPoint(x: row.midX, y: row.midY))
        #expect(model.editor != nil)
        model.mouseDown(at: CGPoint(x: 5, y: 5))
        #expect(model.editor == nil)
        #expect(store.commands == [set(8, F.kino)])
    }
}
