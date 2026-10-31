import Foundation
import Testing

@testable import AbakusCore

@Suite struct DateWithoutTimeTests {
    @Test func serialisesAsYearMonthDay() throws {
        let data = try JSONEncoder().encode([october23])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-10-23\"]")
        #expect(try JSONDecoder().decode([DateWithoutTime].self, from: data) == [october23])
    }

    @Test func rejectsInvalidStrings() {
        #expect(DateWithoutTime(string: "2026-02-30") == nil)
        #expect(DateWithoutTime(string: "2026-13-01") == nil)
        #expect(DateWithoutTime(string: "23.10.2026") == nil)
    }

    @Test func todayIsGregorianWhateverTheUsersCalendar() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = try #require(TimeZone(identifier: "Asia/Bangkok"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-23T20:00:00Z"))
        #expect(DateWithoutTime.today(calendar: buddhist, now: now) == date("2026-10-24"))
    }

    @Test func twoDigitYearsPivotAtSeventy() {
        #expect(DateWithoutTime.year(fromTwoDigits: 70) == 2070)
        #expect(DateWithoutTime.year(fromTwoDigits: 71) == 1971)
        #expect(DateWithoutTime.year(fromTwoDigits: 2026) == 2026)
    }

    @Test func normalisesOverflowingComponents() {
        #expect(DateWithoutTime(year: 2026, month: 13, day: 1) == date("2027-01-01"))
        #expect(DateWithoutTime(year: 2026, month: 0, day: 1) == date("2025-12-01"))
        #expect(DateWithoutTime(year: 2026, month: 2, day: 30) == date("2026-03-02"))
    }

    @Test func addsDaysAcrossMonthAndYearEnds() {
        #expect(date("2026-12-30").addingDays(3) == date("2027-01-02"))
        #expect(date("2024-03-01").addingDays(-1) == date("2024-02-29"))
        #expect(date("2026-10-23").days(until: date("2026-11-02")) == 10)
    }

    @Test func addingMonthsClampsToTheLastDay() {
        #expect(date("2026-01-31").addingMonths(1) == date("2026-02-28"))
        #expect(date("2024-01-31").addingMonths(1) == date("2024-02-29"))
        #expect(date("2026-03-15").addingMonths(-3) == date("2025-12-15"))
    }

    @Test func addingYearsRollsLeapDayIntoMarch() {
        #expect(date("2024-02-29").addingYears(1) == date("2025-03-01"))
        #expect(date("2026-10-23").addingYears(2) == date("2028-10-23"))
    }

    @Test func comparesByCalendarOrder() {
        #expect(date("2026-09-30") < date("2026-10-01"))
        #expect(date("2025-12-31") < date("2026-01-01"))
    }

    @Test func monthBoundaries() {
        #expect(october23.firstOfMonth == date("2026-10-01"))
        #expect(october23.lastOfMonth == date("2026-10-31"))
        #expect(date("2026-02-10").daysInMonth == 28)
        #expect(october23.monthKey == "2026-10")
    }

    @Test func todayUsesTheCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 0, minute: 30))!
        #expect(DateWithoutTime.today(calendar: calendar, now: now) == date("2026-10-23"))
    }
}

@Suite struct AmountTests {
    @Test(arguments: [
        ("2.505", "2.51"), ("2.504", "2.5"), ("-2.505", "-2.5"), ("-2.506", "-2.51"), ("-0.004", "0"),
        ("1234.5", "1234.5"), ("0.125", "0.13"),
    ])
    func roundsLikeActionScript(input: String, expected: String) {
        #expect(Amount.round(decimal(input)) == decimal(expected))
    }

    @Test func roundsToOtherDigitCounts() {
        #expect(Amount.round(decimal("12.5"), digits: 0) == 13)
        #expect(Amount.round(decimal("1.2345"), digits: 3) == decimal("1.235"))
    }

    @Test func sumRoundsEveryStep() {
        #expect(Amount.sum([decimal("0.1"), decimal("0.2"), decimal("0.004")]) == decimal("0.3"))
    }

    @Test func entitiesRoundAmountsOnWrite() {
        var transaction = Transaction(accountId: "A", date: october23, amount: decimal("10.005"))
        #expect(transaction.amount == decimal("10.01"))
        transaction.amount = decimal("-3.333")
        #expect(transaction.amount == decimal("-3.33"))
        #expect(transaction.outflow == decimal("3.33"))
        #expect(transaction.inflow == 0)
    }
}
