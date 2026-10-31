import CoreGraphics
import Foundation

extension BudgetViewModel {
    var categoryRowsOrigin: CGPoint { layout.rowsOrigin }

    func rowsPoint(_ point: CGPoint) -> CGPoint {
        let origin = categoryRowsOrigin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    public func rowFrame(of cell: BudgetCellID) -> CGRect? {
        guard let index = shownMonths.firstIndex(of: cell.month), let top = groups.top(of: cell.categoryId) else {
            return nil
        }
        let layout = layout
        let origin = layout.rowsOrigin
        return CGRect(
            x: origin.x + layout.columnX(index), y: origin.y + top - scrollOffset, width: layout.columnWidth,
            height: BudgetMetrics.rowHeight)
    }

    public func assignedBoxFrame(of cell: BudgetCellID) -> CGRect? {
        guard let row = rowFrame(of: cell), let index = shownMonths.firstIndex(of: cell.month) else { return nil }
        return layout.cells(at: index).field.offsetBy(dx: row.minX, dy: row.minY)
    }

    public func dropDownButtonFrame(of cell: BudgetCellID) -> CGRect? {
        guard let box = assignedBoxFrame(of: cell) else { return nil }
        return CGRect(x: box.minX, y: box.minY, width: BudgetMetrics.fieldButtonWidth, height: box.height)
    }

    public func quickBudgetFrame() -> CGRect? {
        guard let list = quickBudget, let box = assignedBoxFrame(of: list.cell) else { return nil }
        let below = panelSize.height > box.minY + list.height + 18
        return CGRect(
            x: box.maxX - list.width, y: below ? box.maxY : box.minY - list.height, width: list.width,
            height: list.height)
    }

    public func calculatorFrame() -> CGRect? {
        calculatorPlacement()?.frame
    }

    func calculatorPlacement() -> PopoverPlacement? {
        guard let state = calculator, let box = assignedBoxFrame(of: state.cell) else { return nil }
        let size = PopoverMetrics.size(content: CalculatorPopover.size)
        let below = panelSize.height - box.maxY >= size.height
        return PopoverPlacement(
            frame: CGRect(
                origin: CGPoint(x: box.maxX - size.width, y: below ? box.maxY : box.minY - size.height), size: size),
            arrowEdge: below ? .top : .bottom, arrowOffset: size.width - box.width / 2)
    }

    public func mouseDown(at point: CGPoint) {
        guard !isCoveredByModal else { return }
        if calculator != nil, calculatorFrame()?.contains(point) != true {
            mouseDownOutsideCalculator()
        }
        let list = quickBudgetFrame()
        let button = editor.flatMap { dropDownButtonFrame(of: $0.cell) }
        if quickBudget != nil, list?.contains(point) != true, button?.contains(point) != true {
            mouseDownOutsideQuickBudget()
        }
        if let edit = editor, rowFrame(of: edit.cell)?.contains(point) != true, list?.contains(point) != true {
            mouseDownOutsideEditedRow()
        }
    }
}
