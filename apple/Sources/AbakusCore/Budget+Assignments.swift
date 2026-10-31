import Foundation

extension Budget {
    mutating func setAssigned(_ amount: Decimal, month: DateWithoutTime, categoryId: String) throws {
        try requireBudgetCategory(categoryId)
        let rounded = Amount.round(amount)
        guard rounded.isFinite else { throw BudgetError.amountNotFinite }
        setAssignment(rounded, month: month, categoryId: categoryId)
    }

    mutating func moveAssigned(_ amount: Decimal, month: DateWithoutTime, from: String, to: String) throws {
        let sides: [String] = [from, to].filter { !isReadyToAssign($0) }
        for side in sides { try requireBudgetCategory(side) }
        let rounded = Amount.round(amount)
        guard rounded.isFinite else { throw BudgetError.amountNotFinite }
        guard rounded > 0, from != to else { return }
        addAssigned(-rounded, month: month, categoryId: from)
        addAssigned(rounded, month: month, categoryId: to)
    }

    mutating func addAssigned(_ amount: Decimal, month: DateWithoutTime, categoryId: String) {
        guard !isReadyToAssign(categoryId) else { return }
        setAssignment(assigned(in: month, categoryId: categoryId) + amount, month: month, categoryId: categoryId)
    }

    /// The category's own assignment plus those of the deleted categories that count for it.
    public func assigned(in month: DateWithoutTime, categoryId: String) -> Decimal {
        let first = month.firstOfMonth
        return Amount.sum(assignments.filter { $0.categoryId == categoryId && $0.month == first }.map(\.amount))
    }

    var budgetCategoryIds: Set<String> {
        Set(budgetCategoryGroups.flatMap(\.categories).map(\.id))
    }

    func requireBudgetCategory(_ categoryId: String) throws {
        if !budgetCategoryIds.contains(categoryId) { throw BudgetError.categoryNotFound(categoryId) }
    }

    /// Nothing assigned is no row; `amount` is what the category shows, inherited assignments included.
    mutating func setAssignment(_ amount: Decimal, month: DateWithoutTime, categoryId: String) {
        let ownId = EntityID.assignment(categoryId: categoryId, month: month)
        let inherited = Amount.sum(
            assignments.filter { $0.categoryId == categoryId && $0.month == month.firstOfMonth && $0.id != ownId }
                .map(\.amount))
        let assignment = Assignment(categoryId: categoryId, month: month, amount: amount - inherited)
        if let index = assignments.firstIndex(where: { $0.id == assignment.id }) {
            if assignment.amount == 0 { assignments.remove(at: index) } else { assignments[index] = assignment }
        } else if assignment.amount != 0 {
            assignments.append(assignment)
        }
    }

    mutating func removeBudgetData(ofCategories ids: Set<String>) {
        assignments.removeAll { ids.contains($0.categoryId) }
        targetVersions.removeAll { ids.contains($0.categoryId) }
        targetSnoozes.removeAll { ids.contains($0.categoryId) }
    }
}
