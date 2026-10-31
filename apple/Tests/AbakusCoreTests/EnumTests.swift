import Testing

@testable import AbakusCore

@Suite struct EnumTests {
    @Test func errorLevelsOrderByRank() {
        #expect(ErrorLevel.allCases.sorted() == [.none, .needsCategory, .forReview, .error])
    }

    @Test func fourAccountTypesOfWhichOnlyTrackingIsOffBudget() {
        #expect(AccountKind.allCases.map(\.rawValue) == ["checking", "savings", "cash", "tracking"])
        #expect(AccountKind.allCases.map(\.label) == ["Girokonto", "Sparkonto", "Bargeld", "Tracking"])
        #expect(AccountKind.allCases.filter(\.isBudgetAccount) == AccountKind.budgetKinds)
    }

    @Test func recognisesTransferPayeeText() {
        #expect(Payee.isTransferPayeeName("Transfer : Tagesgeld"))
        #expect(Payee.isTransferPayeeName("transfer:Tagesgeld"))
        #expect(!Payee.isTransferPayeeName("Transferwise"))
        #expect(Payee.transferTargetAccountName("TRANSFER :  Tages geld ") == "Tages geld")
    }

    @Test func payeesNamedLikeBankImportsStartListed() throws {
        var fixture = TestBudget()
        for name in ["Cash", "Deposit", "Check"] { _ = try fixture.add(fixture.girokonto, -1, payee: name) }
        let created = fixture.budget.payees.filter { ["Cash", "Deposit", "Check"].contains($0.name) }
        #expect(created.count == 3 && created.allSatisfy { !$0.hidden })
    }
}

@Suite struct FrequencyTests {
    @Test(arguments: [
        (ScheduledTransactionFrequency.once, "2026-10-23"), (.daily, "2026-10-24"), (.weekly, "2026-10-30"),
        (.everyOtherWeek, "2026-11-06"), (.every4Weeks, "2026-11-20"), (.monthly, "2026-11-23"),
        (.everyOtherMonth, "2026-12-23"), (.every3Months, "2027-01-23"), (.every4Months, "2027-02-23"),
        (.twiceAYear, "2027-04-23"), (.yearly, "2027-10-23"), (.everyOtherYear, "2028-10-23"),
    ])
    func following(frequency: ScheduledTransactionFrequency, expected: String) {
        #expect(frequency.following(october23) == date(expected))
    }

    @Test func monthsKeepTheDayOrTakeTheMonthsLast() {
        let monthly = ScheduledTransactionFrequency.monthly
        #expect(monthly.following(date("2026-01-31")) == date("2026-02-28"))
        #expect(monthly.following(date("2026-02-28")) == date("2026-03-28"))
    }

    @Test func februaryTwentyNinthBecomesTheTwentyEighth() {
        #expect(ScheduledTransactionFrequency.yearly.following(date("2028-02-29")) == date("2029-02-28"))
        #expect(ScheduledTransactionFrequency.everyOtherYear.following(date("2028-02-29")) == date("2030-02-28"))
    }

    @Test func twiceAMonthDaysStartFromTheDateAndFoldTheSecondHalf() {
        #expect(ScheduledTransactionFrequency.twiceAMonthDays(for: date("2026-10-05")) == (5, 20))
        #expect(ScheduledTransactionFrequency.twiceAMonthDays(for: date("2026-10-23")) == (8, 23))
    }

    @Test func twiceAMonthGoesToTheNextOfItsDaysElseTheFirstOfTheNextMonth() {
        let frequency = ScheduledTransactionFrequency.twiceAMonth
        #expect(frequency.following(date("2026-10-05"), days: (5, 20)) == date("2026-10-20"))
        #expect(frequency.following(date("2026-10-20"), days: (5, 20)) == date("2026-11-05"))
        #expect(frequency.following(date("2026-10-10"), days: (5, 20)) == date("2026-10-20"))
    }

    @Test func twiceAMonthTakesTheLastDayOfAShortMonth() {
        let frequency = ScheduledTransactionFrequency.twiceAMonth
        #expect(frequency.following(date("2026-02-15"), days: (15, 30)) == date("2026-02-28"))
        #expect(frequency.following(date("2026-02-28"), days: (15, 30)) == date("2026-03-15"))
    }

    @Test func aScheduledTransactionTwiceAMonthDerivesItsDays() {
        let scheduled = ScheduledTransaction(
            accountId: "A", nextDate: date("2026-10-20"), frequency: .twiceAMonth, amount: -10)
        #expect(scheduled.firstDay == 5 && scheduled.secondDay == 20)
        #expect(scheduled.followingDate == date("2026-11-05"))
        let monthly = ScheduledTransaction(accountId: "A", nextDate: date("2026-10-20"), amount: -10)
        #expect(monthly.firstDay == nil && monthly.secondDay == nil)
    }

    @Test func readableNames() {
        #expect(ScheduledTransactionFrequency.everyOtherWeek.readableName == "Alle 2 Wochen")
        #expect(ScheduledTransactionFrequency.allCases.count == 13)
    }
}
