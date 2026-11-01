import SwiftUI

enum RegisterHeaderMetrics {
    static let horizontalPadding: CGFloat = 16
    static let amountFont = ThemeFont(size: 17, weight: .semibold, hasTabularDigits: true)
}

/// The account name with its reconcile date and the pencil; Gebucht + Vorgemerkt = Arbeitssaldo and Abgleichen.
struct RegisterHeader: View {
    let model: RegisterViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: model.accountName)
                        .font(ThemeFont.largeTitle.font)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityAddTraits(.isHeader)
                    if model.account != nil { editAccountButton }
                }
                if let reconciled = model.reconciledLabel {
                    Label(reconciled, systemImage: "lock")
                        .font(ThemeFont.caption.font)
                        .foregroundStyle(ThemeColor.secondaryText)
                }
            }
            Spacer(minLength: 16)
            RegisterSummaryView(model: model, summary: model.summary)
                .layoutPriority(1)
            reconcileButton
        }
        .padding(.horizontal, RegisterHeaderMetrics.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var editAccountButton: some View {
        Button(action: model.editAccountClicked) {
            Image(systemName: "pencil")
                .foregroundStyle(ThemeColor.secondaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(EditAccountForm.title)
        .help(EditAccountForm.title)
    }

    private var reconcileButton: some View {
        let reconciliation = model.reconciliation
        return Button(action: reconciliation.reconcileClicked) {
            Label("Abgleichen", systemImage: "lock")
        }
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .disabled(!reconciliation.isReconcileEnabled)
        .overlay {
            if !reconciliation.isReconcileEnabled {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: reconciliation.reconcileDisabledClicked)
            }
        }
        .toolTip(reconciliation.reconcileTooltip)
    }
}

/// The operands only show while both are Cleared and Uncleared; a search puts its total in their place.
struct RegisterSummaryView: View {
    let model: RegisterViewModel
    let summary: RegisterSummary

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            item(summary.first)
            if summary.showsOperands { operand("+") }
            item(summary.second)
            if summary.showsOperands { operand("=") } else { Divider().frame(height: 28) }
            item(summary.working)
        }
        .fixedSize()
    }

    @ViewBuilder
    private func item(_ item: RegisterSummaryItem) -> some View {
        if item.kind != .blank {
            if item.isClickable {
                Button {
                    model.summaryClicked(item.kind)
                } label: {
                    SummaryItemLabel(item: item)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .toolTip(item.tooltip)
            } else {
                SummaryItemLabel(item: item).toolTip(item.tooltip)
            }
        }
    }

    private func operand(_ symbol: String) -> some View {
        Text(verbatim: symbol)
            .font(RegisterHeaderMetrics.amountFont.font)
            .foregroundStyle(ThemeColor.secondaryText)
            .accessibilityHidden(true)
    }
}

struct SummaryItemLabel: View {
    let item: RegisterSummaryItem

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(verbatim: item.title)
                .font(ThemeFont.caption.font)
                .foregroundStyle(ThemeColor.secondaryText)
            Text(verbatim: item.amountText)
                .font(RegisterHeaderMetrics.amountFont.font)
                .foregroundStyle(item.isNegative ? ThemeColor.negative : ThemeColor.text)
        }
        .lineLimit(1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
