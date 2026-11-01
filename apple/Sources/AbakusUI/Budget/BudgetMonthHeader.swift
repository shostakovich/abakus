import AbakusCore
import SwiftUI

/// One block per month: its name and ⋮, Zu verteilen with the calculation folding out below, the column titles.
struct BudgetMonthHeader: View {
    let model: BudgetViewModel
    let month: BudgetMonth
    let width: CGFloat
    let cells: BudgetCellColumns
    let detailsHeight: CGFloat
    let progress: CGFloat

    var body: some View {
        let display = model.headerDisplay(month)
        VStack(alignment: .leading, spacing: 0) {
            title(display)
                .frame(height: BudgetMetrics.monthTitleHeight)
                .padding(.top, BudgetMetrics.headerTopPadding)
            BudgetMonthResult(model: model, month: month, display: display)
                .frame(height: BudgetMetrics.resultHeight)
                .padding(.top, BudgetMetrics.headerGap)
            BudgetMonthDetails(model: model, month: month)
                .frame(width: width, height: detailsHeight * progress, alignment: .bottomLeading)
                .opacity(Double(progress))
                .clipped()
                .allowsHitTesting(progress == 1)
            BudgetMonthColumnHead(model: model, month: month, display: display, cells: cells)
                .padding(.top, BudgetMetrics.headerGap)
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func title(_ display: BudgetMonthHeaderDisplay) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: display.title)
                .font(BudgetStyle.monthTitleFont.font)
                .foregroundStyle(display.isPast ? ThemeColor.secondaryText : ThemeColor.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            BudgetSymbolButton(
                symbol: "ellipsis", label: "Verteilen", toolTip: "Verteilen", rotation: .degrees(90)
            ) {
                model.present(.monthQuickBudget(month: month.month))
            }
            .budgetPopupAnchor(.monthQuickBudget(month.month), of: model)
        }
        .padding(.leading, BudgetStyle.resultInset)
        .padding(.trailing, 4)
    }
}

private struct BudgetMonthResult: View {
    let model: BudgetViewModel
    let month: BudgetMonth
    let display: BudgetMonthHeaderDisplay

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BudgetStyle.resultCornerRadius)
        return Button(action: model.toggleHeaderDetails) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(spacing: 4) {
                    Text(verbatim: month.resultLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: model.isHeaderExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(BudgetStyle.resultLabelFont.font)
                .foregroundStyle(ThemeColor.secondaryText)
                Spacer(minLength: 0)
                Text(verbatim: display.available)
                    .font(BudgetStyle.resultFont.font)
                    .foregroundStyle(amountStyle)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .padding(.horizontal, BudgetStyle.resultPadding)
            .frame(maxHeight: .infinity)
            .background(display.availableTint == .positive ? ThemeColor.positiveBand : ThemeColor.groupBand, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, BudgetStyle.resultInset)
        .toolTip(model.headerToggleToolTip)
        .accessibilityElement(children: .combine)
    }

    private var amountStyle: Color {
        switch display.availableTint {
        case .neutral: ThemeColor.text
        case .positive: ThemeColor.positive
        case .negative: ThemeColor.negative
        case .muted: ThemeColor.secondaryText
        }
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
        .padding(.leading, BudgetMetrics.cellPadding)
        .padding(.bottom, BudgetMetrics.headerDetailsPadding)
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

private struct BudgetMonthColumnHead: View {
    static let titles = ["Zugewiesen", "Aktivität", "Verfügbar"]

    let model: BudgetViewModel
    let month: BudgetMonth
    let display: BudgetMonthHeaderDisplay
    let cells: BudgetCellColumns
    @State private var isOutflowsHovered = false

    var body: some View {
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
                    total(display.totals[index], isOutflows: index == 1)
                }
                .lineLimit(1)
                .padding(.trailing, index == 2 ? BudgetStyle.availableDigitInset : BudgetMetrics.cellPadding)
                .frame(width: widths[index], alignment: .trailing)
            }
        }
        .padding(.bottom, BudgetStyle.columnHeadBottomPadding)
        .frame(height: BudgetMetrics.columnHeadHeight, alignment: .bottom)
    }

    @ViewBuilder
    private func total(_ total: BudgetTotal, isOutflows: Bool) -> some View {
        let figure = BudgetFigure(
            text: total.digits, font: BudgetStyle.totalFont,
            style: AnyShapeStyle(display.isPast ? ThemeColor.secondaryText : ThemeColor.text), suffix: total.suffix)
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
