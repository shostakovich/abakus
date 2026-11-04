import AbakusUI
import CoreGraphics

extension BudgetViewModel {
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
