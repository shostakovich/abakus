import AbakusCore
import Foundation

public struct BudgetSubRowDisplay: Hashable, Sendable {
    public let assigned: String
    public let outflows: String
    public let balance: String
    public let isBalanceNegative: Bool
    public let isBalanceDimmed: Bool
    public let isOverspent: Bool
    public let hasTransactions: Bool
    public let marker: BudgetAvailableMarker?
}

public struct BudgetMasterRowDisplay: Hashable, Sendable {
    public let assigned: String?
    public let outflows: String
    public let balance: String
    public let isBalanceNegative: Bool
    public let isBalanceDimmed: Bool
    public let hasTransactions: Bool
}

public enum BudgetAvailableTint: Hashable, Sendable {
    case neutral, balanced, negative
}

/// An amount whose trailing currency symbol hangs past the digit edge.
public struct BudgetTotal: Hashable, Sendable {
    public let digits: String
    public let suffix: String

    public var text: String { digits + suffix }
}

public struct BudgetMonthHeaderDisplay: Hashable, Sendable {
    public let available: String
    public let availableTint: BudgetAvailableTint
    public let totals: [BudgetTotal]
}

extension BudgetViewModel {
    var zeroText: String { formatter.currencyNoSymbol(0) }

    public func subRowDisplay(_ categoryId: String, in month: BudgetMonth) -> BudgetSubRowDisplay {
        let figures = month.category(categoryId)
        let balance = figures?.balance ?? 0
        let showsBalance = figures?.showsBalance ?? false
        return BudgetSubRowDisplay(
            assigned: figures?.showsAssigned == true ? formatter.currencyNoSymbol(figures?.assigned ?? 0) : "",
            outflows: figures?.showsOutflows == true ? outflowsText(figures?.outflows ?? 0) : "",
            balance: showsBalance ? formatter.currencyNoSymbol(balance) : "",
            isBalanceNegative: balance < 0, isBalanceDimmed: showsBalance && balance == 0,
            isOverspent: showsBalance && balance < 0, hasTransactions: figures?.hasTransactions ?? false,
            marker: figures?.availableMarker(isBeingBudgeted: month.isBeingBudgeted))
    }

    public func masterRowDisplay(_ row: BudgetCategoryRow, in month: BudgetMonth) -> BudgetMasterRowDisplay {
        let figures = month.master(row.id)
        let balance = figures?.balance ?? 0
        return BudgetMasterRowDisplay(
            assigned: row.kind == .uncategorized ? nil : formatter.currencyNoSymbol(figures?.assigned ?? 0),
            outflows: outflowsText(figures?.outflows ?? 0), balance: formatter.currencyNoSymbol(balance),
            isBalanceNegative: balance < 0, isBalanceDimmed: balance == 0,
            hasTransactions: figures?.hasTransactions ?? false)
    }

    public func headerDisplay(_ month: BudgetMonth) -> BudgetMonthHeaderDisplay {
        let available = Amount.round(month.available, digits: formatter.currencyLocale.decimalDigits)
        let tint: BudgetAvailableTint = available < 0 ? .negative : (available == 0 ? .balanced : .neutral)
        return BudgetMonthHeaderDisplay(
            available: formatter.currency(month.available), availableTint: tint,
            totals: [month.assigned, month.outflows, month.balance].map(total))
    }

    private func total(_ amount: Decimal) -> BudgetTotal {
        let locale = formatter.currencyLocale
        return locale.symbolOnLeft
            ? BudgetTotal(digits: formatter.currency(amount), suffix: "")
            : BudgetTotal(digits: formatter.currencyNoSymbol(amount), suffix: locale.currencySymbol)
    }

    private func outflowsText(_ outflows: Decimal) -> String {
        formatter.budgetAmount(outflows, prefix: "+", prefixZero: false)
    }
}
