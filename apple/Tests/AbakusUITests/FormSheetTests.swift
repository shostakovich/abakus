import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@Suite struct FormSheetTests {
    @Test func theDatePickerStartsTheWeekOnTheDateLocalesFirstDay() {
        #expect(FormatLocale.deDE.calendar.firstWeekday == 2)
        #expect(FormatLocale.deDE.calendar.locale?.identifier == "de_DE")
    }

    @Test func aBudgetDateSurvivesTheDatePicker() {
        let calendar = FormatLocale.deDE.calendar
        let date = DateWithoutTime(year: 2026, month: 2, day: 28)
        #expect(DateWithoutTime(date.date(in: calendar), in: calendar) == date)
    }
}
