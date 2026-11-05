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
}
