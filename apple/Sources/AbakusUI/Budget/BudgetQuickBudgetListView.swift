import SwiftUI

struct BudgetQuickBudgetListView: View {
    let model: BudgetViewModel
    let list: BudgetQuickBudgetList

    var body: some View {
        VStack(spacing: 0) {
            ForEach(list.options.indices, id: \.self) { index in
                row(index) {
                    EmptyView()
                } trailing: {
                    Text(verbatim: model.formatter.currencyNoSymbol(list.options[index].amount))
                        .font(BudgetQuickBudgetList.amountFont.font)
                }
            }
            Divider()
                .padding(.horizontal, 10)
                .frame(height: BudgetQuickBudgetList.separatorHeight)
            row(list.options.count) {
                Image(systemName: "plus.forwardslash.minus")
                    .frame(width: BudgetQuickBudgetList.iconWidth)
                    .padding(.trailing, BudgetQuickBudgetList.iconGap)
                    .accessibilityHidden(true)
            } trailing: {
                EmptyView()
            }
        }
        .padding(.vertical, SystemChrome.menuPadding)
        .frame(width: list.width)
        .font(BudgetQuickBudgetList.labelFont.font)
        .systemMenuChrome()
        .floatingShadow()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Auto-Verteilen")
    }

    private func row(
        _ index: Int, @ViewBuilder leading: () -> some View, @ViewBuilder trailing: () -> some View
    ) -> some View {
        let isHighlighted = list.highlighted == index
        let label =
            list.options.indices.contains(index)
            ? list.options[index].label : BudgetQuickBudgetList.calculatorLabel
        return HStack(spacing: 0) {
            leading()
            Text(verbatim: BudgetQuickBudgetList.label(label))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: BudgetQuickBudgetList.gap)
            trailing()
        }
        .foregroundStyle(isHighlighted ? ThemeColor.selectedText : ThemeColor.text)
        .padding(.horizontal, 10)
        .frame(height: BudgetQuickBudgetList.rowHeight)
        .background {
            if isHighlighted { RoundedRectangle(cornerRadius: 4).fill(ThemeColor.accent) }
        }
        .padding(.horizontal, SystemChrome.menuPadding)
        .contentShape(Rectangle())
        .onHover { if $0 { model.quickBudgetRowHovered(index) } }
        .onTapGesture { model.quickBudgetChosen(index) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }
}
