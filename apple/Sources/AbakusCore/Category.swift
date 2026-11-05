import Foundation

public struct Category: Hashable, Identifiable, Sendable, Positioned {
    public var id: String
    public var categoryGroupId: String
    public var name: String
    public var isInternal: Bool
    public var position: Int

    public init(
        id: String = EntityID.createUID(),
        categoryGroupId: String,
        name: String,
        isInternal: Bool = false,
        position: Int = 0
    ) {
        self.id = id
        self.categoryGroupId = categoryGroupId
        self.name = name
        self.isInternal = isInternal
        self.position = position
    }
}

public struct CategoryGroup: Hashable, Identifiable, Sendable, Positioned {
    public var id: String
    public var name: String
    public var isInternal: Bool
    public var position: Int
    public var categories: [Category]

    public init(
        id: String = EntityID.createUID(),
        name: String,
        isInternal: Bool = false,
        position: Int = 0,
        categories: [Category] = []
    ) {
        self.id = id
        self.name = name
        self.isInternal = isInternal
        self.position = position
        self.categories = categories
    }

    /// The server merges the categories of a group that share a lookup key.
    public func holdsAnother(namedLike category: Category) -> Bool {
        let key = category.name.lookupKey
        return categories.contains { $0.id != category.id && $0.name.lookupKey == key }
    }
}

public enum DefaultCategories {
    public static let splitCategoryName = "Aufteilung"
    public static let readyToAssignName = "Zu verteilen"
    public static let incomeGroupName = "Einnahmen"
    public static let uncategorizedName = "Nicht kategorisiert"
    /// The names as Abakus stores them, not as it shows them.
    static let internalGroupName = "Internal Master Category"
    static let readyToAssignStoredName = "Inflow: Ready to Assign"

    public static let personal: [(master: String, subs: [String])] = [
        ("Giving", ["Tithing", "Charitable"]),
        (
            "Monthly Bills",
            ["Rent/Mortgage", "Phone", "Internet", "Cable TV", "Electricity", "Water", "Natural Gas/Propane/Oil"]
        ),
        (
            "Everyday Expenses",
            ["Groceries", "Fuel", "Spending Money", "Restaurants", "Medical", "Clothing", "Household Goods"]
        ),
        (
            "Rainy Day Funds",
            [
                "Emergency Fund", "Car Repairs", "Home Maintenance", "Car Insurance", "Life Insurance",
                "Health Insurance", "Birthdays", "Christmas",
            ]
        ),
        ("Savings Goals", ["Car Replacement", "Vacation"]),
        ("Debt", ["Car Payment", "Student Loan Payment", "Personal Loan Payment"]),
    ]

    public static let business: [(master: String, subs: [String])] = [
        ("Marketing", ["Printing", "Online", "Referral Fees", "Commissions"]),
        ("Services", ["Accounting", "Legal", "Contractors", "Other"]),
        ("Office", ["Rent", "Telephone/Fax", "Internet"]),
        ("General", ["Meals & Entertainment", "Office Supplies"]),
        ("Travel", ["Automobile", "Hotels/Lodging", "Airfare", "Other"]),
        ("Taxes & Licenses", ["Unemployment", "Payroll", "Quarterlies"]),
    ]

    public static func categoryGroups(
        for type: BudgetType, makeID: () -> String = { EntityID.createUID() }
    ) -> [CategoryGroup] {
        categoryGroups(type == .personal ? personal : business, makeID: makeID)
    }

    public static func categoryGroups(
        _ list: [(master: String, subs: [String])], makeID: () -> String = { EntityID.createUID() }
    ) -> [CategoryGroup] {
        let groups = list.enumerated().map { index, entry in
            let groupId = makeID()
            let categories = entry.subs.enumerated().map { position, name in
                Category(id: makeID(), categoryGroupId: groupId, name: name, position: position)
            }
            return CategoryGroup(id: groupId, name: entry.master, position: index, categories: categories)
        }
        return [internalGroup(id: makeID(), readyToAssignId: makeID())] + groups
    }

    public static func internalGroup(
        id: String = EntityID.createUID(), readyToAssignId: String = EntityID.createUID()
    ) -> CategoryGroup {
        CategoryGroup(
            id: id, name: internalGroupName, isInternal: true,
            categories: [
                Category(id: readyToAssignId, categoryGroupId: id, name: readyToAssignStoredName, isInternal: true)
            ])
    }
}
