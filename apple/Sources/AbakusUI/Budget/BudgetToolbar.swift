import SwiftUI

struct BudgetToolbar: ToolbarContent {
    static let title = "Budget"

    let model: BudgetViewModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(verbatim: Self.title)
                .font(ThemeFont.headline.font)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .principal) {
            BudgetTimeline(model: model)
        }
    }
}

struct BudgetTimeline: View {
    static let monthHeight: CGFloat = 26

    let model: BudgetViewModel

    var body: some View {
        let cells = model.timelineCells()
        HStack(spacing: 0) {
            arrow("chevron.left", label: "Früher", action: model.previousMonthClicked)
            Text(verbatim: String(model.timelineYear))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ThemeColor.secondaryText)
                .padding(.horizontal, 8)
            ForEach(cells, id: \.month) { cell in
                month(cell, in: cells)
            }
            arrow("chevron.right", label: "Später", action: model.nextMonthClicked)
        }
        .animation(.motion(BudgetStyle.indicatorMove), value: model.firstMonth)
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: Self.monthHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func month(_ cell: BudgetTimelineCell, in cells: [BudgetTimelineCell]) -> some View {
        let previousShown = cell.month > 1 && cells[cell.month - 2].isShown
        let nextShown = cell.month < 12 ? cells[cell.month].isShown : model.showsTimelineEnd
        let foreground: AnyShapeStyle =
            cell.isShown
            ? AnyShapeStyle(ThemeColor.selectedText)
            : cell.hasNoData ? AnyShapeStyle(ThemeColor.tertiaryText) : AnyShapeStyle(ThemeColor.text)
        return Button {
            model.timelineMonthClicked(cell.month)
        } label: {
            Text(verbatim: cell.label)
                .font(.system(size: 12, weight: cell.isCurrent ? .bold : (cell.isShown ? .semibold : .regular)))
                .foregroundStyle(foreground)
                .padding(.horizontal, 7)
                .frame(height: Self.monthHeight)
                .background {
                    if cell.isShown {
                        UnevenRoundedRectangle(
                            topLeadingRadius: previousShown ? 0 : Self.monthHeight / 2,
                            bottomLeadingRadius: previousShown ? 0 : Self.monthHeight / 2,
                            bottomTrailingRadius: nextShown ? 0 : Self.monthHeight / 2,
                            topTrailingRadius: nextShown ? 0 : Self.monthHeight / 2
                        )
                        .fill(ThemeColor.accent)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.timelineMonthTitle(cell.month))
        .accessibilityAddTraits(cell.isShown ? .isSelected : [])
    }
}
