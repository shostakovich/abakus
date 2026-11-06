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

@Suite struct RepeatTests {
    @Test func weeksStepSevenDaysEach() {
        #expect(Repeat.every(1, .week).following(october23) == date("2026-10-30"))
        #expect(Repeat.every(2, .week).following(date("2026-12-09")) == date("2026-12-23"))
        #expect(Repeat.every(4, .week).following(date("2026-12-28")) == date("2027-01-25"))
    }

    @Test func monthsKeepTheDayOrTakeTheMonthsLast() {
        #expect(Repeat.monthly.following(date("2027-01-31")) == date("2027-02-28"))
        #expect(Repeat.monthly.following(date("2027-02-28")) == date("2027-03-28"))
        #expect(Repeat.every(6, .month).following(date("2026-08-31")) == date("2027-02-28"))
        #expect(Repeat.every(24, .month).following(date("2026-12-01")) == date("2028-12-01"))
    }

    @Test func yearlyIsTwelveMonthsSoFebruaryTwentyNinthBecomesTheTwentyEighth() {
        #expect(Repeat.yearly == .every(12, .month))
        #expect(Repeat.yearly.following(date("2028-02-29")) == date("2029-02-28"))
    }

    @Test func onceHasNoFollowingDate() {
        #expect(Repeat.once.following(october23) == nil)
        #expect(Repeat.once.dates(after: october23, count: 3).isEmpty)
    }

    @Test func theDatesAfterTheNextDate() {
        #expect(
            Repeat.every(2, .week).dates(after: date("2026-12-09"), count: 3) == [
                date("2026-12-23"), date("2027-01-06"), date("2027-01-20"),
            ])
        #expect(
            Repeat.monthly.dates(after: date("2027-01-31"), count: 2) == [date("2027-02-28"), date("2027-03-28")])
    }

    @Test func labels() {
        #expect(
            [Repeat.once, .every(1, .week), .every(2, .week), .monthly, .yearly, .every(3, .month)].map(\.label) == [
                "Einmalig", "Wöchentlich", "Alle 2 Wochen", "Monatlich", "Jährlich", "Alle 3 Monate",
            ])
    }

    @Test func choicesAreOnceMonthlyYearlyOrCustom() {
        #expect(Repeat.Choice.allCases.map(\.label) == ["Einmalig", "Monatlich", "Jährlich", "Eigene"])
        #expect(
            [Repeat.once, .monthly, .yearly, .every(1, .week), .every(2, .month)].map(\.choice) == [
                .once, .monthly, .yearly, .custom, .custom,
            ])
    }

    @Test func choosingCustomKeepsACustomRepeatElseStartsAtEveryTwoWeeks() {
        #expect(Repeat.every(3, .month).choosing(.custom) == .every(3, .month))
        #expect(Repeat.monthly.choosing(.custom) == .every(2, .week))
        #expect(Repeat.once.choosing(.custom) == .every(2, .week))
        #expect(Repeat.every(3, .month).choosing(.yearly) == .yearly)
        #expect(Repeat.monthly.choosing(.once) == .once)
    }
}
