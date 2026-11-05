import Foundation

public enum Calculator {
    static let signs: [Character: Decimal] = ["+": 1, "-": -1, "−": -1]
    /// As on the web, so that an amount always fits the cents stored as `Int`.
    static let maxIntegerDigits = 15

    /// Numbers joined by `+` and `−`, worked left to right, with an optional leading sign; nil for anything else.
    /// Each number is read as the web's `Abakus.Money` reads it.
    public static func evaluate(_ expression: String, formatter: BudgetFormatter) -> Decimal? {
        let locale = formatter.currencyLocale
        var text = BudgetFormatter.plainAmountText(expression).replacingOccurrences(of: locale.currencySymbol, with: "")
        text.removeAll { $0.isWhitespace }
        var total: Decimal = 0
        var sign: Decimal = 1
        var number = ""
        var index = text.startIndex
        if let first = text.first, let leading = signs[first] {
            sign = leading
            index = text.index(after: index)
        }
        func addNumber() -> Bool {
            guard let value = parseNumber(number, digits: locale.decimalDigits) else { return false }
            total += sign * value
            number = ""
            return true
        }
        while index < text.endIndex {
            let character = text[index]
            if let next = signs[character] {
                guard addNumber() else { return nil }
                sign = next
            } else {
                number.append(character)
            }
            index = text.index(after: index)
        }
        guard addNumber() else { return nil }
        return abs(total) < pow(10, maxIntegerDigits) ? total : nil
    }

    /// A comma or a dot as decimal separator, the other one as thousands separator; a single dot before exactly
    /// three digits groups thousands unless the currency has three decimals or only zeros precede it.
    private static func parseNumber(_ text: String, digits: Int) -> Decimal? {
        guard text.contains(where: \.isASCIIDigit),
            text.allSatisfy({ $0.isASCIIDigit || $0 == "." || $0 == "," }),
            let (whole, fraction) = separate(text, dotGroupsThousands: digits < 3)
        else { return nil }
        var places = fraction
        while places.count > digits, places.last == "0" { places.removeLast() }
        guard places.count <= digits, whole.count <= maxIntegerDigits else { return nil }
        let posix = Locale(identifier: "en_US_POSIX")
        return Decimal(string: (whole.isEmpty ? "0" : whole) + "." + places + "0", locale: posix)
    }

    private static func separate(_ text: String, dotGroupsThousands: Bool) -> (whole: String, fraction: String)? {
        let dots = text.count { $0 == "." }
        let commas = text.count { $0 == "," }
        guard let last = text.lastIndex(where: { $0 == "." || $0 == "," }) else { return (text, "") }
        let before = text[..<last]
        let after = String(text[text.index(after: last)...])
        if dots > 0, commas > 0 {
            let isDot = text[last] == "."
            guard (isDot ? dots : commas) == 1, let whole = ungroup(before, by: isDot ? "," : ".") else { return nil }
            return (whole, after)
        }
        if dots + commas > 1 {
            return ungroup(text[...], by: commas > 0 ? "," : ".").map { ($0, "") }
        }
        if text[last] == ".", after.count == 3, dotGroupsThousands, before.contains(where: { $0 != "0" }) {
            return ungroup(text[...], by: ".").map { ($0, "") }
        }
        return (String(before), after)
    }

    private static func ungroup(_ whole: Substring, by separator: Character) -> String? {
        let groups = whole.split(separator: separator, omittingEmptySubsequences: false)
        guard let first = groups.first, (1...3).contains(first.count), groups.dropFirst().allSatisfy({ $0.count == 3 })
        else { return nil }
        let digits = groups.joined()
        return digits.allSatisfy(\.isASCIIDigit) ? String(digits) : nil
    }
}
