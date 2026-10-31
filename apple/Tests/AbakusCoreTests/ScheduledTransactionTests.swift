import Foundation
import Testing

@testable import AbakusCore

@Suite struct ScheduledTransactionTests {
    private func schedule(
        _ fixture: inout TestBudget, id: String = "S1", on day: String, frequency: ScheduledTransactionFrequency,
        amount: Decimal = -30, payee: String = "Stadtwerke", target: String? = nil
    ) throws {
        let transaction = Transaction(
            id: id, accountId: fixture.girokonto, date: date(day), categoryId: fixture.groceries,
            memo: "Strom", amount: amount
        ).transferring(to: target)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(
                    transaction: transaction, frequency: frequency, payeeName: target == nil ? payee : nil,
                    isNew: true)))
    }

    @Test func savingANewScheduleStoresItUncleared() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", frequency: .monthly)
        let scheduled = try #require(fixture.budget.scheduledTransaction(withId: "S1"))
        #expect(scheduled.frequency == .monthly)
        #expect(scheduled.cleared == .uncleared)
        #expect(scheduled.firstDay == nil && scheduled.secondDay == nil)
        #expect(fixture.budget.payeeName(of: scheduled) == "Stadtwerke")
        #expect(fixture.budget.transactions.count == 3)
    }

    @Test func twiceAMonthDaysFollowTheDateAndSurviveUnrelatedEdits() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-20", frequency: .twiceAMonth)
        var scheduled = try #require(fixture.budget.scheduledTransaction(withId: "S1"))
        #expect(scheduled.firstDay == 5 && scheduled.secondDay == 20)
        fixture.budget.scheduledTransactions[0].firstDay = 3
        fixture.budget.scheduledTransactions[0].secondDay = 18
        var edited = try #require(fixture.budget.scheduledTransaction(withId: "S1")).editableTransaction
        edited.memo = "Gas"
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: edited, frequency: .twiceAMonth, payeeName: nil, isNew: false)))
        scheduled = try #require(fixture.budget.scheduledTransaction(withId: "S1"))
        #expect(scheduled.firstDay == 3 && scheduled.secondDay == 18)
        edited.date = date("2026-11-08")
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: edited, frequency: .twiceAMonth, payeeName: nil, isNew: false)))
        scheduled = try #require(fixture.budget.scheduledTransaction(withId: "S1"))
        #expect(scheduled.firstDay == 8 && scheduled.secondDay == 23)
    }

    @Test func enterNowAddsAnApprovedTransactionAndAdvancesTheSchedule() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", frequency: .monthly)
        try fixture.budget.apply(
            .enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true)))
        let entered = try #require(fixture.budget.transactions.first { $0.source == .scheduled })
        #expect(entered.id == EntityID.enteredTransaction(scheduledId: "S1", date: date("2026-11-02")))
        #expect(entered.date == date("2026-11-02"))
        #expect(entered.approved)
        #expect(entered.cleared == .uncleared)
        #expect(entered.memo == "Strom")
        #expect(entered.scheduledTransactionId == "S1" && entered.scheduledDate == date("2026-11-02"))
        #expect(fixture.budget.payeeName(of: entered) == "Stadtwerke")
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.nextDate == date("2026-12-02"))
    }

    @Test func anOccurrenceEnteredAlreadyIsNotEnteredAgainButTheScheduleMovesOn() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-10-02", frequency: .monthly)
        let id = EntityID.enteredTransaction(scheduledId: "S1", date: date("2026-10-02"))
        _ = try fixture.add(fixture.girokonto, -30, on: "2026-10-02", payee: "Stadtwerke", id: id)
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        #expect(fixture.budget.transactions.filter { $0.id == id }.count == 1)
        #expect(fixture.budget.transaction(withId: id)?.source == .manual)
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.nextDate == date("2026-11-02"))
    }

    @Test func enteringAOnceScheduleRemovesIt() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", frequency: .once)
        try fixture.budget.apply(
            .enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true)))
        #expect(fixture.budget.scheduledTransactions.isEmpty)
        #expect(fixture.budget.transactions.contains { $0.scheduledTransactionId == "S1" })
    }

    @Test func dueOccurrencesAreEnteredUnapprovedUntilTheScheduleIsInTheFuture() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-10-09", frequency: .weekly)
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        let entered = fixture.budget.transactions.filter { $0.source == .scheduled }
        #expect(entered.map(\.date) == [date("2026-10-09"), date("2026-10-16"), date("2026-10-23")])
        #expect(entered.allSatisfy { !$0.approved })
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.nextDate == date("2026-10-30"))
        #expect(fixture.budget.errorState(of: entered[0]).level == .forReview)
    }

    @Test func dueOnceScheduleIsEnteredAndRemovedButAFutureOneStays() throws {
        var fixture = TestBudget()
        try schedule(&fixture, id: "PAST", on: "2026-10-20", frequency: .once)
        try schedule(&fixture, id: "FUTURE", on: "2026-10-24", frequency: .once)
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        #expect(fixture.budget.scheduledTransactions.map(\.id) == ["FUTURE"])
        #expect(fixture.budget.transactions.filter { $0.source == .scheduled }.count == 1)
    }

    @Test func enteredTransferCreatesItsCounterpart() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-10-20", frequency: .monthly, amount: -200, target: fixture.tagesgeld)
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        let entered = EntityID.enteredTransaction(scheduledId: "S1", date: date("2026-10-20"))
        let counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: entered)))
        #expect(counterpart.accountId == fixture.tagesgeld)
        #expect(counterpart.amount == 200)
        #expect(counterpart.payeeId == EntityID.transferPayee(accountId: fixture.girokonto))
        #expect(counterpart.source == .scheduled)
    }

    @Test func enteredSplitPartsAreNamedAfterTheTransactionAndTheirPosition() throws {
        var fixture = TestBudget()
        let transaction = Transaction(
            id: "S1", accountId: fixture.girokonto, date: date("2026-10-20"), amount: -30,
            subtransactions: [
                Subtransaction(id: "a", transactionId: "S1", amount: -10, categoryId: fixture.groceries),
                Subtransaction(id: "b", transactionId: "S1", amount: -20, categoryId: fixture.groceries),
            ])
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, frequency: .yearly, payeeName: "Markt", isNew: true)))
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.categoryId == nil)
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        let entered = try #require(fixture.budget.transactions.first { $0.source == .scheduled })
        #expect(
            entered.subtransactions.map(\.id)
                == [0, 1].map {
                    EntityID.enteredSubtransaction(transactionId: entered.id, position: $0)
                })
        #expect(entered.subtransactions.allSatisfy { $0.transactionId == entered.id })
    }

    @Test func skipMovesToTheNextOccurrence() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", frequency: .everyOtherWeek)
        try fixture.budget.apply(.skipScheduledTransactions(["S1"]))
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.nextDate == date("2026-11-16"))
    }

    @Test func deleteRemovesTheScheduleAndKeepsItsPayee() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", frequency: .monthly, payee: "Nur Geplant")
        try fixture.budget.apply(.deleteScheduledTransactions(["S1"]))
        #expect(fixture.budget.scheduledTransactions.isEmpty)
        #expect(fixture.budget.payees.contains { $0.name == "Nur Geplant" })
    }

    @Test func moveRefusesATransferIntoTheTargetAccount() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", frequency: .monthly, target: fixture.tagesgeld)
        #expect(throws: BudgetError.transferIntoMoveTarget("Tagesgeld")) {
            try fixture.budget.apply(.moveScheduledTransactions(["S1"], toAccount: fixture.tagesgeld))
        }
        try fixture.budget.apply(.moveScheduledTransactions(["S1"], toAccount: fixture.depot))
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.accountId == fixture.depot)
    }

    @Test(arguments: [
        (ScheduledTransactionFrequency.once, "2026-01-31", "2026-01-31"),
        (.daily, "2026-01-31", "2026-02-01"),
        (.weekly, "2026-01-31", "2026-02-07"),
        (.everyOtherWeek, "2026-01-31", "2026-02-14"),
        (.every4Weeks, "2026-01-31", "2026-02-28"),
        (.monthly, "2026-01-31", "2026-02-28"),
        (.everyOtherMonth, "2026-01-31", "2026-03-31"),
        (.every3Months, "2026-01-31", "2026-04-30"),
        (.every4Months, "2026-01-31", "2026-05-31"),
        (.twiceAYear, "2026-08-31", "2027-02-28"),
        (.yearly, "2028-02-29", "2029-02-28"),
        (.everyOtherYear, "2026-01-31", "2028-01-31"),
    ])
    func following(frequency: ScheduledTransactionFrequency, from: String, to: String) {
        #expect(frequency.following(date(from)) == date(to))
    }

    @Test func twiceAMonthAlternatesBetweenItsTwoDays() {
        let start = date("2026-02-14")
        let days = ScheduledTransactionFrequency.twiceAMonthDays(for: start)
        let second = ScheduledTransactionFrequency.twiceAMonth.following(start, days: days)
        #expect(second == date("2026-02-28"))
        let third = ScheduledTransactionFrequency.twiceAMonth.following(second, days: days)
        #expect(third == date("2026-03-14"))
        #expect(ScheduledTransactionFrequency.twiceAMonthDays(for: date("2026-02-20")) == (5, 20))
    }

    @Test func schedulesThatCannotBeAddedAsTheyAreAreEnteredPlain() throws {
        var fixture = TestBudget()
        fixture.budget.scheduledTransactions = [
            ScheduledTransaction(
                id: "OWN", accountId: fixture.girokonto, nextDate: date("2026-10-20"), frequency: .once,
                payeeId: EntityID.transferPayee(accountId: fixture.girokonto), amount: -5),
            ScheduledTransaction(
                id: "UNEVEN", accountId: fixture.girokonto, nextDate: date("2026-10-21"), frequency: .once,
                amount: -10,
                subtransactions: [
                    Subtransaction(transactionId: "UNEVEN", amount: -4, categoryId: fixture.groceries)
                ]),
        ]
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        let entered = fixture.budget.transactions.filter { $0.source == .scheduled }
        #expect(entered.count == 2)
        let transfer = try #require(entered.first { $0.scheduledTransactionId == "OWN" })
        #expect(transfer.payeeId == nil)
        let split = try #require(entered.first { $0.scheduledTransactionId == "UNEVEN" })
        #expect(split.subtransactions.isEmpty)
        #expect(split.categoryId == nil)
        #expect(split.amount == -10)
    }

    @Test func allThirteenFrequenciesHaveGermanLabels() {
        #expect(
            ScheduledTransactionFrequency.allCases.map(\.readableName) == [
                "Einmalig", "Täglich", "Wöchentlich", "Alle 2 Wochen", "Zweimal im Monat", "Alle 4 Wochen", "Monatlich",
                "Alle 2 Monate", "Alle 3 Monate", "Alle 4 Monate", "Zweimal im Jahr", "Jährlich", "Alle 2 Jahre",
            ])
    }
}
