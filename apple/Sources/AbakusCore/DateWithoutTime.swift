import Foundation

public struct DateWithoutTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        let monthIndex = year * 12 + (month - 1)
        let normalizedYear = monthIndex >= 0 ? monthIndex / 12 : (monthIndex - 11) / 12
        let normalizedMonth = monthIndex - normalizedYear * 12 + 1
        let first = Self.daysFromCivil(normalizedYear, normalizedMonth, 1)
        (self.year, self.month, self.day) = Self.civilFromDays(first + day - 1)
    }

    /// The years every parser accepts; beyond them the day arithmetic would overflow.
    public static let supportedYears = 1000...3000

    /// Two-digit years up to 70 are this century, the others the last one.
    public static func year(fromTwoDigits year: Int) -> Int {
        year < 100 ? year + (year > 70 ? 1900 : 2000) : year
    }

    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            Self.supportedYears.contains(year), (1...12).contains(month),
            (1...Self.daysInMonth(year: year, month: month)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = DateWithoutTime(string: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(text)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    /// Budgets use Gregorian dates; the user's calendar only contributes its time zone.
    public static func today(calendar: Calendar = .current, now: Date = Date()) -> DateWithoutTime {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: now)
        return DateWithoutTime(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public func noon(calendar: Calendar = .current) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var monthKey: String {
        String(format: "%04d-%02d", year, month)
    }

    public static func < (lhs: DateWithoutTime, rhs: DateWithoutTime) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    public var daysInMonth: Int { Self.daysInMonth(year: year, month: month) }
    public var firstOfMonth: DateWithoutTime { DateWithoutTime(year: year, month: month, day: 1) }
    public var lastOfMonth: DateWithoutTime { DateWithoutTime(year: year, month: month, day: daysInMonth) }

    public var dayNumber: Int { Self.daysFromCivil(year, month, day) }

    public func addingDays(_ days: Int) -> DateWithoutTime {
        let (year, month, day) = Self.civilFromDays(dayNumber + days)
        return DateWithoutTime(year: year, month: month, day: day)
    }

    public func addingMonths(_ months: Int) -> DateWithoutTime {
        let target = DateWithoutTime(year: year, month: month + months, day: 1)
        return DateWithoutTime(year: target.year, month: target.month, day: min(day, target.daysInMonth))
    }

    /// Sets the year directly, so February 29 rolls over to March 1.
    public func addingYears(_ years: Int) -> DateWithoutTime {
        DateWithoutTime(year: year + years, month: month, day: day)
    }

    public func days(until other: DateWithoutTime) -> Int {
        other.dayNumber - dayNumber
    }

    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civilFromDays(_ days: Int) -> (Int, Int, Int) {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPart = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPart + 2) / 5 + 1
        let month = monthPart < 10 ? monthPart + 3 : monthPart - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}
