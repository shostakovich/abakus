import AbakusUI
import CoreGraphics

extension BudgetViewModel {
    public func mouseDown(at point: CGPoint) {
        guard !isCoveredByModal else { return }
        if let edit = editor, rowFrame(of: edit.cell)?.contains(point) != true {
            mouseDownOutsideEditedRow()
        }
    }
}
