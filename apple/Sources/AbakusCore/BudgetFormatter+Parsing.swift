import Foundation

extension BudgetFormatter {
    /// The pattern named in the "Ungültiges Datum" callout.
    public var shortDatePattern: String {
        let parts =
            switch dateLocale.dateSequence {
            case .dmy: ["TT", "MM", "JJ"]
            case .mdy: ["MM", "TT", "JJ"]
            case .ymd: ["JJ", "MM", "TT"]
            }
        return parts.joined(separator: dateLocale.dateSeparator)
    }

    public func parseDate(_ text: String, today: DateWithoutTime) -> DateWithoutTime? {
        guard !text.isEmpty else { return nil }
        var normalized = text
        for separator in [".", "-", "'", dateLocale.dateSeparator] where !separator.isEmpty {
            normalized = normalized.replacingOccurrences(of: separator, with: "/")
        }
        let first: String
        let second: String
        let third: String
        if normalized.contains("/") {
            let parts = normalized.split(separator: "/", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 2 else { return nil }
            first = parts[0]
            second = parts[1]
            var year = parts.count > 2 ? parts[2] : ""
            if let space = year.firstIndex(of: " "), space > year.startIndex { year = String(year[..<space]) }
            third = year
        } else {
            guard normalized.allSatisfy(\.isASCIIDigit) else { return nil }
            let characters = Array(normalized)
            func slice(_ start: Int, _ length: Int) -> String { String(characters[start..<start + length]) }
            switch (characters.count, dateLocale.dateSequence) {
            case (6, _): (first, second, third) = (slice(0, 2), slice(2, 2), slice(4, 2))
            case (8, .ymd): (first, second, third) = (slice(0, 4), slice(4, 2), slice(6, 2))
            case (8, _): (first, second, third) = (slice(0, 2), slice(2, 2), slice(4, 4))
            default: return nil
            }
        }
        let (dayText, monthText, yearText): (String, String, String) =
            switch dateLocale.dateSequence {
            case .mdy: (second, first, third)
            case .dmy: (first, second, third)
            case .ymd: (third, second, first)
            }
        guard [dayText, monthText, yearText].allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        let day = dayText.isEmpty ? 1 : Int(dayText) ?? -1
        let month = monthText.isEmpty ? 1 : Int(monthText) ?? -1
        guard let typedYear = yearText.isEmpty ? today.year : Int(yearText) else { return nil }
        let year = DateWithoutTime.year(fromTwoDigits: typedYear)
        guard (1...12).contains(month), (0...31).contains(day), DateWithoutTime.supportedYears.contains(year) else {
            return nil
        }
        return DateWithoutTime(year: year, month: month, day: day)
    }

    /// Text without a number is zero.
    public func parseAmount(_ text: String) -> Decimal {
        Amount.round(parseAmountUnrounded(text), digits: currencyLocale.decimalDigits)
    }

    public func parseAmountUnrounded(_ text: String) -> Decimal {
        var prepared = text
        if let range = prepared.range(of: currencyLocale.currencySymbol) { prepared.removeSubrange(range) }
        prepared = prepared.replacingOccurrences(of: " ", with: "")
        guard
            let number = Self.parseNumberString(
                prepared, decimalSeparator: currencyLocale.decimalSeparator,
                thousandsSeparator: currencyLocale.groupSeparator)
        else { return 0 }
        return Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// A typed balance, or nil when the text is not a number.
    public func parseBalance(_ text: String) -> Decimal? {
        var body = text.replacingOccurrences(of: " ", with: "")
        if let range = body.range(of: currencyLocale.currencySymbol) { body.removeSubrange(range) }
        if body.hasPrefix("-") || body.hasPrefix("+") { body.removeFirst() }
        body = body.replacingOccurrences(of: currencyLocale.groupSeparator, with: "")
        let parts = body.components(separatedBy: currencyLocale.decimalSeparator)
        guard parts.count <= 2, body.contains(where: \.isASCIIDigit),
            parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) })
        else { return nil }
        return parseAmount(text)
    }

    /// The last `.` or `,` is the decimal point.
    public func parseAmountWithUnknownDecimalSeparator(_ text: String) -> Decimal {
        let decimal = currencyLocale.decimalSeparator
        var unified = text.replacingOccurrences(of: ".", with: decimal).replacingOccurrences(of: ",", with: decimal)
        if let first = unified.range(of: decimal), let last = unified.range(of: decimal, options: .backwards),
            first != last
        {
            let head = unified[..<last.lowerBound].replacingOccurrences(of: decimal, with: "")
            unified = head + unified[last.lowerBound...]
        }
        return parseAmount(unified)
    }

    /// The last run of digits and separators wins.
    static func parseNumberString(_ text: String, decimalSeparator: String, thousandsSeparator: String) -> String? {
        let characters = Array(text).map(String.init)
        guard text.components(separatedBy: decimalSeparator).count <= 2 else { return nil }
        var number: String?
        var isNegative = false
        var index = 0
        while index < characters.count {
            let letter = characters[index]
            index += 1
            guard letter.first?.isASCIIDigit == true || letter == decimalSeparator else { continue }
            if (index >= 2 && characters[index - 2] == "-") || characters.first == "-" { isNegative = true }
            var collected = ""
            index -= 1
            while index < characters.count {
                let next = characters[index]
                index += 1
                if next.first?.isASCIIDigit == true {
                    collected += next
                } else if next == decimalSeparator {
                    collected += "."
                } else if next != thousandsSeparator || index >= characters.count {
                    break
                }
            }
            number = collected
        }
        guard var number else { return nil }
        if !text.isEmpty, let value = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")), value == 0 {
            return "0"
        }
        if number.hasSuffix(".") {
            if number.count >= 2 {
                number.removeLast()
            } else {
                number = ""
                isNegative = false
            }
        }
        return isNegative ? "-" + number : number
    }
}

public enum InvalidBalance {
    public static let instruction = "Ungültiger Saldo"

    /// The new-account dialog shows the text in bold.
    public static func content(_ text: String, bold: Bool = false) -> String {
        "„\(bold ? "<b>\(text)</b>" : text)“ ist keine gültige Zahl."
    }
}

extension Character {
    var isASCIIDigit: Bool { asciiValue.map { (48...57).contains($0) } ?? false }
}
