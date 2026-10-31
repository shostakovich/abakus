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
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.trailing, BudgetMetrics.cellPadding)
            .frame(width: width, height: BudgetMetrics.rowHeight, alignment: .trailing)
    }
}

private struct BudgetOutflowsFigure: View {
    let model: BudgetViewModel
    let text: String
    let font: ThemeFont
    let style: AnyShapeStyle
    let hasTransactions: Bool
    let anchor: BudgetPopupAnchor
    var toolTip: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        BudgetFigure(text: text, zero: model.zeroText, font: font, style: style)
            .underline(isHovered && hasTransactions)
            .budgetPopupAnchor(anchor, of: model)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
            .pointerStyle(hasTransactions ? .link : .default)
            .toolTip(toolTip)
            .accessibilityAddTraits(hasTransactions ? .isButton : [])
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
        let text = AnyShapeStyle(ThemeColor.text)
        HStack(spacing: 0) {
            BudgetCell(width: cells.assigned) {
                if let assigned = display.assigned {
                    BudgetFigure(text: assigned, zero: model.zeroText, font: font)
                } else {
                    // An empty cell would collapse and pull the other figures into its column.
                    Color.clear
                }
            }
            BudgetCell(width: cells.outflows) {
                BudgetOutflowsFigure(
                    model: model, text: display.outflows, font: font, style: text,
                    hasTransactions: display.hasTransactions, anchor: .outflows(month.month, row.id)
                ) { model.masterOutflowsClicked(month: month.month, masterId: row.id) }
            }
            BudgetCell(width: cells.balance) {
                BudgetFigure(
                    text: display.balance, zero: model.zeroText,
                    font: display.isBalanceNegative ? BudgetStyle.masterNegativeFont : font,
                    style: display.isBalanceNegative ? AnyShapeStyle(ThemeColor.negative) : text)
            }
        }
        .frame(height: BudgetMetrics.rowHeight)
        .contentShape(Rectangle())
        .onHover { model.rowHovered(row.id, in: .month(month.month), $0) }
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
                    style: AnyShapeStyle(ThemeColor.secondaryText), hasTransactions: display.hasTransactions,
                    anchor: .outflows(month.month, row.id),
                    toolTip: display.outflows.isEmpty ? nil : "Buchungen zeigen"
                ) { model.subOutflowsClicked(month: month.month, categoryId: row.id) }
            }
            balance(display)
        }
        .frame(height: BudgetMetrics.rowHeight)
        .contentShape(Rectangle())
        .onHover { model.rowHovered(row.id, in: .month(month.month), $0) }
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
                    BudgetFigure(text: display.assigned, zero: model.zeroText)
                }
                .background(alignment: .topLeading) {
                    if model.hoveredRow == row.id {
                        RoundedRectangle(cornerRadius: BudgetStyle.fieldCornerRadius)
                            .fill(ThemeColor.groupFill)
                            .frame(width: field.width, height: field.height)
                            .offset(x: field.minX, y: field.minY)
                    }
                }
                .contentShape(Rectangle())
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
        let value = display.balance.isEmpty ? model.zeroText : display.balance
        return BudgetCell(width: cells.balance) {
            HStack(spacing: BudgetStyle.markerSpacing) {
                if let marker = display.marker {
                    Image(systemName: marker.symbol.name)
                        .font(.system(size: BudgetStyle.markerSize))
                        .foregroundStyle(marker.symbol.color)
                }
                BudgetFigure(
                    text: display.balance, zero: model.zeroText,
                    font: display.isOverspent ? BudgetStyle.overspentFont : BudgetStyle.balanceFont,
                    style: balanceStyle(display))
            }
            .budgetPopupAnchor(.balance(month.month, row.id), of: model)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.balanceClicked(month: month.month, categoryId: row.id) }
        .pointerStyle(.link)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Verfügbar")
        .accessibilityValue(display.marker.map { "\(value), \($0.label)" } ?? value)
    }

    private func balanceStyle(_ display: BudgetSubRowDisplay) -> AnyShapeStyle {
        if display.isBalanceNegative { return AnyShapeStyle(ThemeColor.negative) }
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
