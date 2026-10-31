import Foundation

public struct Assignment: Hashable, Identifiable, Sendable {
    public var id: String
    public var categoryId: String
    public var month: DateWithoutTime
    public var amount: Decimal

    public init(categoryId: String, month: DateWithoutTime, amount: Decimal) {
        self.init(
            id: EntityID.assignment(categoryId: categoryId, month: month), categoryId: categoryId, month: month,
            amount: amount)
    }

    /// One of a deleted category counts for its successor under its own id.
    init(id: String, categoryId: String, month: DateWithoutTime, amount: Decimal) {
        self.id = id
        self.categoryId = categoryId
        self.month = month.firstOfMonth
        self.amount = Amount.round(amount)
    }
}

public struct TargetSnooze: Hashable, Identifiable, Sendable {
    public var id: String
    public var categoryId: String
    public var month: DateWithoutTime

    public init(categoryId: String, month: DateWithoutTime) {
        id = EntityID.targetSnooze(categoryId: categoryId, month: month)
        self.categoryId = categoryId
        self.month = month.firstOfMonth
    }
}
