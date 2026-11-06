import Foundation
import Testing

@testable import AbakusCore

@Suite struct ScheduledTransactionTests {
    private func schedule(
        _ fixture: inout TestBudget, id: String = "S1", on day: String, repeats: Repeat,
        amount: Decimal = -30, payee: String = "Stadtwerke", target: String? = nil
    ) throws {
        let transaction = Transaction(
            id: id, accountId: fixture.girokonto, date: date(day), categoryId: fixture.groceries,
            memo: "Strom", amount: amount
        ).transferring(to: target)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(
                    transaction: transaction, repeats: repeats, payeeName: target == nil ? payee : nil,
                    isNew: true)))
    }

    @Test func savingANewScheduleStoresItUncleared() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", repeats: .monthly)
        let scheduled = try #require(fixture.budget.scheduledTransaction(withId: "S1"))
        #expect(scheduled.repeats == .monthly)
        #expect(scheduled.cleared == .uncleared)
        #expect(fixture.budget.payeeName(of: scheduled) == "Stadtwerke")
        #expect(fixture.budget.transactions.count == 3)
    }

    @Test func enterNowAddsAnApprovedTransactionAndAdvancesTheSchedule() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", repeats: .monthly)
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

    @Test(arguments: [true, false]) func enterNowLeavesSchedulesOfAccountsThatTakeNoEntries(closed: Bool) throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", repeats: .monthly)
        let index = try #require(fixture.budget.accounts.firstIndex { $0.id == fixture.girokonto })
        if closed {
            fixture.budget.accounts[index].closed = true
        } else {
            fixture.budget.accounts[index].sharedExpenses = true
        }
        let before = fixture.budget
        try fixture.budget.apply(
            .enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true)))
        #expect(fixture.budget == before)
    }

    @Test func dueSchedulesOfAClosedAccountWaitAndAreCaughtUpOnceItIsReopened() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-10-09", repeats: .every(1, .week))
        try schedule(&fixture, id: "ONCE", on: "2026-10-20", repeats: .once)
        let index = try #require(fixture.budget.accounts.firstIndex { $0.id == fixture.girokonto })
        fixture.budget.accounts[index].closed = true
        let before = fixture.budget
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        #expect(fixture.budget == before)

        fixture.budget.accounts[index].closed = false
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        let entered = fixture.budget.transactions.filter { $0.source == .scheduled }
        #expect(
            entered.filter { $0.scheduledTransactionId == "S1" }.map(\.date)
                == [date("2026-10-09"), date("2026-10-16"), date("2026-10-23")])
        #expect(entered.contains { $0.scheduledTransactionId == "ONCE" })
        #expect(fixture.budget.scheduledTransactions.map(\.id) == ["S1"])
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.nextDate == date("2026-10-30"))
    }

    @Test func anOccurrenceEnteredAlreadyIsNotEnteredAgainButTheScheduleMovesOn() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-10-02", repeats: .monthly)
        let id = EntityID.enteredTransaction(scheduledId: "S1", date: date("2026-10-02"))
        _ = try fixture.add(fixture.girokonto, -30, on: "2026-10-02", payee: "Stadtwerke", id: id)
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        #expect(fixture.budget.transactions.filter { $0.id == id }.count == 1)
        #expect(fixture.budget.transaction(withId: id)?.source == .manual)
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.nextDate == date("2026-11-02"))
    }

    @Test func enteringAOnceScheduleRemovesIt() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", repeats: .once)
        try fixture.budget.apply(
            .enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true)))
        #expect(fixture.budget.scheduledTransactions.isEmpty)
        #expect(fixture.budget.transactions.contains { $0.scheduledTransactionId == "S1" })
    }

    @Test func dueOccurrencesAreEnteredUnapprovedUntilTheScheduleIsInTheFuture() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-10-09", repeats: .every(1, .week))
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        let entered = fixture.budget.transactions.filter { $0.source == .scheduled }
        #expect(entered.map(\.date) == [date("2026-10-09"), date("2026-10-16"), date("2026-10-23")])
        #expect(entered.allSatisfy { !$0.approved })
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.nextDate == date("2026-10-30"))
        #expect(fixture.budget.errorState(of: entered[0]).level == .forReview)
    }

    @Test func dueOnceScheduleIsEnteredAndRemovedButAFutureOneStays() throws {
        var fixture = TestBudget()
        try schedule(&fixture, id: "PAST", on: "2026-10-20", repeats: .once)
        try schedule(&fixture, id: "FUTURE", on: "2026-10-24", repeats: .once)
        try fixture.budget.apply(.enterDueScheduledTransactions(today: october23))
        #expect(fixture.budget.scheduledTransactions.map(\.id) == ["FUTURE"])
        #expect(fixture.budget.transactions.filter { $0.source == .scheduled }.count == 1)
    }

    @Test func enteredTransferCreatesItsCounterpart() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-10-20", repeats: .monthly, amount: -200, target: fixture.tagesgeld)
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
                ScheduledSave(transaction: transaction, repeats: .yearly, payeeName: "Markt", isNew: true)))
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
        try schedule(&fixture, on: "2026-11-02", repeats: .every(2, .week))
        try fixture.budget.apply(.skipScheduledTransactions(["S1"]))
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.nextDate == date("2026-11-16"))
    }

    @Test func skippingAOnceScheduleRemovesIt() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", repeats: .once)
        try fixture.budget.apply(.skipScheduledTransactions(["S1"]))
        #expect(fixture.budget.scheduledTransactions.isEmpty)
        #expect(!fixture.budget.transactions.contains { $0.scheduledTransactionId == "S1" })
    }

    @Test func deleteRemovesTheScheduleAndKeepsItsPayee() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", repeats: .monthly, payee: "Nur Geplant")
        try fixture.budget.apply(.deleteScheduledTransactions(["S1"]))
        #expect(fixture.budget.scheduledTransactions.isEmpty)
        #expect(fixture.budget.payees.contains { $0.name == "Nur Geplant" })
    }

    @Test func moveRefusesATransferIntoTheTargetAccount() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", repeats: .monthly, target: fixture.tagesgeld)
        #expect(throws: BudgetError.transferIntoMoveTarget("Tagesgeld")) {
            try fixture.budget.apply(.moveScheduledTransactions(["S1"], toAccount: fixture.tagesgeld))
        }
        try fixture.budget.apply(.moveScheduledTransactions(["S1"], toAccount: fixture.depot))
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.accountId == fixture.depot)
    }

    @Test func monthlyStepsKeepTheMonthsLastDay() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2027-01-31", repeats: .monthly)
        try fixture.budget.apply(.enterDueScheduledTransactions(today: date("2027-03-28")))
        let entered = fixture.budget.transactions.filter { $0.source == .scheduled }
        #expect(entered.map(\.date).sorted() == [date("2027-01-31"), date("2027-02-28"), date("2027-03-28")])
        #expect(fixture.budget.scheduledTransaction(withId: "S1")?.nextDate == date("2027-04-28"))
    }

    @Test func aScheduleRoundTripsItsRepeatThroughItsRow() throws {
        for repeats in [Repeat.once, .every(2, .week), .yearly] {
            let scheduled = ScheduledTransaction(
                id: "S", accountId: "A", nextDate: october23, repeats: repeats, amount: -10)
            let row = scheduled.row
            #expect(row["repeat_unit"] == .of(repeats.unit?.rawValue))
            #expect(row["repeat_every"] == .of(repeats.count))
            #expect(ScheduledTransaction(id: "S", row: row, resolve: SuccessorChain([:]))?.repeats == repeats)
        }
    }

    @Test func changingTheRepeatWritesUnitAndCountWithOneClock() throws {
        var fixture = TestBudget()
        try schedule(&fixture, on: "2026-11-02", repeats: .every(2, .week))
        let database = try BudgetDatabase()
        try database.save(fixture.budget, over: nil, now: Date())
        let before = fixture.budget
        let sent = Set(try database.outbox())
        fixture.budget.scheduledTransactions[0].repeats = .every(2, .month)

        try database.save(fixture.budget, over: before, now: Date())

        let written = try database.outbox().filter { !sent.contains($0) }
        #expect(written.map(\.column).sorted() == ["repeat_every", "repeat_unit"])
        #expect(Set(written.map(\.clock)).count == 1)
    }

    @Test func aUnitWithoutItsCountStepsByOne() throws {
        let row: SyncRow = [
            "account_id": .text("A"), "next_date": .date(october23), "amount": .cents(-10),
            "repeat_unit": .text("week"),
        ]
        #expect(ScheduledTransaction(id: "S", row: row, resolve: SuccessorChain([:]))?.repeats == .every(1, .week))
    }

    @Test func aScheduleWithAnUnknownUnitIsSkipped() throws {
        let row: SyncRow = [
            "account_id": .text("A"), "next_date": .date(october23), "amount": .cents(-10),
            "repeat_unit": .text("day"), "repeat_every": .integer(3),
        ]
        #expect(ScheduledTransaction(id: "S", row: row, resolve: SuccessorChain([:])) == nil)
    }

    @Test func schedulesThatCannotBeAddedAsTheyAreAreEnteredPlain() throws {
        var fixture = TestBudget()
        fixture.budget.scheduledTransactions = [
            ScheduledTransaction(
                id: "OWN", accountId: fixture.girokonto, nextDate: date("2026-10-20"), repeats: .once,
                payeeId: EntityID.transferPayee(accountId: fixture.girokonto), amount: -5),
            ScheduledTransaction(
                id: "UNEVEN", accountId: fixture.girokonto, nextDate: date("2026-10-21"), repeats: .once,
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
}
