import Foundation

/// The register's views: a view filters first, the search narrows what it shows.
public enum RegisterFilter: String, CaseIterable, Hashable, Sendable {
    case all, unapproved, uncleared, needsCategory

    public var title: String {
        switch self {
        case .all: "Alle Buchungen"
        case .unapproved: "Zu bestätigen"
        case .uncleared: "Vorgemerkt"
        case .needsCategory: "Ohne Kategorie"
        }
    }

    /// Each view is a rule of its own, so an import without a category is in Zu bestätigen and Ohne Kategorie.
    public func includes(_ transaction: Transaction, in lookup: BudgetLookup) -> Bool {
        switch self {
        case .all: true
        case .unapproved: !transaction.approved
        case .uncleared: transaction.cleared == .uncleared
        case .needsCategory: lookup.needsCategory(transaction)
        }
    }
}

/// The web's full-text search: payee, category and memo of a transaction and its parts, and its amount as written
/// without sign („48,75“), all by lookup key.
public struct RegisterSearch: Hashable, Sendable {
    public enum Hit: Hashable, Sendable {
        case transaction, part
    }

    public let key: String

    public init(_ text: String) {
        key = text.lookupKey
    }

    public var isEmpty: Bool { key.isEmpty }

    /// `.part` when only a split's part matches, so the split opens to show it.
    public func hit(_ transaction: Transaction, lookup: BudgetLookup, formatter: BudgetFormatter) -> Hit? {
        guard !isEmpty else { return .transaction }
        let amount = formatter.currencyNoSymbol(transaction.amount < 0 ? -transaction.amount : transaction.amount)
        let own = [
            lookup.payeeName(of: transaction), transaction.isSplit ? "" : Self.category(transaction.categoryId, lookup),
            transaction.memo ?? "",
        ]
        if amount.lookupKey.contains(key) || own.contains(where: contains) { return .transaction }
        let parts = transaction.subtransactions.flatMap {
            [lookup.payeeName(of: $0), Self.category($0.categoryId, lookup), $0.memo ?? ""]
        }
        return parts.contains(where: contains) ? .part : nil
    }

    private func contains(_ text: String) -> Bool {
        !text.isEmpty && text.lookupKey.contains(key)
    }

    private static func category(_ categoryId: String?, _ lookup: BudgetLookup) -> String {
        guard let categoryId, EntityID.isCategorized(categoryId) else { return "" }
        if lookup.budget.isReadyToAssign(categoryId) { return DefaultCategories.readyToAssignName }
        return lookup.categoryName(categoryId)
    }
}

extension Transaction {
    public var needsApproval: Bool {
        !approved && source != .manual
    }
}
