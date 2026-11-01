import AbakusCore
import SwiftUI

struct BudgetMonthRowsView: View {
    let model: BudgetViewModel
    let month: BudgetMonth
    let cells: BudgetCellColumns

    var body: some View {
        BudgetGroupsStack(groups: model.groups, offset: model.scrollOffset) { group in
            BudgetMonthMasterRow(model: model, month: month, row: group.header, cells: cells)
        } sub: { row in
            BudgetMonthSubRow(model: model, month: month, row: row, cells: cells)
        }
    }
}

private struct BudgetCell<Content: View>: View {
    let width: CGFloat
    var trailing = BudgetMetrics.cellPadding
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.trailing, trailing)
            .frame(width: width, height: BudgetMetrics.rowHeight, alignment: .trailing)
    }
}

private struct BudgetOutflowsFigure: View {
    let model: BudgetViewModel
    let text: String
    let font: ThemeFont
    let hasTransactions: Bool
    let anchor: BudgetPopupAnchor
    var toolTip: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        BudgetFigure(text: text, font: font, style: AnyShapeStyle(ThemeColor.secondaryText))
            .underline(isHovered && hasTransactions)
            .budgetPopupAnchor(anchor, of: model)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
            .pointerStyle(hasTransactions ? .link : .default)
            .toolTip(toolTip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Aktivität")
            .accessibilityValue(text)
            .accessibilityAddTraits(hasTransactions ? .isButton : [])
    }
}

extension BudgetMonth {
    /// A past month is muted; red stays red.
    func figureStyle(isNegative: Bool = false) -> AnyShapeStyle {
        if isNegative { return AnyShapeStyle(ThemeColor.negative) }
        return AnyShapeStyle(isClosed ? ThemeColor.secondaryText : ThemeColor.text)
    }
}

struct BudgetMonthMasterRow: View {
    let model: BudgetViewModel
    let month: BudgetMonth
    let row: BudgetCategoryRow
    let cells: BudgetCellColumns

    var body: some View {
        let display = model.masterRowDisplay(row, in: month)
        let font = BudgetStyle.masterFont
        HStack(spacing: 0) {
            BudgetCell(width: cells.assigned) {
                BudgetFigure(text: display.assigned, font: font, style: month.figureStyle())
            }
            BudgetCell(width: cells.outflows) {
                BudgetOutflowsFigure(
                    model: model, text: display.outflows, font: font, hasTransactions: display.hasTransactions,
                    anchor: .outflows(month.month, row.id)
                ) { model.masterOutflowsClicked(month: month.month, masterId: row.id) }
            }
            BudgetCell(width: cells.balance, trailing: BudgetStyle.availableDigitInset) {
                BudgetFigure(
                    text: display.balance, font: font, style: month.figureStyle(isNegative: display.isBalanceNegative))
            }
        }
        .frame(height: BudgetMetrics.rowHeight)
    }
}

struct BudgetMonthSubRow: View {
    let model: BudgetViewModel
    let month: BudgetMonth
    let row: BudgetCategoryRow
    let cells: BudgetCellColumns

    var body: some View {
        let display = model.subRowDisplay(row.id, in: month)
        HStack(spacing: 0) {
            assigned(display)
            BudgetCell(width: cells.outflows) {
                BudgetOutflowsFigure(
                    model: model, text: display.outflows, font: BudgetStyle.outflowsFont,
                    hasTransactions: display.hasTransactions, anchor: .outflows(month.month, row.id),
                    toolTip: display.outflows.isEmpty ? nil : "Buchungen zeigen"
                ) { model.subOutflowsClicked(month: month.month, categoryId: row.id) }
            }
            balance(display)
        }
        .frame(height: BudgetMetrics.rowHeight)
    }

    private var cell: BudgetCellID { BudgetCellID(month: month.month, categoryId: row.id) }

    @ViewBuilder
    private func assigned(_ display: BudgetSubRowDisplay) -> some View {
        let field = cells.field
        let edit = model.editor?.cell == cell ? model.editor : nil
        ZStack(alignment: .topLeading) {
            if let edit {
                BudgetEditedField(model: model, edit: edit)
                    .frame(width: field.width, height: field.height)
                    .offset(x: field.minX, y: field.minY)
            } else {
                BudgetCell(width: cells.assigned) {
                    BudgetFigure(text: display.assigned, style: month.figureStyle())
                }
                .background(alignment: .topLeading) {
                    if model.hoveredAssignedCell == cell {
                        RoundedRectangle(cornerRadius: BudgetStyle.fieldCornerRadius)
                            .strokeBorder(ThemeColor.text.opacity(0.5), lineWidth: 1)
                            .frame(width: field.width, height: field.height)
                            .offset(x: field.minX, y: field.minY)
                    }
                }
                .contentShape(Rectangle())
                .onHover { model.assignedCellHovered(cell, $0) }
                .onTapGesture { model.beginEdit(cell) }
                .pointerStyle(.horizontalText)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Zugewiesen")
                .accessibilityValue(display.assigned.isEmpty ? model.zeroText : display.assigned)
            }
        }
        .frame(width: cells.assigned, height: BudgetMetrics.rowHeight, alignment: .topLeading)
    }

    private func balance(_ display: BudgetSubRowDisplay) -> some View {
        BudgetCell(width: cells.balance, trailing: BudgetStyle.markerInset) {
            HStack(spacing: 0) {
                BudgetFigure(
                    text: display.balance,
                    font: display.isBalanceZero ? BudgetStyle.assignedFont : BudgetStyle.balanceFont,
                    style: balanceStyle(display))
                Color.clear
                    .frame(width: BudgetStyle.markerSlot, height: BudgetStyle.ringSize)
                    .overlay(alignment: .trailing) { marker(display) }
            }
            .budgetPopupAnchor(.balance(month.month, row.id), of: model)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.balanceClicked(month: month.month, categoryId: row.id) }
        .pointerStyle(.link)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Verfügbar")
        .accessibilityValue(display.accessibilityValue)
    }

    @ViewBuilder
    private func marker(_ display: BudgetSubRowDisplay) -> some View {
        if let marker = display.marker {
            let color = month.isClosed ? ThemeColor.secondaryText : marker.symbol.color
            if let percent = display.fundedPercent {
                BudgetTargetRing(percent: percent, color: color)
            } else {
                Image(systemName: marker.symbol.name)
                    .font(.system(size: BudgetStyle.markerSize))
                    .foregroundStyle(color)
            }
        }
    }

    private func balanceStyle(_ display: BudgetSubRowDisplay) -> AnyShapeStyle {
        if display.isBalanceZero { return AnyShapeStyle(ThemeColor.tertiaryText) }
        if display.isBalanceNegative || month.isClosed {
            return month.figureStyle(isNegative: display.isBalanceNegative)
        }
        return display.marker == .underfunded ? AnyShapeStyle(ThemeColor.warning) : AnyShapeStyle(ThemeColor.text)
    }
}

private struct BudgetEditedField: View {
    /// Puts the digits on the column's digit edge.
    static let textTrailingInset = BudgetMetrics.cellPadding - BudgetMetrics.fieldTrailingInset

    let model: BudgetViewModel
    let edit: BudgetCellEdit

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BudgetStyle.fieldCornerRadius)
        HStack(spacing: 0) {
            Button(action: model.dropDownButtonClicked) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ThemeColor.secondaryText)
                    .frame(width: BudgetMetrics.fieldButtonWidth, height: BudgetMetrics.fieldHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Auto-Verteilen")
            .toolTip("Auto-Verteilen und Rechner")
            BudgetCellField(model: model, edit: edit)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, Self.textTrailingInset)
        }
        .background(ThemeColor.fieldBackground, in: shape)
        .overlay { shape.strokeBorder(ThemeColor.accent, lineWidth: 1) }
        .focusRing(true, cornerRadius: BudgetStyle.fieldCornerRadius)
    }
}
