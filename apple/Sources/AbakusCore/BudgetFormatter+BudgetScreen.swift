import Foundation

extension BudgetFormatter {
    public func shortMonthName(_ month: Int) -> String {
        dateLocale.shortMonthNames[(month - 1 + 12) % 12]
    }

    public func monthAndShortYear(_ date: DateWithoutTime) -> String {
        "\(monthName(date.month)) '\(String(format: "%02d", date.year % 100))"
    }

    /// Negative values keep their own "-", zero takes the prefix with `prefixZero`.
    public func budgetAmount(_ value: Decimal, prefix: String = "", prefixZero: Bool = true) -> String {
        let rounded = Amount.round(value, digits: currencyLocale.decimalDigits)
        let text = currencyNoSymbol(rounded)
        return rounded < 0 || (rounded == 0 && !prefixZero) ? text : prefix + text
    }

    /// A typed assigned amount: empty text is zero; text that does not parse, or is too large for `Decimal`, is nil.
    public func parseBudgetAmount(_ text: String) -> Decimal? {
        var prepared = text
        if let range = prepared.range(of: currencyLocale.currencySymbol) { prepared.removeSubrange(range) }
        prepared = prepared.replacingOccurrences(of: " ", with: "")
        if prepared.isEmpty { return 0 }
        guard
            let number = Self.parseNumberString(
                prepared, decimalSeparator: currencyLocale.decimalSeparator,
                thousandsSeparator: currencyLocale.groupSeparator)
        else { return nil }
        if number.isEmpty { return 0 }
        guard let value = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let rounded = Amount.round(value, digits: currencyLocale.decimalDigits)
        return rounded.isFinite ? rounded : nil
    }
}

public struct BudgetHeaderLine: Hashable, Sendable {
    public let amount: String
    public let text: String
    public var isWarning = false
}

extension BudgetMonth {
    public func headerLines(formatter: BudgetFormatter) -> [BudgetHeaderLine] {
        let previous = formatter.shortMonthName(month.addingMonths(-1).month)
        let this = formatter.shortMonthName(month.month)
        let assignedAmount = formatter.budgetAmount(-assigned, prefix: "+", prefixZero: false)
        var lines = [
            BudgetHeaderLine(
                amount: formatter.budgetAmount(previousMonthAvailable), text: "Nicht verteilt im " + previous,
                isWarning: previousMonthAvailable < 0),
            BudgetHeaderLine(
                amount: formatter.budgetAmount(previousMonthOverspent), text: "Überzogen im " + previous,
                isWarning: previousMonthOverspent < 0),
            BudgetHeaderLine(
                amount: formatter.budgetAmount(income, prefix: "+", prefixZero: false), text: "Einnahmen im " + this),
            BudgetHeaderLine(amount: assignedAmount, text: "Zugewiesen im " + this),
        ]
        if !isClosed && assignedInFuture != 0 {
            lines.append(
                BudgetHeaderLine(
                    amount: formatter.budgetAmount(-assignedInFuture, prefix: "+"), text: "Für spätere Monate"))
        }
        for shortfall in uncovered {
            let later = shortfall.month
            let name = formatter.shortMonthName(later.month) + (later.year == month.year ? "" : " \(later.year)")
            lines.append(
                BudgetHeaderLine(
                    amount: formatter.budgetAmount(-shortfall.amount), text: "Nicht gedeckt im " + name,
                    isWarning: true))
        }
        return lines
    }
}
