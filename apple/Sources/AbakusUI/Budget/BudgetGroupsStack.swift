import SwiftUI

struct BudgetGroupsStack<Header: View, Sub: View>: View {
    let groups: [BudgetGroup]
    let offset: CGFloat
    @ViewBuilder let header: (BudgetGroup) -> Header
    @ViewBuilder let sub: (BudgetCategoryRow) -> Sub

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    header(group)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.subs) { row in
                            sub(row)
                        }
                    }
                    .frame(
                        height: group.isExpanded ? CGFloat(group.subs.count) * BudgetMetrics.rowHeight : 0,
                        alignment: .top
                    )
                    .clipped()
                    .contentShape(Rectangle())
                    .allowsHitTesting(group.isExpanded)
                }
            }
        }
        .animation(.motion(BudgetStyle.groupResize), value: groups.map(\.isExpanded))
        .offset(y: -offset)
    }
}

/// Runs under every column and the separators between them: the master tint and a hairline under every row.
struct BudgetRowBackgrounds: View {
    let groups: [BudgetGroup]
    let offset: CGFloat
    let width: CGFloat

    var body: some View {
        BudgetGroupsStack(groups: groups, offset: offset) { group in
            row(isTinted: group.header.kind != .sub)
        } sub: { _ in
            row(isTinted: false)
        }
        .allowsHitTesting(false)
    }

    private func row(isTinted: Bool) -> some View {
        ZStack(alignment: .bottom) {
            if isTinted { Rectangle().fill(ThemeColor.groupFill) }
            Rectangle().fill(ThemeColor.separator).frame(height: 1)
        }
        .frame(width: width, height: BudgetMetrics.rowHeight, alignment: .bottom)
    }
}
