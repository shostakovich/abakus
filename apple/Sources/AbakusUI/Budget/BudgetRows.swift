import AbakusCore
import CoreGraphics
import Foundation

public struct BudgetCategoryRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case uncategorized, master, sub
    }

    public let id: String
    public let kind: Kind
    public let name: String
    public let masterId: String

    public var nameToolTip: String { name + "\n\nKlicken zum Umbenennen oder Löschen." }
}

struct BudgetCategoryFit: Hashable {
    let name: String
    let isMaster: Bool

    /// The name, the 2 pt gaps the row's HStack puts around it and its trailing padding.
    var rowWidth: CGFloat {
        let font = isMaster ? BudgetStyle.masterFont : BudgetStyle.nameFont
        return BudgetStyle.nameX + font.width(of: name) + 2 + 6
    }
}

public struct BudgetGroup: Identifiable, Hashable, Sendable {
    public let header: BudgetCategoryRow
    public let subs: [BudgetCategoryRow]
    public let isExpanded: Bool

    public var id: String { header.id }
    public var visibleRows: [BudgetCategoryRow] { isExpanded ? [header] + subs : [header] }
    public var height: CGFloat { CGFloat(visibleRows.count) * BudgetMetrics.rowHeight }
}

extension BudgetSheet {
    public var groups: [BudgetGroup] {
        var groups: [BudgetGroup] = []
        if showsUncategorizedRow {
            groups.append(
                BudgetGroup(
                    header: BudgetCategoryRow(
                        id: EntityID.uncategorizedMasterCategory, kind: .uncategorized,
                        name: DefaultCategories.uncategorizedName,
                        masterId: EntityID.uncategorizedMasterCategory),
                    subs: [], isExpanded: false))
        }
        for master in categoryGroups {
            let subs = master.categories.map { sub in
                BudgetCategoryRow(id: sub.id, kind: .sub, name: sub.name, masterId: master.id)
            }
            groups.append(
                BudgetGroup(
                    header: BudgetCategoryRow(
                        id: master.id, kind: .master, name: master.name, masterId: master.id),
                    subs: subs, isExpanded: isExpanded(master.id)))
        }
        return groups
    }
}

extension [BudgetGroup] {
    public var contentHeight: CGFloat { reduce(0) { $0 + $1.height } }

    public var visibleRows: [BudgetCategoryRow] { flatMap(\.visibleRows) }

    public var editableCategoryIds: [String] {
        filter(\.isExpanded).flatMap { $0.subs.map(\.id) }
    }

    public func top(of rowId: String) -> CGFloat? {
        var y: CGFloat = 0
        for group in self {
            for row in group.visibleRows {
                if row.id == rowId { return y }
                y += BudgetMetrics.rowHeight
            }
        }
        return nil
    }
}
