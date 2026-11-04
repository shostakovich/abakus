import AbakusCore
import Foundation
import SwiftUI

public struct BudgetSubRowDisplay: Hashable, Sendable {
    public let assigned: String
    public let outflows: String
    public let balance: String
    public let isBalanceNegative: Bool
    public let isBalanceZero: Bool
    public let hasTransactions: Bool
    public let marker: BudgetAvailableMarker?
    /// The ring of an underfunded target.
    public let fundedPercent: Int?
    public let targetBar: BudgetTargetBar?
    public let accessibilityValue: String
    /// The mark beside a target bar, which agrees with the bar's colour.
    public let barMarker: BudgetAvailableMarker?
    public let barAccessibilityValue: String
}

public enum BudgetTargetBarState: Hashable, Sendable {
    case underfunded, funded, snoozed, overspent, idle
}

public struct BudgetTargetBar: Hashable, Sendable {
    public let share: Double
    public let state: BudgetTargetBarState
}

public struct BudgetMasterRowDisplay: Hashable, Sendable {
    public let assigned: String
    public let outflows: String
    public let balance: String
    public let isBalanceNegative: Bool
    public let hasTransactions: Bool
}

public enum BudgetAvailableTint: Hashable, Sendable {
    case neutral, positive, negative, muted

    public var color: Color {
        switch self {
        case .neutral: ThemeColor.text
        case .positive: ThemeColor.positive
        case .negative: ThemeColor.negative
        case .muted: ThemeColor.secondaryText
        }
    }
}

/// An amount whose trailing currency symbol hangs past the digit edge.
public struct BudgetTotal: Hashable, Sendable {
    public let digits: String
    public let suffix: String

    public var text: String { suffix.isEmpty ? digits : digits + BudgetFormatter.unitSpace + suffix }
}

public struct BudgetMonthHeaderDisplay: Hashable, Sendable {
    public let title: String
    public let available: String
    public let availableTint: BudgetAvailableTint
    public let totals: [BudgetTotal]
    public let isPast: Bool
}

extension BudgetViewModel {
    package var zeroText: String { formatter.currencyNoSymbol(0) }

    public func subRowDisplay(_ categoryId: String, in month: BudgetMonth) -> BudgetSubRowDisplay {
        let figures = month.category(categoryId)
        let balance = figures?.balance ?? 0
        let marker = figures?.availableMarker(isBeingBudgeted: month.isBeingBudgeted)
        let fundedPercent = marker == .underfunded ? figures?.target?.fundedPercent : nil
        let balanceText = isZero(balance) ? zeroText : formatter.currencyNoSymbol(balance)
        let bar = figures.flatMap { targetBar($0, in: month) }
        let barMarker = bar?.state == .funded ? .funded : marker
        func accessibilityValue(_ marker: BudgetAvailableMarker?) -> String {
            guard let marker else { return balanceText }
            let percent = marker == .underfunded ? fundedPercent : nil
            let label = percent.map { "\(marker.label), \($0) % finanziert" } ?? marker.label
            return "\(balanceText), \(label)"
        }
        return BudgetSubRowDisplay(
            assigned: figure(figures?.assigned ?? 0), outflows: outflowsText(figures?.outflows ?? 0),
            balance: balanceText, isBalanceNegative: balance < 0, isBalanceZero: isZero(balance),
            hasTransactions: figures?.hasTransactions ?? false, marker: marker, fundedPercent: fundedPercent,
            targetBar: bar, accessibilityValue: accessibilityValue(marker), barMarker: barMarker,
            barAccessibilityValue: accessibilityValue(barMarker))
    }

    public func masterRowDisplay(_ row: BudgetCategoryRow, in month: BudgetMonth) -> BudgetMasterRowDisplay {
        let figures = month.master(row.id)
        let balance = figures?.balance ?? 0
        return BudgetMasterRowDisplay(
            assigned: row.kind == .uncategorized ? "" : figure(figures?.assigned ?? 0),
            outflows: outflowsText(figures?.outflows ?? 0), balance: figure(balance), isBalanceNegative: balance < 0,
            hasTransactions: figures?.hasTransactions ?? false)
    }

    public func headerDisplay(_ month: BudgetMonth) -> BudgetMonthHeaderDisplay {
        let available = Amount.round(month.available, digits: formatter.currencyLocale.decimalDigits)
        return BudgetMonthHeaderDisplay(
            title: formatter.monthName(month.month.month) + " " + String(month.month.year),
            available: formatter.currency(month.available), availableTint: tint(available, isPast: month.isClosed),
            totals: [month.assigned, month.outflows, month.balance].map(total), isPast: month.isClosed)
    }

    /// Amber only while the month is being budgeted, as the ring; a closed month stays grey.
    private func targetBar(_ figures: BudgetCategoryFigures, in month: BudgetMonth) -> BudgetTargetBar? {
        guard let target = figures.target else { return nil }
        let state: BudgetTargetBarState =
            if figures.isOverspent {
                .overspent
            } else if month.isClosed {
                .idle
            } else if target.isSnoozed {
                .snoozed
            } else if target.openNeed > 0 {
                month.isBeingBudgeted ? .underfunded : .idle
            } else {
                .funded
            }
        return BudgetTargetBar(share: assignedShare(target), state: state)
    }

    /// In whole percent rounded down, as the ring; a snoozed target still shows what it would ask.
    private func assignedShare(_ target: BudgetTargetFigures) -> Double {
        guard target.needed > 0, target.underfunded > 0 else { return 1 }
        var share = 100 * (target.needed - target.underfunded) / target.needed
        var percent = Decimal()
        NSDecimalRound(&percent, &share, 0, .down)
        return min(max(NSDecimalNumber(decimal: percent).doubleValue / 100, 0), 1)
    }

    private func tint(_ available: Decimal, isPast: Bool) -> BudgetAvailableTint {
        if available < 0 { return .negative }
        if isPast { return .muted }
        return available > 0 ? .positive : .neutral
    }

    private func total(_ amount: Decimal) -> BudgetTotal {
        let locale = formatter.currencyLocale
        return locale.symbolOnLeft
            ? BudgetTotal(digits: formatter.currency(amount), suffix: "")
            : BudgetTotal(digits: formatter.currencyNoSymbol(amount), suffix: locale.currencySymbol)
    }

    private func isZero(_ amount: Decimal) -> Bool {
        Amount.round(amount, digits: formatter.currencyLocale.decimalDigits) == 0
    }

    private func figure(_ amount: Decimal) -> String {
        isZero(amount) ? "" : formatter.currencyNoSymbol(amount)
    }

    private func outflowsText(_ outflows: Decimal) -> String {
        isZero(outflows) ? "" : formatter.budgetAmount(outflows, prefix: "+")
    }
}
