import Foundation

public struct Category: Hashable, Identifiable, Sendable, Positioned {
    public var id: String
    public var categoryGroupId: String
    public var name: String
    /// Hidden categories still count.
    public var hidden: Bool
    public var isInternal: Bool
    public var position: Int
    public var note: String?

    public init(
        id: String = EntityID.createUID(),
        categoryGroupId: String,
        name: String,
        hidden: Bool = false,
        isInternal: Bool = false,
        position: Int = 0,
        note: String? = nil
    ) {
        self.id = id
        self.categoryGroupId = categoryGroupId
        self.name = name
        self.hidden = hidden
        self.isInternal = isInternal
        self.position = position
        self.note = note
    }
}

public struct CategoryGroup: Hashable, Identifiable, Sendable, Positioned {
    public var id: String
    public var name: String
    public var hidden: Bool
    public var isInternal: Bool
    public var position: Int
    public var note: String?
    public var categories: [Category]

    public init(
        id: String = EntityID.createUID(),
        name: String,
        hidden: Bool = false,
        isInternal: Bool = false,
        position: Int = 0,
        note: String? = nil,
        categories: [Category] = []
    ) {
        self.id = id
        self.name = name
        self.hidden = hidden
        self.isInternal = isInternal
        self.position = position
        self.note = note
        self.categories = categories
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
