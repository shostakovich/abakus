import Foundation

public enum DateFilterPreset: String, CaseIterable, Hashable, Sendable {
    case thisMonth = "This Month"
    case latestThreeMonths = "Latest 3 Months"
    case thisYear = "This Year"
    case lastYear = "Last Year"
    case allDates = "All Dates"

    public var label: String {
        switch self {
        case .thisMonth: "Dieser Monat"
        case .latestThreeMonths: "Letzte 3 Monate"
        case .thisYear: "Dieses Jahr"
        case .lastYear: "Letztes Jahr"
        case .allDates: "Alle Daten"
        }
    }
}

public struct DateFilterSelection: Hashable, Sendable {
    public var preset: DateFilterPreset?
    public var start: DateWithoutTime
    public var end: DateWithoutTime
    public var label: String

    /// Preset labels are resolved against today on every search, custom months stay fixed.
    public static func preset(_ preset: DateFilterPreset, today: DateWithoutTime, range: DateFilterRange)
        -> DateFilterSelection?
    {
        let month = today.firstOfMonth
        let (start, end): (DateWithoutTime, DateWithoutTime) =
            switch preset {
            case .thisMonth: (month, month)
            case .latestThreeMonths: (month.addingMonths(-2), month)
            case .thisYear:
                (
                    DateWithoutTime(year: today.year, month: 1, day: 1),
                    DateWithoutTime(year: today.year, month: 12, day: 1)
                )
            case .lastYear:
                (
                    DateWithoutTime(year: today.year - 1, month: 1, day: 1),
                    DateWithoutTime(year: today.year - 1, month: 12, day: 1)
                )
            case .allDates: (range.start, range.end)
            }
        guard preset != .allDates else { return nil }
        return DateFilterSelection(preset: preset, start: start, end: end, label: preset.label)
    }

    /// "Oktober 2026", "2025" for a whole year, else "Januar 2026 bis März 2026".
    public static func custom(_ first: DateWithoutTime, _ second: DateWithoutTime, formatter: BudgetFormatter)
        -> DateFilterSelection
    {
        let start = min(first, second).firstOfMonth
        let end = max(first, second).firstOfMonth
        let label: String
        if start == end {
            label = formatter.monthHeader(start)
        } else if start.year == end.year && start.month == 1 && end.month == 12 {
            label = String(start.year)
        } else {
            label = "\(formatter.monthHeader(start)) bis \(formatter.monthHeader(end))"
        }
        return DateFilterSelection(preset: nil, start: start, end: end, label: label)
    }

    public func resolved(today: DateWithoutTime, range: DateFilterRange) -> DateFilterSelection? {
        guard let preset else { return self }
        return Self.preset(preset, today: today, range: range)
    }

    public func contains(_ date: DateWithoutTime) -> Bool {
        date.monthKey >= start.monthKey && date.monthKey <= end.monthKey
    }
}

/// First to latest transaction; only the month pickers run to max(latest, today).
public struct DateFilterRange: Hashable, Sendable {
    public var start: DateWithoutTime
    public var end: DateWithoutTime
    public var latest: DateWithoutTime

    public init(start: DateWithoutTime, end: DateWithoutTime, latest: DateWithoutTime? = nil) {
        self.start = start.firstOfMonth
        self.end = end.firstOfMonth
        self.latest = (latest ?? end).firstOfMonth
    }

    public init(dates: [DateWithoutTime], today: DateWithoutTime) {
        let latest = dates.max() ?? today
        self.init(start: dates.min() ?? today, end: max(latest, today), latest: latest)
    }

    public var years: [Int] { Array(start.year...end.year) }

    public func clamped(_ month: DateWithoutTime) -> DateWithoutTime {
        min(max(month.firstOfMonth, start), end)
    }

    public func isEnabled(_ preset: DateFilterPreset, today: DateWithoutTime) -> Bool {
        let month = today.firstOfMonth
        switch preset {
        case .thisMonth: return latest >= month
        case .latestThreeMonths: return start <= month
        case .thisYear: return latest.year >= today.year
        case .lastYear: return start.year <= today.year - 1
        case .allDates: return true
        }
    }
}

extension Budget {
    public func dateFilterRange(forAccount key: String, today: DateWithoutTime) -> DateFilterRange {
        let list = key == EntityID.allAccounts ? transactions : transactions(inAccount: key)
        return DateFilterRange(dates: list.map(\.date), today: today)
    }
}
