import Foundation

public enum ScheduledTransactionFrequency: String, Codable, CaseIterable, Sendable {
    case once
    case daily
    case weekly
    case everyOtherWeek = "every_other_week"
    case twiceAMonth = "twice_a_month"
    case every4Weeks = "every_4_weeks"
    case monthly
    case everyOtherMonth = "every_other_month"
    case every3Months = "every_3_months"
    case every4Months = "every_4_months"
    case twiceAYear = "twice_a_year"
    case yearly
    case everyOtherYear = "every_other_year"

    public var readableName: String {
        switch self {
        case .once: "Einmalig"
        case .daily: "Täglich"
        case .weekly: "Wöchentlich"
        case .everyOtherWeek: "Alle 2 Wochen"
        case .twiceAMonth: "Zweimal im Monat"
        case .every4Weeks: "Alle 4 Wochen"
        case .monthly: "Monatlich"
        case .everyOtherMonth: "Alle 2 Monate"
        case .every3Months: "Alle 3 Monate"
        case .every4Months: "Alle 4 Monate"
        case .twiceAYear: "Zweimal im Jahr"
        case .yearly: "Jährlich"
        case .everyOtherYear: "Alle 2 Jahre"
        }
    }

    /// The days of a schedule twice a month that starts on `date`: its day and the day 15 later.
    public static func twiceAMonthDays(for date: DateWithoutTime) -> (first: Int, second: Int) {
        let first = date.day <= 15 ? date.day : date.day - 15
        return (first, first + 15)
    }

    /// The occurrence after `date`; `days` only twice a month.
    public func following(_ date: DateWithoutTime, days: (first: Int, second: Int)? = nil) -> DateWithoutTime {
        step(date, by: 1, days: days)
    }

    /// Steps as `sync/PROTOCOL.md` says, so every writer enters the same dates.
    func step(_ date: DateWithoutTime, by sign: Int, days: (first: Int, second: Int)?) -> DateWithoutTime {
        switch self {
        case .once: date
        case .twiceAMonth:
            days.map { sign > 0 ? Self.nextTwiceAMonth(after: date, $0) : Self.previousTwiceAMonth(before: date, $0) }
                ?? date
        case .daily: date.addingDays(sign)
        case .weekly: date.addingDays(7 * sign)
        case .everyOtherWeek: date.addingDays(14 * sign)
        case .every4Weeks: date.addingDays(28 * sign)
        case .monthly: date.addingMonths(sign)
        case .everyOtherMonth: date.addingMonths(2 * sign)
        case .every3Months: date.addingMonths(3 * sign)
        case .every4Months: date.addingMonths(4 * sign)
        case .twiceAYear: date.addingMonths(6 * sign)
        case .yearly: date.addingMonths(12 * sign)
        case .everyOtherYear: date.addingMonths(24 * sign)
        }
    }

    private static func on(_ day: Int, in month: DateWithoutTime) -> DateWithoutTime {
        DateWithoutTime(year: month.year, month: month.month, day: min(day, month.daysInMonth))
    }

    private static func nextTwiceAMonth(after date: DateWithoutTime, _ days: (first: Int, second: Int))
        -> DateWithoutTime
    {
        let later = [days.first, days.second].map { on($0, in: date) }.first { $0 > date }
        return later ?? on(days.first, in: date.firstOfMonth.addingMonths(1))
    }

    private static func previousTwiceAMonth(before date: DateWithoutTime, _ days: (first: Int, second: Int))
        -> DateWithoutTime
    {
        let earlier = [days.second, days.first].map { on($0, in: date) }.first { $0 < date }
        return earlier ?? on(days.second, in: date.firstOfMonth.addingMonths(-1))
    }
}

public struct ScheduledTransaction: Hashable, Identifiable, Sendable, SplittableTransaction {
    public var id: String
    public var accountId: String
    public var nextDate: DateWithoutTime
    public var frequency: ScheduledTransactionFrequency
    /// Only twice a month: the two days of the month.
    public var firstDay: Int?
    public var secondDay: Int?
    public var payeeId: String?
    public var categoryId: String?
    public var memo: String?
    public var amount: Decimal { didSet { amount = Amount.round(amount) } }
    public var cleared: ClearedStatus
    public var subtransactions: [Subtransaction]

    public init(
        id: String = EntityID.createUID(),
        accountId: String,
        nextDate: DateWithoutTime,
        frequency: ScheduledTransactionFrequency = .monthly,
        days: (first: Int, second: Int)? = nil,
        payeeId: String? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        amount: Decimal,
        cleared: ClearedStatus = .uncleared,
        subtransactions: [Subtransaction] = []
    ) {
        self.id = id
        self.accountId = accountId
        self.nextDate = nextDate
        self.frequency = frequency
        let twice =
            frequency == .twiceAMonth ? days ?? ScheduledTransactionFrequency.twiceAMonthDays(for: nextDate) : nil
        firstDay = twice?.first
        secondDay = twice?.second
        self.payeeId = payeeId
        self.categoryId = categoryId
        self.memo = memo
        self.amount = Amount.round(amount)
        self.cleared = cleared == .reconciled ? .cleared : cleared
        self.subtransactions = subtransactions
    }

    /// A transaction as a schedule: uncleared and its parts never linked as transfers.
    init(_ transaction: Transaction, frequency: ScheduledTransactionFrequency) {
        self.init(
            id: transaction.id, accountId: transaction.accountId, nextDate: transaction.date, frequency: frequency,
            payeeId: transaction.payeeId, categoryId: transaction.isSplit ? nil : transaction.categoryId,
            memo: transaction.memo, amount: transaction.amount,
            subtransactions: transaction.subtransactions.map { part in
                var line = part
                line.transactionId = transaction.id
                line.transferTransactionId = nil
                return line
            })
    }

    public var days: (first: Int, second: Int)? {
        guard let firstDay, let secondDay else { return nil }
        return (firstDay, secondDay)
    }

    public var followingDate: DateWithoutTime {
        frequency.step(nextDate, by: 1, days: days)
    }

    /// `nextDate` is the next occurrence, so the recurrence is also projected backwards.
    public func occurrences(from first: DateWithoutTime, through last: DateWithoutTime) -> Int {
        if frequency == .once { return nextDate >= first && nextDate <= last ? 1 : 0 }
        guard nextDate <= last else { return 0 }
        let next = { frequency.step($0, by: 1, days: days) }
        let previous = { frequency.step($0, by: -1, days: days) }
        var cursor = nextDate
        while cursor > first {
            let earlier = previous(cursor)
            guard earlier < cursor else { break }
            cursor = earlier
        }
        while cursor < first {
            let later = next(cursor)
            guard later > cursor else { return 0 }
            cursor = later
        }
        var count = 0
        while cursor <= last {
            count += 1
            let later = next(cursor)
            guard later > cursor else { break }
            cursor = later
        }
        return count
    }
}
