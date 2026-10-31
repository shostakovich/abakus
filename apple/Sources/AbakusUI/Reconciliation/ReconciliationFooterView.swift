import AbakusCore
import SwiftUI

enum ReconciliationFooterMetrics {
    static let labelFont = ThemeFont(size: 12)
    static let valueFont = ThemeFont(size: 12, weight: .semibold, hasTabularDigits: true)
    static let differenceFont = ThemeFont(size: 22, weight: .semibold, hasTabularDigits: true)
    static let operatorWidth: CGFloat = 14
}

/// The summary as an equation beside the difference as the key figure and the three actions; a narrow
/// register puts the actions under the equation.
struct ReconciliationFooterView: View {
    let reconciliation: RegisterReconciliationController

    var body: some View {
        if let footer = reconciliation.footer {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    ReconciliationEquation(rows: footer.rows)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 8) {
                        ReconciliationDifference(footer: footer)
                        message(footer)
                        actions
                    }
                }
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(alignment: .top, spacing: 22) {
                        ReconciliationEquation(rows: footer.rows)
                        Spacer(minLength: 0)
                        ReconciliationDifference(footer: footer)
                    }
                    HStack(alignment: .center, spacing: 22) {
                        message(footer)
                        actions
                    }
                }
            }
            .padding(.horizontal, RegisterHeaderMetrics.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func message(_ footer: ReconciliationFooterModel) -> some View {
        Text(verbatim: footer.message)
            .font(ThemeFont.caption.font)
            .foregroundStyle(ThemeColor.secondaryText)
            .multilineTextAlignment(.trailing)
            .fixedSize()
    }

    private var actions: some View {
        HStack(spacing: 8) {
            ForEach(ReconciliationAction.allCases, id: \.self) { action in
                if action == .finish {
                    Button(action.title) { reconciliation.perform(action) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(action.title) { reconciliation.perform(action) }
                }
            }
        }
        .fixedSize()
    }
}

private struct ReconciliationEquation: View {
    let rows: [ReconciliationFooterRow]

    var body: some View {
        let metrics = ReconciliationFooterMetrics.self
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if row.operation == .equals {
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
                GridRow {
                    Text(verbatim: row.label)
                        .font(metrics.labelFont.font)
                        .foregroundStyle(ThemeColor.secondaryText)
                    Text(verbatim: row.operation?.rawValue ?? "")
                        .font(metrics.valueFont.font)
                        .foregroundStyle(ThemeColor.tertiaryText)
                        .frame(width: metrics.operatorWidth)
                        .accessibilityHidden(true)
                    Text(verbatim: row.value)
                        .font(metrics.valueFont.font)
                        .foregroundStyle(ThemeColor.text)
                        .gridColumnAlignment(.trailing)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize()
    }
}

private struct ReconciliationDifference: View {
    let footer: ReconciliationFooterModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(verbatim: ReconciliationFooterModel.differenceTitle)
                .font(ThemeFont.caption.font)
                .foregroundStyle(ThemeColor.secondaryText)
            Text(verbatim: footer.difference)
                .font(ReconciliationFooterMetrics.differenceFont.font)
                .foregroundStyle(footer.isBalanced ? ThemeColor.balanced : ThemeColor.negative)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
