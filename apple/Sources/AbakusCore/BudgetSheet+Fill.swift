import Foundation

/// What filling adds to a category's assignment.
public struct BudgetFill: Hashable, Sendable {
    public let categoryId: String
    public let amount: Decimal

    public init(categoryId: String, amount: Decimal) {
        self.categoryId = categoryId
        self.amount = amount
    }
}

extension BudgetSheet {
    private var categoryIdsInBudgetOrder: [String] {
        categoryGroups.flatMap(\.categories).map(\.id)
    }

    /// What the month's targets still ask, snoozed ones left out.
    public func underfunded(in date: DateWithoutTime) -> Decimal {
        guard let month = month(date) else { return 0 }
        return Amount.sum(categoryIdsInBudgetOrder.map { month.openNeed($0) })
    }

    /// Abakus's `fill_underfunded`: in budget order as far as the month's free money reaches, the last one partly.
    public func underfundedFills(in date: DateWithoutTime) -> [BudgetFill] {
        guard let month = month(date) else { return [] }
        var left = month.free
        var fills: [BudgetFill] = []
        for id in categoryIdsInBudgetOrder {
            let amount = min(month.openNeed(id), left)
            guard amount > 0 else { continue }
            fills.append(BudgetFill(categoryId: id, amount: amount))
            left = Amount.round(left - amount)
        }
        return fills
    }

    public func firstUnderfunded(in date: DateWithoutTime) -> String? {
        guard let month = month(date) else { return nil }
        return categoryIdsInBudgetOrder.first { month.openNeed($0) > 0 }
    }

    /// What the category's target still asks as far as the free money reaches, else all of it.
    public func assignSuggestion(categoryId: String, in date: DateWithoutTime) -> Decimal {
        guard let month = month(date) else { return 0 }
        let need = month.openNeed(categoryId)
        return need > 0 ? min(need, month.free) : month.free
    }
}

extension BudgetMonth {
    fileprivate func openNeed(_ categoryId: String) -> Decimal {
        category(categoryId)?.target?.openNeed ?? 0
    }
}

extension Budget {
    mutating func fillUnderfunded(month: DateWithoutTime, today: DateWithoutTime) {
        for fill in budgetSheet(today: today, including: [month]).underfundedFills(in: month) {
            addAssigned(fill.amount, month: month, categoryId: fill.categoryId)
        }
    }
}
