#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    struct BudgetPhoneView: View {
        let model: BudgetViewModel
        @State private var amountWidth: CGFloat?

        var body: some View {
            if let month = model.shownMonths.first.flatMap(model.month) {
                List {
                    ForEach(model.groups.listRows) { item in
                        switch item.row.kind {
                        case .master:
                            BudgetGroupLabel(model: model, group: item.group) {
                                groupBalance(item.group, in: month)
                            }
                            .listRowBackground(ThemeColor.groupBand)
                        case .uncategorized:
                            BudgetPhoneUncategorizedRow(model: model, row: item.row, month: month)
                                .moveDisabled(true)
                        case .sub:
                            BudgetPhoneCategoryRow(model: model, row: item.row, month: month, amountWidth: amountWidth)
                        }
                    }
                    .onMove(perform: model.touchRowsMoved)
                    BudgetAddGroupButton(model: model)
                }
                .listStyle(.plain)
                .scrollsUnderDock()
                .scrollContentBackground(.hidden)
                .background(ThemeColor.contentBackground)
                .background { widestAmount(in: month) }
                .safeAreaInset(edge: .top, spacing: 0) {
                    BudgetPhoneHeader(model: model, month: month)
                }
            }
        }

        /// Every category's Verfügbar takes the widest one's width, so the target bars end at one edge.
        private func widestAmount(in month: BudgetMonth) -> some View {
            let amounts = Set(model.groups.flatMap(\.subs).map { model.subRowDisplay($0.id, in: month).balance })
            return ZStack {
                ForEach(Array(amounts), id: \.self) { Text(verbatim: $0) }
            }
            .fontWeight(.semibold)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { amountWidth = $0.rounded(.up) }
        }

        private func groupBalance(_ group: BudgetGroup, in month: BudgetMonth) -> some View {
            let display = model.masterRowDisplay(group.header, in: month)
            return Text(verbatim: display.balance)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(display.isBalanceNegative ? ThemeColor.negative : ThemeColor.text)
                .padding(.trailing, BudgetStyle.markerSlot)
        }
    }

    private struct BudgetPhoneHeader: View {
        let model: BudgetViewModel
        let month: BudgetMonth
        @State private var amountInset: CGFloat = 14

        var body: some View {
            let waiting = model.waiting(in: month)
            VStack(spacing: 0) {
                if model.isHeaderExpanded {
                    BudgetCalculation(
                        model: model, month: month, amountInset: amountInset, horizontalPadding: 16
                    )
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                BudgetResultBand(model: model, month: month, amountInset: $amountInset)
                    .padding(.horizontal, 16)
                BudgetWaitingLine(model: model, month: month, waiting: waiting)
                    .padding(.horizontal, 16)
            }
            .padding(.top, model.isHeaderExpanded ? 0 : 6)
            .padding(.bottom, waiting.isEmpty ? 10 : 0)
            .background(ThemeColor.contentBackground)
            .overlay(alignment: .bottom) { Rectangle().fill(ThemeColor.separator).frame(height: 0.5) }
        }
    }

    private struct BudgetPhoneCategoryRow: View {
        let model: BudgetViewModel
        let row: BudgetCategoryRow
        let month: BudgetMonth
        let amountWidth: CGFloat?

        var body: some View {
            let display = model.subRowDisplay(row.id, in: month)
            Button {
                model.categoryTapped(row.id, month: month.month)
            } label: {
                HStack(spacing: 12) {
                    BudgetCategoryName(name: row.name, bar: display.targetBar)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BudgetAvailableFigure(display: display, month: month, showsRing: false, amountWidth: amountWidth)
                }
                .padding(.leading, BudgetTouchStyle.nameIndent)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.name)
            .accessibilityValue("Verfügbar \(display.barAccessibilityValue)")
            .accessibilityAddTraits(.isButton)
        }
    }

    private struct BudgetPhoneUncategorizedRow: View {
        let model: BudgetViewModel
        let row: BudgetCategoryRow
        let month: BudgetMonth

        var body: some View {
            let display = model.masterRowDisplay(row, in: month)
            Button(action: model.uncategorizedTapped) {
                HStack(spacing: 12) {
                    BudgetCategoryName(name: row.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: display.balance.isEmpty ? model.zeroText : display.balance)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(display.isBalanceNegative ? ThemeColor.negative : ThemeColor.text)
                        .padding(.trailing, BudgetStyle.markerSlot)
                }
                .padding(.leading, BudgetTouchStyle.nameIndent)
                .contentShape(Rectangle())
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Buchungen ohne Kategorie zeigen")
        }
    }
#endif
