import AbakusCore
import Foundation
import Testing

@Suite struct DateFilterTests {
    private let range = DateFilterRange(start: date("2025-03-15"), end: date("2026-10-23"))
    private let formatter = BudgetFormatter()

    @Test func presetsResolveAgainstToday() {
        let thisMonth = DateFilterSelection.preset(.thisMonth, today: october23, range: range)
        #expect(thisMonth?.start == date("2026-10-01"))
        #expect(thisMonth?.end == date("2026-10-01"))
        #expect(thisMonth?.label == "Dieser Monat")
        let three = DateFilterSelection.preset(.latestThreeMonths, today: october23, range: range)
        #expect(three?.start == date("2026-08-01"))
        let year = DateFilterSelection.preset(.thisYear, today: october23, range: range)
        #expect(year?.start == date("2026-01-01"))
        #expect(year?.end == date("2026-12-01"))
        let last = DateFilterSelection.preset(.lastYear, today: october23, range: range)
        #expect(last?.start == date("2025-01-01"))
        #expect(last?.end == date("2025-12-01"))
    }

    @Test func allDatesIsNoFilter() {
        #expect(DateFilterSelection.preset(.allDates, today: october23, range: range) == nil)
    }

    @Test func filterIsByWholeMonths() {
        let selection = DateFilterSelection.preset(.thisMonth, today: october23, range: range)!
        #expect(selection.contains(date("2026-10-31")))
        #expect(selection.contains(date("2026-10-01")))
        #expect(!selection.contains(date("2026-09-30")))
        #expect(!selection.contains(date("2026-11-01")))
    }

    @Test func customLabels() {
        #expect(
            DateFilterSelection.custom(date("2026-10-01"), date("2026-10-01"), formatter: formatter).label
                == "Oktober 2026")
        #expect(
            DateFilterSelection.custom(date("2025-01-01"), date("2025-12-01"), formatter: formatter).label == "2025")
        #expect(
            DateFilterSelection.custom(date("2026-01-01"), date("2026-03-01"), formatter: formatter).label
                == "Januar 2026 bis März 2026")
    }

    @Test func customRangeSwapsReversedMonths() {
        let selection = DateFilterSelection.custom(date("2026-03-20"), date("2026-01-05"), formatter: formatter)
        #expect(selection.start == date("2026-01-01"))
        #expect(selection.end == date("2026-03-01"))
        #expect(selection.preset == nil)
    }

    @Test func customSelectionsStayFixed() {
        let selection = DateFilterSelection.custom(date("2026-01-01"), date("2026-03-01"), formatter: formatter)
        #expect(selection.resolved(today: date("2027-05-05"), range: range) == selection)
        let preset = DateFilterSelection.preset(.thisMonth, today: october23, range: range)!
        #expect(preset.resolved(today: date("2026-11-02"), range: range)?.start == date("2026-11-01"))
    }

    @Test func rangeRunsFromTheFirstTransactionToTodayOrLater() {
        let dates = [date("2026-05-02"), date("2026-12-24")]
        let range = DateFilterRange(dates: dates, today: october23)
        #expect(range.start == date("2026-05-01"))
        #expect(range.end == date("2026-12-01"))
        #expect(DateFilterRange(dates: [], today: october23).start == date("2026-10-01"))
    }

    @Test func presetEnableRules() {
        let young = DateFilterRange(start: date("2026-10-02"), end: date("2026-10-23"))
        #expect(young.isEnabled(.thisMonth, today: october23))
        #expect(young.isEnabled(.latestThreeMonths, today: october23))
        #expect(young.isEnabled(.thisYear, today: october23))
        #expect(!young.isEnabled(.lastYear, today: october23))
        #expect(range.isEnabled(.lastYear, today: october23))
        #expect(young.isEnabled(.allDates, today: october23))
    }

    @Test func thisMonthAndThisYearNeedATransactionThatRecent() {
        let old = DateFilterRange(dates: [date("2025-01-10"), date("2025-03-05")], today: october23)
        #expect(!old.isEnabled(.thisMonth, today: october23))
        #expect(!old.isEnabled(.thisYear, today: october23))
        #expect(old.end == date("2026-10-01"))
        let recent = DateFilterRange(dates: [date("2025-01-10"), date("2026-10-02")], today: october23)
        #expect(recent.isEnabled(.thisMonth, today: october23))
    }

    @Test func clampingKeepsMonthsInsideTheRange() {
        #expect(range.clamped(date("2020-01-01")) == date("2025-03-01"))
        #expect(range.clamped(date("2030-01-01")) == date("2026-10-01"))
        #expect(range.years == [2025, 2026])
    }
}
