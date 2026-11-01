import AbakusCore
import Foundation

public struct RegisterSortOrder: Hashable, Sendable {
    public var column: RegisterColumn
    public var ascending: Bool

    public static let `default` = RegisterSortOrder(column: .date, ascending: false)

    public init(column: RegisterColumn, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }

    public func clicked(_ column: RegisterColumn) -> RegisterSortOrder {
        guard column.isSortable else { return self }
        return column == self.column
            ? RegisterSortOrder(column: column, ascending: !ascending)
            : RegisterSortOrder(column: column, ascending: true)
    }
}

/// The chosen key, then the default keys.
struct RegisterSortKeys {
    var accountName: String
    var keys: DefaultOrderKeys
    var frequency = 0

    func compare(_ other: RegisterSortKeys, by column: RegisterColumn) -> ComparisonResult {
        let (lhs, rhs) = (keys, other.keys)
        return switch column {
        case .account: accountName.localizedStandardCompare(other.accountName)
        case .date: Self.order(lhs.date, rhs.date)
        case .payee: lhs.payee.localizedStandardCompare(rhs.payee)
        case .category: lhs.category.localizedStandardCompare(rhs.category)
        case .memo: lhs.memo.localizedStandardCompare(rhs.memo)
        case .outflow, .inflow: Self.order(rhs.amount, lhs.amount)
        case .cleared: Self.order(rhs.cleared.integerValue, lhs.cleared.integerValue)
        case .frequency: Self.order(frequency, other.frequency)
        case .runningBalance: .orderedSame
        }
    }

    func precedes(_ other: RegisterSortKeys, order: RegisterSortOrder) -> Bool {
        var result = compare(other, by: order.column)
        if result == .orderedSame { result = keys.compare(other.keys) }
        return order.ascending ? result == .orderedAscending : result == .orderedDescending
    }

    private static func order<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }
}

enum RegisterSorter {
    static func sorted(_ transactions: [Transaction], by order: RegisterSortOrder, lookup: BudgetLookup)
        -> [Transaction]
    {
        let keyed = transactions.map { transaction in
            (
                transaction,
                RegisterSortKeys(
                    accountName: lookup.account(withId: transaction.accountId)?.name ?? "",
                    keys: lookup.defaultOrderKeys(of: transaction))
            )
        }
        return keyed.sorted { $0.1.precedes($1.1, order: order) }.map(\.0)
    }
}
