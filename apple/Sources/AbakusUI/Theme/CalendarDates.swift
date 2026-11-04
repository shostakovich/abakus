import AbakusCore
import Foundation

extension FormatLocale {
    /// Gregorian like the budget's dates, with the date locale's first weekday.
    package var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: identifier)
        calendar.firstWeekday = firstDayOfWeek + 1
        return calendar
    }
}

extension DateWithoutTime {
    package init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    package func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}
