import AbakusCore
import SwiftUI

struct BudgetMonthCard: View {
    static let titleHeight: CGFloat = 38

    let model: BudgetViewModel
    let month: BudgetMonth
    let width: CGFloat
    let height: CGFloat
    let detailsHeight: CGFloat
    let progress: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BudgetStyle.cardCornerRadius)
        VStack(spacing: 0) {
            title
            Divider()
            BudgetMonthDetails(model: model, month: month)
                .frame(height: detailsHeight * progress, alignment: .bottom)
                .opacity(Double(progress))
                .clipped()
                .allowsHitTesting(progress == 1)
            result
            Spacer(minLength: 0)
        }
        .frame(width: width, height: height)
        .background(ThemeColor.contentBackground, in: shape)
        .overlay { shape.strokeBorder(ThemeColor.separator, lineWidth: 1) }
        .clipShape(shape)
    }

    private var title: some View {
        let name = model.formatter.shortMonthName(month.month.month) + " " + String(month.month.year)
        return ZStack {
            Text(verbatim: name)
                .font(BudgetStyle.monthTitleFont.font)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                BudgetSymbolButton(
                    symbol: "bolt.fill", label: "Verteilen", toolTip: "Verteilen"
                ) { model.present(.monthQuickBudget(month: month.month)) }
                .budgetPopupAnchor(.monthQuickBudget(month.month), of: model)
            }
            .padding(.trailing, 6)
        }
        .frame(height: Self.titleHeight)
    }

    private var result: some View {
        let display = model.headerDisplay(month)
        let style: AnyShapeStyle =
            switch display.availableTint {
            case .neutral: AnyShapeStyle(ThemeColor.text)
            case .balanced: AnyShapeStyle(ThemeColor.balanced)
            case .negative: AnyShapeStyle(ThemeColor.negative)
            }
        return Button(action: model.toggleHeaderDetails) {
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Text(verbatim: month.resultLabel)
                    Image(systemName: model.isHeaderExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(BudgetStyle.columnTitleFont.font)
                .foregroundStyle(ThemeColor.secondaryText)
                Text(verbatim: display.available)
                    .font(BudgetStyle.availableFont.font)
                    .foregroundStyle(style)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .toolTip(model.headerToggleToolTip)
        .accessibilityElement(children: .combine)
    }
}

private struct BudgetMonthDetails: View {
    let model: BudgetViewModel
    let month: BudgetMonth
    @State private var isIncomeHovered = false

    var body: some View {
        let lines = month.headerLines(formatter: model.formatter)
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let isIncome = index == 2
                GridRow {
                    Text(verbatim: line.amount)
                        .font(BudgetStyle.detailAmountFont.font)
                        .foregroundStyle(line.isWarning ? ThemeColor.negative : ThemeColor.text)
                        .gridColumnAlignment(.trailing)
                    Text(verbatim: line.text)
                        .font(BudgetStyle.detailFont.font)
                        .foregroundStyle(line.isWarning ? ThemeColor.negative : ThemeColor.secondaryText)
                }
                .lineLimit(1)
                .underline(isIncome && isIncomeHovered)
                .modifier(
                    BudgetIncomeLink(model: model, month: month.month, isOn: isIncome, isHovered: $isIncomeHovered))
            }
        }
        .padding(.bottom, 4)
    }
}

private struct BudgetIncomeLink: ViewModifier {
    let model: BudgetViewModel
    let month: DateWithoutTime
    let isOn: Bool
    @Binding var isHovered: Bool

    func body(content: Content) -> some View {
        if isOn {
            content
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .onTapGesture { model.present(.incomeSummary(month: month)) }
                .pointerStyle(.link)
                .toolTip("Einnahmen zeigen")
                .budgetPopupAnchor(.incomeLine(month), of: model)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}

struct BudgetMonthHeaderCell: View {
    static let titles = ["Zugewiesen", "Aktivität", "Verfügbar"]

    let model: BudgetViewModel
    let month: BudgetMonth
    let cells: BudgetCellColumns
    @State private var isOutflowsHovered = false

    var body: some View {
        let totals = model.headerDisplay(month).totals
        let widths = [cells.assigned, cells.outflows, cells.balance]
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: Self.titles[index])
                        .font(BudgetStyle.columnTitleFont.font)
                        .foregroundStyle(ThemeColor.secondaryText)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                    total(totals[index], isOutflows: index == 1)
                }
                .lineLimit(1)
                .padding(.trailing, BudgetMetrics.cellPadding)
                .frame(width: widths[index], alignment: .trailing)
            }
        }
        .padding(.bottom, 6)
        .frame(height: BudgetMetrics.tableHeaderHeight, alignment: .bottom)
    }

    @ViewBuilder
    private func total(_ total: BudgetTotal, isOutflows: Bool) -> some View {
        let figure = BudgetFigure(
            text: total.digits, zero: "", font: BudgetStyle.totalFont, suffix: total.suffix)
        if isOutflows {
            figure
                .underline(isOutflowsHovered && month.hasTransactions)
                .budgetPopupAnchor(.totalsOutflows(month.month), of: model)
                .contentShape(Rectangle())
                .onHover { isOutflowsHovered = $0 }
                .onTapGesture { model.totalsOutflowsClicked(month: month.month) }
                .pointerStyle(month.hasTransactions ? .link : .default)
        } else {
            figure
        }
    }
}
