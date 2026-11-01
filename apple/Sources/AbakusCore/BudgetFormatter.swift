import Foundation

public struct FormatLocale: Hashable, Sendable {
    public enum DateSequence: Sendable { case dmy, mdy, ymd }

    public var identifier: String
    public var currencySymbol: String
    public var symbolOnLeft: Bool
    public var decimalSeparator: String
    public var groupSeparator: String
    public var decimalDigits: Int
    public var dateSequence: DateSequence
    public var dateSeparator: String
    public var monthNames: [String]
    public var shortMonthNames: [String]
    public var dayNamesShortest: [String]
    /// 0 is Sunday.
    public var firstDayOfWeek: Int

    public static let deDE = FormatLocale(
        identifier: "de_DE", currencySymbol: "€", symbolOnLeft: false, decimalSeparator: ",", groupSeparator: ".",
        decimalDigits: 2, dateSequence: .dmy, dateSeparator: ".",
        monthNames: [
            "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
            "November", "Dezember",
        ], dayNamesShortest: ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"], firstDayOfWeek: 1,
        shortMonthNames: ["Jan", "Feb", "Mrz", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"])

    public static let enUS = FormatLocale(
        identifier: "en_US", currencySymbol: "$", symbolOnLeft: true, decimalSeparator: ".", groupSeparator: ",",
        decimalDigits: 2, dateSequence: .mdy, dateSeparator: "/",
        monthNames: [
            "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
            "November", "December",
        ], dayNamesShortest: ["S", "M", "T", "W", "T", "F", "S"], firstDayOfWeek: 0)

    public init(
        identifier: String, currencySymbol: String, symbolOnLeft: Bool, decimalSeparator: String,
        groupSeparator: String, decimalDigits: Int, dateSequence: DateSequence, dateSeparator: String,
        monthNames: [String], dayNamesShortest: [String], firstDayOfWeek: Int, shortMonthNames: [String]? = nil
    ) {
        self.identifier = identifier
        self.currencySymbol = currencySymbol
        self.symbolOnLeft = symbolOnLeft
        self.decimalSeparator = decimalSeparator
        self.groupSeparator = groupSeparator
        self.decimalDigits = decimalDigits
        self.dateSequence = dateSequence
        self.dateSeparator = dateSeparator
        self.monthNames = monthNames
        self.shortMonthNames = shortMonthNames ?? monthNames.map { String($0.prefix(3)) }
        self.dayNamesShortest = dayNamesShortest
        self.firstDayOfWeek = firstDayOfWeek
    }

    public init(identifier: String) {
        switch identifier {
        case "de_DE": self = .deDE
        case "en_US": self = .enUS
        default: self = Self.derived(from: Locale(identifier: identifier))
        }
    }

    private static func derived(from locale: Locale) -> FormatLocale {
        let currency = NumberFormatter()
        currency.locale = locale
        currency.numberStyle = .currency
        let symbol = currency.currencySymbol ?? "¤"
        let sample = currency.string(from: 1) ?? ""
        let shortDate = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: locale) ?? "dd/MM/yyyy"
        let letters = shortDate.filter { "dMy".contains($0) }
        let sequence: DateSequence =
            letters.first == "y" ? .ymd : (letters.first == "M" ? .mdy : .dmy)
        let separator = shortDate.first { !$0.isLetter }.map(String.init) ?? "/"
        let names = DateFormatter()
        names.locale = locale
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let weekdays: [String]? = names.shortStandaloneWeekdaySymbols
        let days = weekdays?.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        return FormatLocale(
            identifier: locale.identifier, currencySymbol: symbol, symbolOnLeft: sample.hasPrefix(symbol),
            decimalSeparator: currency.currencyDecimalSeparator ?? ".",
            groupSeparator: currency.currencyGroupingSeparator ?? ",",
            decimalDigits: max(0, currency.maximumFractionDigits), dateSequence: sequence, dateSeparator: separator,
            monthNames: names.standaloneMonthSymbols ?? FormatLocale.enUS.monthNames,
            dayNamesShortest: days ?? FormatLocale.enUS.dayNamesShortest, firstDayOfWeek: calendar.firstWeekday - 1,
            shortMonthNames: names.shortStandaloneMonthSymbols?.map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            })
    }
}

public struct BudgetFormatter: Hashable, Sendable {
    public var currencyLocale: FormatLocale
    public var dateLocale: FormatLocale

    public init(currencyLocale: FormatLocale = .deDE, dateLocale: FormatLocale? = nil) {
        self.currencyLocale = currencyLocale
        self.dateLocale = dateLocale ?? currencyLocale
    }

    public init(metaData: BudgetMetaData) {
        self.init(
            currencyLocale: FormatLocale(identifier: metaData.currencyLocale),
            dateLocale: FormatLocale(identifier: metaData.dateLocale))
    }

    public func currency(_ value: Decimal) -> String {
        format(value, symbol: true, thousands: true)
    }

    public func currencyNoSymbol(_ value: Decimal) -> String {
        format(value, symbol: false, thousands: true)
    }

    public func currencySimple(_ value: Decimal) -> String {
        format(value, symbol: false, thousands: false)
    }

    public func registerAmount(_ value: Decimal) -> String {
        Amount.round(value, digits: currencyLocale.decimalDigits) == 0 ? "" : currencyNoSymbol(value)
    }

    public func dateShort(_ date: DateWithoutTime) -> String {
        dateString(date, year: String(format: "%02d", date.year % 100))
    }

    /// Day and month without the year, "24.10." where dates end in a dot.
    public func dayMonth(_ date: DateWithoutTime) -> String {
        let day = String(format: "%02d", date.day)
        let month = String(format: "%02d", date.month)
        let separator = dateLocale.dateSeparator
        let parts = dateLocale.dateSequence == .dmy ? [day, month] : [month, day]
        return parts.joined(separator: separator) + (separator == "." ? "." : "")
    }

    public func monthName(_ month: Int) -> String {
        dateLocale.monthNames[(month - 1 + 12) % 12]
    }

    public func monthHeader(_ date: DateWithoutTime) -> String {
        "\(monthName(date.month)) \(date.year)"
    }

    private func dateString(_ date: DateWithoutTime, year: String) -> String {
        let day = String(format: "%02d", date.day)
        let month = String(format: "%02d", date.month)
        let parts =
            switch dateLocale.dateSequence {
            case .dmy: [day, month, year]
            case .mdy: [month, day, year]
            case .ymd: [year, month, day]
            }
        return parts.joined(separator: dateLocale.dateSeparator)
    }

    private func format(_ value: Decimal, symbol: Bool, thousands: Bool) -> String {
        let locale = currencyLocale
        let rounded = Amount.round(value, digits: locale.decimalDigits)
        let negative = rounded < 0
        let digits = NSDecimalNumber(decimal: negative ? -rounded : rounded).stringValue
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        var integer = String(parts[0])
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        fraction += String(repeating: "0", count: max(0, locale.decimalDigits - fraction.count))
        if thousands { integer = grouped(integer, separator: locale.groupSeparator) }
        var number = locale.decimalDigits > 0 ? integer + locale.decimalSeparator + fraction : integer
        if symbol {
            number = locale.symbolOnLeft ? locale.currencySymbol + number : number + locale.currencySymbol
        }
        return negative ? "-" + number : number
    }

    private func grouped(_ integer: String, separator: String) -> String {
        var groups: [String] = []
        var remaining = Substring(integer)
        while remaining.count > 3 {
            groups.insert(String(remaining.suffix(3)), at: 0)
            remaining = remaining.dropLast(3)
        }
        groups.insert(String(remaining), at: 0)
        return groups.joined(separator: separator)
    }
}
