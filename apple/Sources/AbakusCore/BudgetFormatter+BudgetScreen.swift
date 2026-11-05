import Foundation

extension BudgetFormatter {
    public func shortMonthName(_ month: Int) -> String {
        dateLocale.shortMonthNames[(month - 1 + 12) % 12]
    }

    public func monthAndShortYear(_ date: DateWithoutTime) -> String {
        "\(monthName(date.month)) '\(String(format: "%02d", date.year % 100))"
    }

    /// Negative values keep their own minus, zero takes the prefix with `prefixZero`.
    public func budgetAmount(
        _ value: Decimal, prefix: String = "", prefixZero: Bool = true, withUnit: Bool = false
    ) -> String {
        let rounded = Amount.round(value, digits: currencyLocale.decimalDigits)
        let text = withUnit ? currency(rounded) : currencyNoSymbol(rounded)
        return rounded < 0 || (rounded == 0 && !prefixZero) ? text : prefix + text
    }
}

public struct BudgetHeaderLine: Hashable, Sendable {
    public let amount: String
    public let text: String
    public var isWarning = false
}

extension BudgetMonth {
    public func headerLines(formatter: BudgetFormatter, withUnit: Bool = false) -> [BudgetHeaderLine] {
        let previous = formatter.shortMonthName(month.addingMonths(-1).month)
        let this = formatter.shortMonthName(month.month)
        func amount(_ value: Decimal, prefix: String = "", prefixZero: Bool = true) -> String {
            formatter.budgetAmount(value, prefix: prefix, prefixZero: prefixZero, withUnit: withUnit)
        }
        let assignedAmount = amount(-assigned, prefix: "+", prefixZero: false)
        var lines = [
            BudgetHeaderLine(
                amount: amount(previousMonthAvailable), text: "Nicht verteilt im " + previous,
                isWarning: previousMonthAvailable < 0),
            BudgetHeaderLine(
                amount: amount(previousMonthOverspent), text: "Überzogen im " + previous,
                isWarning: previousMonthOverspent < 0),
            BudgetHeaderLine(
                amount: amount(income, prefix: "+", prefixZero: false), text: "Einnahmen im " + this),
            BudgetHeaderLine(amount: assignedAmount, text: "Zugewiesen im " + this),
        ]
        if !isClosed && assignedInFuture != 0 {
            lines.append(
                BudgetHeaderLine(
                    amount: amount(-assignedInFuture, prefix: "+"), text: "Für spätere Monate"))
        }
        for shortfall in uncovered {
            let later = shortfall.month
            let name = formatter.shortMonthName(later.month) + (later.year == month.year ? "" : " \(later.year)")
            lines.append(
                BudgetHeaderLine(
                    amount: amount(-shortfall.amount), text: "Nicht gedeckt im " + name,
                    isWarning: true))
        }
        return lines
    }
}
