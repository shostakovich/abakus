import Foundation

extension Budget {
    public func hasReconciledTransactions(inCategory id: String) -> Bool {
        transactions.contains { transaction in
            transaction.cleared == .reconciled
                && (transaction.categoryId == id || transaction.subtransactions.contains { $0.categoryId == id })
        }
    }

    mutating func addCategoryGroup(id: String) {
        guard categoryGroup(withId: id) == nil else { return }
        let name = Self.firstFreeName("Neue Kategoriegruppe", taken: categoryGroups.map(\.name))
        categoryGroups.append(CategoryGroup(id: id, name: name))
        reorderGroups([id] + budgetCategoryGroups.map(\.id).filter { $0 != id })
    }

    mutating func addCategory(groupId: String, id: String) throws {
        let index = try groupIndex(groupId)
        guard category(withId: id) == nil else { return }
        collapsedCategoryGroupIds.remove(groupId)
        let name = Self.firstFreeName("Neue Kategorie", taken: categoryGroups[index].categories.map(\.name))
        appendCategory(Category(id: id, categoryGroupId: groupId, name: name))
    }

    private static func firstFreeName(_ base: String, taken: [String]) -> String {
        let used = Set(taken.map { $0.lowercased() })
        var number = 1
        while true {
            let name = number == 1 ? base : "\(base) \(number)"
            if !used.contains(name.lowercased()) { return name }
            number += 1
        }
    }

    mutating func renameCategoryGroup(_ id: String, to text: String) throws {
        let index = try groupIndex(id)
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != categoryGroups[index].name else { return }
        if name.isEmpty { throw BudgetError.categoryMustHaveName }
        if CategoryNames.containsIllegalCharacters(name) { throw BudgetError.categoryIllegalCharacters }
        if CategoryNames.isIncomeGroupName(name) { throw BudgetError.categoryCantBeIncome }
        if CategoryNames.isReservedGroupName(name) { throw BudgetError.categoryIsReserved }
        let taken = categoryGroups.filter { $0.id != id }.map(\.name) + [DefaultCategories.uncategorizedName]
        if taken.contains(where: { $0.lowercased() == name.lowercased() }) { throw BudgetError.categoryNameUsed }
        categoryGroups[index].name = name
    }

    mutating func renameCategory(_ id: String, to text: String) throws {
        let location = try categoryLocation(id)
        let category = categoryGroups[location.group].categories[location.category]
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != category.name else { return }
        if name.isEmpty { throw BudgetError.categoryMustHaveName }
        if CategoryNames.containsIllegalCharacters(name) { throw BudgetError.categoryIllegalCharacters }
        let siblings = categoryGroups[location.group].categories
        if siblings.contains(where: { $0.id != id && $0.name.lowercased() == name.lowercased() }) {
            throw BudgetError.categoryNameUsed
        }
        categoryGroups[location.group].categories[location.category].name = name
    }

    /// As in Abakus, the successor takes over the references and the assignments; targets and snoozes go.
    mutating func deleteCategory(_ id: String, into successor: String) throws {
        let location = try categoryLocation(id)
        guard successor != id else { throw BudgetError.categoryNotFound(successor) }
        try requireBudgetCategory(successor)
        recategorize(id, as: successor)
        moveAssignments(of: id, to: successor)
        categoryGroups[location.group].categories.remove(at: location.category)
        successorIds[id] = successor
    }

    mutating func discardCategory(_ id: String) throws {
        let location = try categoryLocation(id)
        guard !refersToCategory(id) else { throw BudgetError.categoryInUse }
        categoryGroups[location.group].categories.remove(at: location.category)
    }

    mutating func deleteCategoryGroup(_ id: String) throws {
        let index = try groupIndex(id)
        guard categoryGroups[index].categories.isEmpty else { throw BudgetError.categoryGroupNotEmpty }
        categoryGroups.remove(at: index)
        collapsedCategoryGroupIds.remove(id)
    }

    private func refersToCategory(_ id: String) -> Bool {
        let lines =
            transactions.flatMap(\.subtransactions) + scheduledTransactions.flatMap(\.subtransactions)
            + matchProposals.flatMap(\.subtransactions)
        return transactions.contains { $0.categoryId == id } || scheduledTransactions.contains { $0.categoryId == id }
            || matchProposals.contains { $0.categoryId == id }
            || lines.contains { $0.categoryId == id } || payees.contains { $0.lastCategoryId == id }
            || assignments.contains { $0.categoryId == id } || targetVersions.contains { $0.categoryId == id }
            || targetSnoozes.contains { $0.categoryId == id }
    }

    private mutating func recategorize(_ id: String, as successor: String) {
        func replace(_ categoryId: inout String?) {
            if categoryId == id { categoryId = successor }
        }
        func replace(_ lines: inout [Subtransaction]) {
            for index in lines.indices { replace(&lines[index].categoryId) }
        }
        for index in transactions.indices {
            replace(&transactions[index].categoryId)
            replace(&transactions[index].subtransactions)
        }
        for index in scheduledTransactions.indices {
            replace(&scheduledTransactions[index].categoryId)
            replace(&scheduledTransactions[index].subtransactions)
        }
        for index in payees.indices { replace(&payees[index].lastCategoryId) }
    }

    private mutating func moveAssignments(of id: String, to successor: String) {
        let moved = assignments.filter { $0.categoryId == id }
        removeBudgetData(ofCategories: [id])
        for assignment in moved { addAssigned(assignment.amount, month: assignment.month, categoryId: successor) }
    }

    /// `index` is the drop position in the target's visible list, before the item is taken out.
    mutating func moveCategory(_ id: String, toGroup groupId: String, index: Int) throws {
        let from = try categoryLocation(id)
        let to = try groupIndex(groupId)
        let category = categoryGroups[from.group].categories[from.category]
        var order = categoryIds(ofGroup: to)
        if from.group == to {
            let current = order.firstIndex(of: id) ?? order.count
            order.remove(at: current)
            let position = Self.dropPosition(index, count: order.count + 1, current: current)
            order.insert(id, at: position)
            reorderCategories(ofGroup: to, order)
            return
        }
        let target = categoryGroups[to]
        if target.categories.contains(where: { $0.name.lowercased() == category.name.lowercased() }) {
            throw BudgetError.categoryNameTakenInGroup(group: target.name, name: category.name)
        }
        categoryGroups[from.group].categories.remove(at: from.category)
        var moved = category
        moved.categoryGroupId = groupId
        categoryGroups[to].categories.append(moved)
        order.insert(id, at: Self.dropPosition(index, count: order.count, current: nil))
        reorderCategories(ofGroup: to, order)
        reorderCategories(ofGroup: from.group, categoryIds(ofGroup: from.group))
    }

    mutating func moveCategoryGroup(_ id: String, index: Int) throws {
        _ = try groupIndex(id)
        var order = budgetCategoryGroups.map(\.id)
        let current = order.firstIndex(of: id) ?? order.count
        order.remove(at: current)
        order.insert(id, at: Self.dropPosition(index, count: order.count + 1, current: current))
        reorderGroups(order)
    }

    private static func dropPosition(_ index: Int, count: Int, current: Int?) -> Int {
        guard index >= 0, index <= count else { return current == nil ? count : count - 1 }
        if let current, current < index { return index - 1 }
        return index
    }

    public func isExpanded(_ group: CategoryGroup) -> Bool {
        !collapsedCategoryGroupIds.contains(group.id)
    }

    mutating func setCategoryGroupExpanded(_ id: String, _ expanded: Bool) throws {
        _ = try groupIndex(id)
        if expanded { collapsedCategoryGroupIds.remove(id) } else { collapsedCategoryGroupIds.insert(id) }
    }

    mutating func setAllCategoryGroupsExpanded(_ expanded: Bool) {
        collapsedCategoryGroupIds = expanded ? [] : Set(budgetCategoryGroups.map(\.id))
    }

    func groupIndex(_ id: String) throws -> Int {
        guard let index = categoryGroups.firstIndex(where: { $0.id == id && !$0.isInternal }) else {
            throw BudgetError.categoryNotFound(id)
        }
        return index
    }

    func categoryLocation(_ id: String) throws -> (group: Int, category: Int) {
        for (groupIndex, group) in categoryGroups.enumerated() where !group.isInternal {
            if let categoryIndex = group.categories.firstIndex(where: { $0.id == id }) {
                return (groupIndex, categoryIndex)
            }
        }
        throw BudgetError.categoryNotFound(id)
    }

    private func categoryIds(ofGroup index: Int) -> [String] {
        categoryGroups[index].categories.sortedByPosition().map(\.id)
    }

    mutating func appendCategory(_ category: Category) {
        guard let index = categoryGroups.firstIndex(where: { $0.id == category.categoryGroupId }) else { return }
        let order = categoryIds(ofGroup: index)
        categoryGroups[index].categories.append(category)
        reorderCategories(ofGroup: index, order + [category.id])
    }

    mutating func reorderGroups(_ order: [String]) {
        for (position, id) in order.enumerated() {
            if let index = categoryGroups.firstIndex(where: { $0.id == id }) {
                categoryGroups[index].position = position
            }
        }
    }

    private mutating func reorderCategories(ofGroup index: Int, _ order: [String]) {
        for (position, id) in order.enumerated() {
            if let categoryIndex = categoryGroups[index].categories.firstIndex(where: { $0.id == id }) {
                categoryGroups[index].categories[categoryIndex].position = position
            }
        }
    }
}
