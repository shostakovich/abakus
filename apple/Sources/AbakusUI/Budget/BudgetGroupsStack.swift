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

/// Runs under every column and the separators between them: the group band and a hairline under every row.
struct BudgetRowBackgrounds: View {
    let groups: [BudgetGroup]
    let offset: CGFloat
    let width: CGFloat
    /// Verfügbar of each month, which the group band takes some of its tint from.
    let tints: [CGRect]

    var body: some View {
        BudgetGroupsStack(groups: groups, offset: offset) { group in
            row(isBand: group.header.kind != .sub)
        } sub: { _ in
            row(isBand: false)
        }
        .allowsHitTesting(false)
    }

    private func row(isBand: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            if isBand {
                Rectangle().fill(ThemeColor.groupBand)
                ForEach(tints, id: \.minX) { tint in
                    Rectangle().fill(ThemeColor.availableTint.opacity(BudgetStyle.groupAvailableTintOpacity))
                        .frame(width: tint.width)
                        .offset(x: tint.minX)
                }
            }
            Rectangle().fill(ThemeColor.separator).frame(height: 1)
        }
        .frame(width: width, height: BudgetMetrics.rowHeight, alignment: .bottomLeading)
    }
}
