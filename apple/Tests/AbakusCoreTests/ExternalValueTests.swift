import Foundation
import Testing

@testable import AbakusCore

@Suite struct ExternalValueTests {
    @Test func datesOutsideTheSupportedYearsAreRejected() {
        #expect(DateWithoutTime(string: "100000000000000000-01-01") == nil)
        #expect(DateWithoutTime(string: "0999-12-31") == nil)
        #expect(DateWithoutTime(string: "1000-01-01") != nil)
        #expect(BudgetFormatter().parseDate("01.01.99999999999999999999", today: october23) == nil)
    }
}
