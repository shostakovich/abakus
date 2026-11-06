import Foundation

/// How often a scheduled transaction happens: once, or every `count` weeks or months (`sync/PROTOCOL.md`).
public enum Repeat: Hashable, Sendable {
    case once
    case every(Int, Unit)

    public enum Unit: String, CaseIterable, Sendable {
        case week, month
    }

    /// The four choices of the „Wiederholen“ field; Eigene is any other count and unit.
    public enum Choice: CaseIterable, Sendable {
        case once, monthly, yearly, custom

        public var label: String {
            switch self {
            case .once: "Einmalig"
            case .monthly: "Monatlich"
            case .yearly: "Jährlich"
            case .custom: "Eigene"
            }
        }
    }

    public static let counts = 1...99
    public static let monthly = Repeat.every(1, .month)
    public static let yearly = Repeat.every(12, .month)
    public static let customDefault = Repeat.every(2, .week)

    public var unit: Unit? {
        guard case .every(_, let unit) = self else { return nil }
        return unit
    }

    public var count: Int? {
        guard case .every(let count, _) = self else { return nil }
        return count
    }

    public var label: String {
        switch self {
        case .once: "Einmalig"
        case .every(1, .week): "Wöchentlich"
        case .every(let count, .week): "Alle \(count) Wochen"
        case .every(1, .month): "Monatlich"
        case .every(12, .month): "Jährlich"
        case .every(let count, .month): "Alle \(count) Monate"
        }
    }

    public var choice: Choice {
        switch self {
        case .once: .once
        case Self.monthly: .monthly
        case Self.yearly: .yearly
        case .every: .custom
        }
    }

    /// Eigene keeps a custom count and unit, else starts at every 2 weeks.
    public func choosing(_ choice: Choice) -> Repeat {
        switch choice {
        case .once: .once
        case .monthly: .monthly
        case .yearly: .yearly
        case .custom: self.choice == .custom ? self : Self.customDefault
        }
    }

    /// The occurrence after `date`, nil once; months keep the day or take the month's last.
    public func following(_ date: DateWithoutTime) -> DateWithoutTime? {
        switch self {
        case .once: nil
        case .every(let count, .week): date.addingDays(7 * count)
        case .every(let count, .month): date.addingMonths(count)
        }
    }

    /// The dates of the `count` occurrences after `date`, none once.
    public func dates(after date: DateWithoutTime, count: Int) -> [DateWithoutTime] {
        var dates: [DateWithoutTime] = []
        var cursor = date
        while dates.count < count, let next = following(cursor) {
            dates.append(next)
            cursor = next
        }
        return dates
    }
}
