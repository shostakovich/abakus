import AbakusCore
import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import AbakusUI

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
        for text in ["12,5", "12.5", "125,00", "1,2,3", "-", ""] {
            model.beginEdit(model.cell(F.kleidung))
            model.cellTextChanged(text)
            model.commitEdit()
            #expect(model.editor == nil)
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
        model.panelSize = CGSize(width: 1652, height: 600)
        model.beginEdit(BudgetCellID(month: day("2027-02-01"), categoryId: F.kino))
        model.beginColumnResize(atX: 0)
        model.columnResizeMoved(toX: 190)
        #expect(model.shownMonths.count == 4)
        #expect(model.editor == nil)
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
        let model = F().model(panel: CGSize(width: 1076, height: 320)).model
        model.beginEdit(model.cell(F.lebensmittel))
        #expect(model.cellKey(.pageDown))
        #expect(model.scrollOffset == 100)
        #expect(model.editor != nil)
    }

    @Test func aCellBelowTheViewportScrollsIntoView() {
        let model = F().model(panel: CGSize(width: 1076, height: 320)).model
        #expect(model.layout.viewportHeight == 69)
        model.beginEdit(model.cell(F.kino))
        #expect(model.scrollOffset == 155)
        model.beginEdit(model.cell(F.lebensmittel))
        #expect(model.scrollOffset == 32)
    }

    @Test func operatorsOpenTheCalculatorAfterStoringTheTypedText() {
        let (model, store) = F().model()
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("10")
        #expect(model.cellKey(.character("+")))
        #expect(model.editor == nil)
        #expect(model.calculator?.calculator.display == "10,00")
        #expect(store.commands == [set(10, F.kino)])
        #expect(model.panelFocusRequest == 1)
        model.calculatorKey(.character("5"))
        model.calculatorKey(.enter)
        #expect(model.calculator == nil)
        #expect(store.commands.last == set(15, F.kino))
        #expect(model.editor?.text == "15,00")
    }

    @Test func minusOnlyCalculatesWithANonZeroValue() {
        let model = F().model().model
        model.beginEdit(model.cell(F.kino))
        #expect(!model.cellKey(.character("-")))
        model.cellTextChanged("-5")
        #expect(model.cellKey(.character("-")))
        #expect(model.calculator != nil)
    }

    @Test func anErrorResultStaysOnTheCalculator() {
        let (model, store) = F().model()
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("4")
        model.cellKey(.character("/"))
        model.calculatorKey(.character("0"))
        model.calculatorOK()
        #expect(model.calculator?.calculator.isError == true)
        #expect(store.commands == [set(4, F.kino)])
        model.calculatorKey(.escape)
        #expect(model.calculator == nil)
        #expect(model.editor == nil)
    }

    @Test func f2OpensTheQuickBudgetListAndEnterAppliesTheHighlightedRow() {
        var fixture = F()
        fixture.budget(80, F.lebensmittel, in: "2026-09-01")
        fixture.spend(60, F.lebensmittel, on: "2026-09-10")
        let (model, store) = fixture.model()
        model.beginEdit(model.cell(F.lebensmittel))
        model.cellTextChanged("1")
        #expect(model.cellKey(.f2))
        let list = try! #require(model.quickBudget)
        #expect(
            list.options.map(\.label) == [
                "Zugewiesen im Vormonat:", "Ausgegeben im Vormonat:", "Geplante Ausgaben diesen Monat:",
                "Verfügbar auf null bringen:",
            ])
        #expect(list.rowCount == 5)
        #expect(list.height == 131)
        model.cellKey(.down)
        #expect(model.quickBudget?.highlighted == 1)
        model.cellKey(.character("x"))
        #expect(model.editor?.text == "1")
        model.cellKey(.enter)
        #expect(model.quickBudget == nil)
        #expect(model.editor?.text == "60,00")
        #expect(store.commands == [set(60, F.lebensmittel)])
        model.commitEdit()
        #expect(store.commands.count == 1)
    }

    @Test func aQuickBudgetPickOfZeroShowsZeroInTheOpenField() {
        var fixture = F()
        fixture.budget(25, F.kino, in: "2026-10-01")
        let (model, store) = fixture.model()
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("7")
        model.openQuickBudget()
        let index = try! #require(model.quickBudget?.options.firstIndex { $0.fill == .assignedLastMonth })
        model.quickBudgetChosen(index)
        #expect(model.editor?.text == "0,00")
        #expect(store.commands == [set(0, F.kino)])
        model.commitEdit()
        #expect(store.commands.count == 1)
    }

    @Test func aQuickBudgetPickOfTheStoredAmountStoresNothing() {
        var fixture = F()
        fixture.budget(25, F.kino, in: "2026-09-01")
        fixture.budget(25, F.kino, in: "2026-10-01")
        let (model, store) = fixture.model()
        model.beginEdit(model.cell(F.kino))
        model.cellTextChanged("7")
        model.openQuickBudget()
        model.quickBudgetChosen(0)
        #expect(model.editor?.text == "25,00")
        model.commitEdit()
        #expect(store.commands.isEmpty)
    }

    @Test func theQuickBudgetMenuFitsItsLongestRow() throws {
        var fixture = F()
        for month in 3...9 { fixture.budget(10, F.kino, in: "2026-0\(month)-01") }
        let model = fixture.model().model
        model.beginEdit(model.cell(F.kino))
        model.openQuickBudget()
        let list = try #require(model.quickBudget)
        let label = try #require(list.options.first { $0.label.contains("nur 7 Monate") })
        let row =
            ThemeFont.body.width(of: label.label.trimmingCharacters(in: .whitespaces)) + 12
            + ThemeFont.body.width(of: model.formatter.currencyNoSymbol(label.amount))
        #expect(list.width >= row + 2 * (10 + 5))
        let calculator = 16 + 6 + ThemeFont.body.width(of: BudgetQuickBudgetList.calculatorLabel) + 12
        #expect(list.width >= calculator + 2 * (10 + 5))
    }

    @Test func theLastMonthsFieldKeepsItsColumnsNarrowerCells() throws {
        let model = F().model().model
        let cell = model.cell(F.kino, "2026-12-01")
        let box = try #require(model.assignedBoxFrame(of: cell))
        let row = try #require(model.rowFrame(of: cell))
        #expect(box == model.layout.cells(at: 2).field.offsetBy(dx: row.minX, dy: row.minY))
    }

    @Test func aRefusedQuickBudgetPickShowsTheStoredAmount() {
        var fixture = F()
        fixture.budget(25, F.kino, in: "2026-10-01")
        let (model, store) = fixture.model()
        model.beginEdit(model.cell(F.kino))
        model.openQuickBudget()
        store.fail(with: BudgetError.amountNotFinite, once: true)
        model.quickBudgetChosen(0)
        #expect(model.quickBudget == nil)
        #expect(model.editor?.text == "25,00")
        #expect(store.budget.assigned(in: day("2026-10-01"), categoryId: F.kino) == 25)
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

    @Test func theQuickBudgetListClosesOrHandsOverToTheCalculator() {
        let model = F().model().model
        model.beginEdit(model.cell(F.kino))
        model.dropDownButtonClicked()
        #expect(model.quickBudget != nil)
        model.cellKey(.escape)
        #expect(model.quickBudget == nil)
        #expect(model.editor != nil)
        model.dropDownButtonClicked()
        model.cellKey(.character("*"))
        #expect(model.quickBudget == nil)
        #expect(model.calculator != nil)
        model.calculatorCancel()
        model.beginEdit(model.cell(F.kino))
        model.openQuickBudget()
        model.quickBudgetChosen(4)
        #expect(model.calculator != nil)
    }

    @Test func theCellFieldSwallowsWordCompletion() {
        #expect(BudgetCellField.command(for: #selector(NSTextView.complete(_:))) == .swallow)
        #expect(BudgetCellField.command(for: #selector(NSResponder.insertTab(_:))) == .key(.tab))
        #expect(BudgetCellField.command(for: #selector(NSResponder.deleteBackward(_:))) == .key(.backspace))
        #expect(BudgetCellField.command(for: #selector(NSResponder.moveLeft(_:))) == nil)
    }

    @Test func typingKeepsToTheRestrictedCharacters() {
        #expect("0123456789,.-+ /[]".allSatisfy(BudgetViewModel.allowsTyping))
        #expect(!"aZ€:".contains(where: BudgetViewModel.allowsTyping))
    }

    @Test func popupsSitAtTheAssignedBox() throws {
        let model = F().model().model
        let cell = model.cell(F.kino)
        model.beginEdit(cell)
        let row = try #require(model.rowFrame(of: cell))
        #expect(row.origin == CGPoint(x: 16 + 202, y: 234 + 6 * 32))
        #expect(row.height == 32 && abs(row.width - 272.667) < 0.001)
        #expect(model.assignedBoxFrame(of: cell) == CGRect(x: 218 + 8, y: 426 + 4, width: 77, height: 24))
        #expect(model.dropDownButtonFrame(of: cell) == CGRect(x: 226, y: 430, width: 20, height: 24))
        model.openQuickBudget()
        let list = try #require(model.quickBudgetFrame())
        let box = try #require(model.assignedBoxFrame(of: cell))
        #expect(abs(list.maxX - box.maxX) < 0.001)
        #expect(list.minY == box.maxY)
        model.panelSize = CGSize(width: 1076, height: 420)
        #expect(model.quickBudgetFrame()?.maxY == box.minY)
        model.cellKey(.character("+"))
        let calculator = try #require(model.calculatorFrame())
        #expect(abs(calculator.maxX - box.maxX) < 0.001)
        #expect(calculator.maxY == box.minY)
    }

    @Test func theCalculatorOpensAboveWhenItsWholeHeightDoesNotFitBelowTheBox() throws {
        let model = F().model().model
        let cell = model.cell(F.kino)
        model.beginEdit(cell)
        let box = try #require(model.assignedBoxFrame(of: cell))
        let height = PopoverMetrics.size(content: CalculatorPopover.size).height
        model.panelSize = CGSize(width: 1076, height: box.maxY + height - 1)
        model.cellKey(.character("+"))
        let calculator = try #require(model.calculatorFrame())
        #expect(calculator.maxY == box.minY)
        model.panelSize = CGSize(width: 1076, height: box.maxY + height)
        #expect(model.calculatorFrame()?.minY == box.maxY)
    }

    @Test func aMouseDownOutsideTheRowCommits() throws {
        let (model, store) = F().model()
        let cell = model.cell(F.kino)
        model.beginEdit(cell)
        model.cellTextChanged("8")
        let row = try #require(model.rowFrame(of: cell))
        model.mouseDown(at: CGPoint(x: row.midX, y: row.midY))
        #expect(model.editor != nil)
        model.openQuickBudget()
        let list = try #require(model.quickBudgetFrame())
        model.mouseDown(at: CGPoint(x: list.midX, y: list.midY))
        #expect(model.quickBudget != nil)
        model.mouseDown(at: CGPoint(x: row.maxX - 2, y: row.midY))
        #expect(model.quickBudget == nil)
        #expect(model.editor != nil)
        model.mouseDown(at: CGPoint(x: 5, y: 5))
        #expect(model.editor == nil)
        #expect(store.commands == [set(8, F.kino)])
    }
}
