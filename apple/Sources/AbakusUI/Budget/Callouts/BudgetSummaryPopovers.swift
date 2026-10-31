import AbakusCore
import SwiftUI

struct BudgetSummaryPopover: View {
    static let width: CGFloat = 470

    let controller: BudgetCalloutController
    let summary: TransactionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverTitle(summary.title)
            Text(TextMarkup.attributed(summary.message))
                .fixedSize(horizontal: false, vertical: true)
            BudgetSummaryTable(
                rows: summary.rows, formatter: controller.formatter, onClick: controller.summaryRowClicked)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Im Konto zeigen", action: controller.showInAccountViewClicked)
                    .disabled(summary.rows.isEmpty)
                Button("Schließen", action: controller.summaryClosed)
            }
        }
        .font(ThemeFont.body.font)
        .foregroundStyle(ThemeColor.text)
        .frame(width: Self.width, alignment: .leading)
    }
}

private struct BudgetSummaryTable: View {
    static let columns: [(title: String, width: CGFloat, alignment: Alignment)] = [
        ("Datum", 70, .leading), ("Konto", 100, .leading), ("Empfänger", 100, .leading), ("Memo", 100, .leading),
        ("Betrag", 76, .trailing),
    ]
    static let headerHeight: CGFloat = 24
    static let inset: CGFloat = 4

    let rows: [TransactionSummaryRow]
    let formatter: BudgetFormatter
    let onClick: (TransactionSummaryRow) -> Void

    var body: some View {
        let rowsHeight = SystemChrome.menuRowHeight * CGFloat(rows.count) + 2 * Self.inset
        let height = min(max(Self.headerHeight + rowsHeight, 100), 200)
        VStack(spacing: 0) {
            cells(Self.columns.map(\.title))
                .font(ThemeFont.caption.font.weight(.semibold))
                .foregroundStyle(ThemeColor.secondaryText)
                .padding(.horizontal, Self.inset + 8)
                .frame(height: Self.headerHeight)
                .accessibilityAddTraits(.isHeader)
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            onClick(row)
                        } label: {
                            cells([
                                formatter.dateShort(row.date), row.accountName, row.payee, row.memo,
                                formatter.currencyNoSymbol(row.amount),
                            ])
                        }
                    }
                }
                .buttonStyle(PopoverMenuButtonStyle())
                .padding(Self.inset)
            }
            .scrollIndicators(rowsHeight > height - Self.headerHeight ? .visible : .never)
        }
        .frame(height: height, alignment: .top)
        .background(ThemeColor.contentBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(ThemeColor.separator) }
    }

    private func cells(_ texts: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.columns.enumerated()), id: \.offset) { index, column in
                Text(verbatim: texts[index])
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, index == Self.columns.count - 1 ? 0 : 8)
                    .frame(width: column.width, alignment: column.alignment)
            }
        }
    }
}

struct BudgetOutflowHelpPopover: View {
    static let width: CGFloat = 340

    let controller: BudgetCalloutController
    let help: BudgetOutflowHelp
    @State private var isChecked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverTitle(BudgetOutflowHelp.title)
            Text(TextMarkup.attributed(help.message))
                .fixedSize(horizontal: false, vertical: true)
            Toggle(
                BudgetOutflowHelp.checkbox,
                isOn: Binding(
                    get: { isChecked },
                    set: { checked in
                        guard checked else { return }
                        isChecked = true
                        controller.dontShowOutflowHelpAgainClicked()
                    })
            )
            .toggleStyle(.checkbox)
        }
        .font(ThemeFont.body.font)
        .foregroundStyle(ThemeColor.text)
        .frame(width: Self.width, alignment: .leading)
    }
}
