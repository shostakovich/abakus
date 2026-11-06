import AbakusUI
import SwiftUI

struct RegisterStatusBar: View {
    let model: RegisterViewModel

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if let total = model.selectedTotal {
                SelectedTotalLabel(item: total)
            }
        }
        .padding(.horizontal, RegisterHeaderMetrics.horizontalPadding - 6)
        .frame(height: RegisterMetrics.statusBarHeight)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct SelectedTotalLabel: View {
    let item: RegisterSummaryItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: item.title)
                .foregroundStyle(ThemeColor.secondaryText)
            Text(verbatim: item.amountText)
                .font(ThemeFont.tableEmphasized.font)
                .foregroundStyle(item.isNegative ? ThemeColor.negative : ThemeColor.text)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .toolTip(item.tooltip)
    }
}
