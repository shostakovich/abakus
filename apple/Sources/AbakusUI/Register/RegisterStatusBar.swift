import SwiftUI

/// The Scheduled Transactions toggle with its count, and the selected total.
struct RegisterStatusBar: View {
    let model: RegisterViewModel

    var body: some View {
        HStack(spacing: 12) {
            scheduledToggle
            Spacer(minLength: 0)
            if let total = model.selectedTotal {
                SelectedTotalLabel(item: total)
            }
        }
        .padding(.horizontal, RegisterHeaderMetrics.horizontalPadding - 6)
        .frame(height: RegisterMetrics.statusBarHeight)
        .overlay(alignment: .top) { Divider() }
    }

    private var scheduledToggle: some View {
        let count = model.scheduler.scheduledTransactions.count
        let isVisible = Binding(get: { model.isSchedulerVisible }, set: { _ in model.scheduledToggleClicked() })
        return Toggle(isOn: isVisible) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                Text("Geplante Buchungen")
                if count > 0 {
                    Text(verbatim: String(count))
                        .font(ThemeFont.caption.font.monospacedDigit())
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(ThemeColor.groupFill))
                }
            }
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .toolTip(model.scheduledToggleTooltip)
        .registerAnchor(.schedulerTitle, isActive: !model.isSchedulerVisible)
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
