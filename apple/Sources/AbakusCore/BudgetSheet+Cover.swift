import Foundation

/// Money a category's overspending can be covered from: Zu verteilen or another category.
public struct BudgetFundsSource: Hashable, Sendable {
    public let categoryId: String
    public let name: String
    public let available: Decimal
    public let isReadyToAssign: Bool

    public init(categoryId: String, name: String, available: Decimal, isReadyToAssign: Bool = false) {
        self.categoryId = categoryId
        self.name = name
        self.available = available
        self.isReadyToAssign = isReadyToAssign
    }

    /// The overspending, as far as this source reaches.
    public func coverAmount(overspent balance: Decimal) -> Decimal {
        max(0, min(-balance, available))
    }

    public func remaining(afterCovering balance: Decimal) -> Decimal {
        Amount.round(available - coverAmount(overspent: balance))
    }
}

extension BudgetSheet {
    /// Zu verteilen while it has money, then the other categories with money, the most first.
    public func coverSources(for categoryId: String, in date: DateWithoutTime) -> [BudgetFundsSource] {
        guard let month = month(date) else { return [] }
        let readyToAssign =
            month.free > 0
            ? [
                BudgetFundsSource(
                    categoryId: budget.readyToAssignCategoryId, name: DefaultCategories.readyToAssignName,
                    available: month.free, isReadyToAssign: true)
            ] : []
        let categories = categoryGroups.flatMap(\.categories).compactMap { sub -> BudgetFundsSource? in
            guard sub.id != categoryId, let balance = month.category(sub.id)?.balance, balance > 0
            else { return nil }
            return BudgetFundsSource(categoryId: sub.id, name: sub.name, available: balance)
        }
        return readyToAssign + categories.sorted { $0.available > $1.available }
    }
}
