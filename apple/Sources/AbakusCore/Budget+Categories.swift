import Foundation

public enum CategoryNames {
    public static let addNewCategory = "Neue Kategorie …"

    /// No colon means the whole text names the master.
    public static func components(_ text: String) -> (master: String, sub: String) {
        guard !text.isEmpty else { return ("", "") }
        let parts = text.components(separatedBy: ":")
        switch parts.count {
        case 1: return (text, "")
        case 2:
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
        default: return ("", "")
        }
    }

    public static func containsIllegalCharacters(_ name: String) -> Bool {
        name.contains(":") || name.contains("`")
    }

    public static func isIncomeGroupName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespaces).lowercased() == DefaultCategories.incomeGroupName.lowercased()
    }

    public static func isReservedGroupName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        if isIncomeGroupName(name) { return true }
        let reserved = [
            "__Internal__", "__SupplementalIncome__", "__PrimaryIncome__", "__Split__", addNewCategory,
        ]
        return reserved.contains { $0.lowercased() == name.lowercased() }
    }
}

extension Budget {
    public var budgetCategoryGroups: [CategoryGroup] {
        categoryGroups.filter { !$0.isInternal }.sortedByPosition().map { master in
            var sorted = master
            sorted.categories = master.categories.sortedByPosition()
            return sorted
        }
    }

    public var incomeGroupListing: CategoryGroup {
        let groupId = EntityID.incomeMasterCategory
        return CategoryGroup(
            id: groupId, name: DefaultCategories.incomeGroupName,
            categories: [
                Category(
                    id: readyToAssignCategoryId, categoryGroupId: groupId, name: DefaultCategories.readyToAssignName)
            ])
    }

    public func category(fullName: String) -> Category? {
        guard let colon = fullName.firstIndex(of: ":") else { return nil }
        let masterName = fullName[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let subName = fullName[fullName.index(after: colon)...].trimmingCharacters(in: .whitespaces).lowercased()
        for master in budgetCategoryGroups where master.name.lowercased() == masterName {
            if let sub = master.categories.first(where: { $0.name.lowercased() == subName }) { return sub }
        }
        return nil
    }

    public func category(named name: String) -> Category? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        for master in budgetCategoryGroups {
            if let sub = master.categories.first(where: { $0.name.lowercased() == wanted }) { return sub }
        }
        return nil
    }

    public func incomeCategory(label: String) -> String? {
        let wanted = label.trimmingCharacters(in: .whitespaces).lowercased()
        return wanted == DefaultCategories.readyToAssignName.lowercased() ? readyToAssignCategoryId : nil
    }

    mutating func addNamedCategory(groupName: String, name: String) throws {
        let group = groupName.trimmingCharacters(in: .whitespaces)
        let category = name.trimmingCharacters(in: .whitespaces)
        guard !group.isEmpty, !category.isEmpty else { throw BudgetError.categoryNameMissing }
        if CategoryNames.containsIllegalCharacters(group) { throw BudgetError.categoryIllegalCharacters }
        if CategoryNames.isIncomeGroupName(group) { throw BudgetError.categoryCantBeIncome }
        if CategoryNames.isReservedGroupName(group) { throw BudgetError.categoryIsReserved }
        if CategoryNames.containsIllegalCharacters(category) { throw BudgetError.categoryIllegalCharacters }
        let existing = budgetCategoryGroups.first { $0.name.lowercased() == group.lowercased() }
        if let existing, existing.categories.contains(where: { $0.name.lowercased() == category.lowercased() }) {
            throw BudgetError.duplicateCategoryName
        }
        let groupId: String
        if let existing {
            groupId = existing.id
        } else {
            let new = CategoryGroup(name: group)
            categoryGroups.append(new)
            reorderGroups(budgetCategoryGroups.map(\.id).filter { $0 != new.id } + [new.id])
            groupId = new.id
        }
        appendCategory(Category(categoryGroupId: groupId, name: category))
    }
}
