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

    @Test func aTwiceAMonthScheduleEntersEachDateOnce() throws {
        let schedule = ScheduledTransaction(
            id: "S", accountId: "GIRO", nextDate: date("2026-10-05"), frequency: .twiceAMonth, amount: -10)
        var fixture = TestBudget()
        fixture.budget.scheduledTransactions = [schedule]
        try fixture.budget.apply(.enterDueScheduledTransactions(today: date("2026-10-31")))
        try fixture.budget.apply(.enterDueScheduledTransactions(today: date("2026-10-31")))
        let entered = fixture.budget.transactions.filter { $0.scheduledTransactionId == "S" }
        #expect(entered.map(\.date) == [date("2026-10-05"), date("2026-10-20")])
    }
}
