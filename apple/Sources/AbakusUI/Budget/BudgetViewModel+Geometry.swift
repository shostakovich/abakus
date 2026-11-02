import CoreGraphics
import Foundation

extension BudgetViewModel {
    package var categoryRowsOrigin: CGPoint { layout.rowsOrigin }

    package func rowsPoint(_ point: CGPoint) -> CGPoint {
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
}
