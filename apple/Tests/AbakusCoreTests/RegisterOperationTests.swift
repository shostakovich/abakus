import AbakusCore
import Foundation
import Testing

@Suite struct RegisterOperationTests {
    private func applied(_ test: TestBudget, _ command: BudgetCommand) throws -> Budget {
        try test.budget.applying(command)
    }

    @Test func approvingAcceptsTheTransaction() throws {
        var test = TestBudget()
        let id = try test.add(test.girokonto, -5)
        let index = test.budget.transactions.firstIndex { $0.id == id }!
        test.budget.transactions[index].approved = false
        test.budget.transactions[index].source = .bank
        let budget = try applied(test, .approveTransactions([id]))
        #expect(budget.transaction(withId: id)?.approved == true)
        #expect(budget.transaction(withId: id)?.needsApproval == false)
    }

    @Test func togglingClearsAndApprovesUnclearedRows() throws {
        var test = TestBudget()
        let id = try test.add(test.girokonto, -5)
        let index = test.budget.transactions.firstIndex { $0.id == id }!
        test.budget.transactions[index].approved = false
        let budget = try applied(test, .toggleCleared([id]))
        #expect(budget.transaction(withId: id)?.cleared == .cleared)
        #expect(budget.transaction(withId: id)?.approved == true)
    }

    @Test func togglingUnclearsWhenEveryRowIsCleared() throws {
        var test = TestBudget()
        let a = try test.add(test.girokonto, -5, cleared: .cleared)
        let b = try test.add(test.girokonto, -6, cleared: .cleared)
        let budget = try applied(test, .toggleCleared([a, b]))
        #expect(budget.transaction(withId: a)?.cleared == .uncleared)
        #expect(budget.transaction(withId: b)?.cleared == .uncleared)
    }

    @Test func mixedSelectionBecomesCleared() throws {
        var test = TestBudget()
        let a = try test.add(test.girokonto, -5, cleared: .cleared)
        let b = try test.add(test.girokonto, -6)
        let budget = try applied(test, .toggleCleared([a, b]))
        #expect(budget.transaction(withId: a)?.cleared == .cleared)
        #expect(budget.transaction(withId: b)?.cleared == .cleared)
    }

    @Test func reconciledRowsNeverToggle() throws {
        var test = TestBudget()
        let a = try test.add(test.girokonto, -5, cleared: .reconciled)
        let b = try test.add(test.girokonto, -6, cleared: .cleared)
        let budget = try applied(test, .toggleCleared([a, b]))
        #expect(budget.transaction(withId: a)?.cleared == .reconciled)
        #expect(budget.transaction(withId: b)?.cleared == .uncleared)
        #expect(try applied(test, .toggleCleared([a])) == test.budget)
    }

    @Test func bulkCategorizeSkipsSplits() throws {
        var test = TestBudget()
        let plain = try test.add(test.girokonto, -5)
        let split = Transaction(
            id: "SPLIT", accountId: test.girokonto, date: date("2026-10-11"), amount: -10,
            subtransactions: [
                Subtransaction(transactionId: "SPLIT", amount: -4),
                Subtransaction(transactionId: "SPLIT", amount: -6),
            ])
        try test.budget.apply(.addTransaction(split))
        let budget = try applied(test, .categorizeTransactions([plain, "SPLIT"], categoryId: test.groceries))
        #expect(budget.transaction(withId: plain)?.categoryId == test.groceries)
        #expect(budget.transaction(withId: "SPLIT")?.categoryId == nil)
        let cleared = try budget.applying(.categorizeTransactions([plain], categoryId: nil))
        #expect(cleared.transaction(withId: plain)?.categoryId == nil)
    }

    @Test func fillingMissingCategoriesReachesSplitLines() throws {
        var test = TestBudget()
        let split = Transaction(
            id: "SPLIT", accountId: test.girokonto, date: date("2026-10-11"), amount: -10,
            subtransactions: [
                Subtransaction(id: "A", transactionId: "SPLIT", amount: -4, categoryId: test.groceries),
                Subtransaction(id: "B", transactionId: "SPLIT", amount: -6),
            ])
        try test.budget.apply(.addTransaction(split))
        let fuel = test.category("Everyday Expenses", "Fuel")
        let budget = try applied(test, .fillMissingCategory(["SPLIT"], categoryId: fuel))
        #expect(budget.transaction(withId: "SPLIT")?.subtransactions.map(\.categoryId) == [test.groceries, fuel])
    }

    @Test func removingTransferCategoriesFixesErrors() throws {
        var test = TestBudget()
        let id = try test.transfer(from: test.girokonto, to: test.tagesgeld, -50, category: test.groceries)
        #expect(test.budget.errorState(of: test.budget.transaction(withId: id)!).level == .error)
        let budget = try applied(test, .removeTransferCategories([id]))
        #expect(budget.transaction(withId: id)?.categoryId == nil)
        #expect(budget.notifierCounts(forAccount: test.girokonto).errors == 0)
    }

    @Test func movingChangesTheAccountAndUnreconciles() throws {
        var test = TestBudget()
        let id = try test.add(test.girokonto, -5, cleared: .reconciled)
        let budget = try applied(test, .moveTransactions([id], toAccountId: test.tagesgeld))
        #expect(budget.transaction(withId: id)?.accountId == test.tagesgeld)
        #expect(budget.transaction(withId: id)?.cleared == .cleared)
    }

    @Test func movingATransferRetargetsItsCounterpart() throws {
        var test = TestBudget()
        let id = try test.transfer(from: test.girokonto, to: test.depot, -50)
        let budget = try applied(test, .moveTransactions([id], toAccountId: test.tagesgeld))
        let counterpart = budget.transactions.first { $0.transferTransactionId == id }!
        #expect(counterpart.accountId == test.depot)
        #expect(counterpart.payeeId == EntityID.transferPayee(accountId: test.tagesgeld))
        #expect(budget.payeeName(of: counterpart) == "Transfer : Tagesgeld")
    }

    @Test func movingATransferIntoItsTargetFails() throws {
        var test = TestBudget()
        let id = try test.transfer(from: test.girokonto, to: test.depot, -50)
        #expect(throws: BudgetError.self) { try test.budget.applying(.moveTransactions([id], toAccountId: test.depot)) }
        #expect(test.budget.transaction(withId: id)!.transfers(into: test.depot))
    }

    @Test func moveTargetsAreOpenOtherAccountsByName() {
        var test = TestBudget()
        let index = test.budget.accounts.firstIndex { $0.id == test.depot }!
        test.budget.accounts[index].closed = true
        #expect(test.budget.moveTargets(excluding: test.girokonto).map(\.name) == ["Tagesgeld"])
    }

    @Test func restoringPutsTransactionsAndPayeesBack() throws {
        var test = TestBudget()
        let id = try test.add(test.girokonto, -5, payee: "Bäcker")
        let before = test.budget
        let deleted = try applied(test, .deleteTransactions([id]))
        #expect(deleted.transaction(withId: id) == nil)
        let restored = try deleted.applying(
            .restoreTransactions([before.transaction(withId: id)!], payees: before.payees))
        #expect(restored.transaction(withId: id) == before.transaction(withId: id))
        #expect(restored.payeeName(of: restored.transaction(withId: id)!) == "Bäcker")
    }

    @Test func restoringAMoveBringsBackTheAccountTheReconciledStateAndTheTransferTarget() throws {
        var test = TestBudget()
        let id = try test.transfer(from: test.girokonto, to: test.depot, -50)
        try test.budget.apply(.setCleared([id], .reconciled))
        let moved = try applied(test, .moveTransactions([id], toAccountId: test.tagesgeld))
        let restored = try moved.applying(
            .restoreMovedTransactions([
                MovedTransaction(transactionId: id, accountId: test.girokonto, cleared: .reconciled)
            ]))
        let transaction = try #require(restored.transaction(withId: id))
        #expect(transaction.accountId == test.girokonto)
        #expect(transaction.cleared == .reconciled)
        let counterpart = try #require(restored.transactions.first { $0.transferTransactionId == id })
        #expect(counterpart.payeeId == EntityID.transferPayee(accountId: test.girokonto))
    }

    @Test func restoringAMovedScheduleOnlyResetsItsAccount() throws {
        var test = TestBudget()
        let schedule = Transaction(id: "S1", accountId: test.girokonto, date: date("2026-11-02"), amount: -25)
        try test.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: schedule, frequency: .monthly, payeeName: "Rent", isNew: true)))
        let moved = try applied(test, .moveScheduledTransactions(["S1"], toAccount: test.tagesgeld))
        let restored = try moved.applying(
            .restoreMovedTransactions([
                MovedTransaction(transactionId: "S1", accountId: test.girokonto, cleared: .uncleared)
            ]))
        #expect(restored == test.budget)
    }

    @Test func makeRecurringSchedulesMonthlyAfterToday() throws {
        var test = TestBudget()
        let id = try test.add(test.girokonto, -9.99, on: "2026-09-05", payee: "Spotify", cleared: .cleared)
        let budget = try applied(test, .makeRecurring(transactionId: id, scheduleId: "SCHED", today: october23))
        let schedule = try #require(budget.scheduledTransactions.first { $0.id == "SCHED" })
        #expect(schedule.frequency == .monthly)
        #expect(schedule.nextDate == date("2026-11-05"))
        #expect(schedule.cleared == .uncleared)
        #expect(schedule.amount == -9.99)
        #expect(budget.transaction(withId: id) != nil)
    }

    @Test func makeRecurringOnTheSameDayStepsToNextMonth() throws {
        var test = TestBudget()
        let id = try test.add(test.girokonto, -1, on: "2026-10-23")
        let budget = try applied(test, .makeRecurring(transactionId: id, scheduleId: "S", today: october23))
        #expect(budget.scheduledTransactions.first?.nextDate == date("2026-11-23"))
    }

    @Test func moveToSchedulerKeepsTheDateAndDeletesTheOriginal() throws {
        var test = TestBudget()
        let id = try test.add(test.girokonto, -20, on: "2026-12-01", payee: "Versicherung")
        let budget = try applied(test, .moveToScheduler(transactionId: id, scheduleId: "ONCE"))
        let schedule = try #require(budget.scheduledTransactions.first)
        #expect(schedule.frequency == .once)
        #expect(schedule.nextDate == date("2026-12-01"))
        #expect(budget.transaction(withId: id) == nil)
        #expect(budget.payee(withId: schedule.payeeId!)?.name == "Versicherung")
    }

    @Test func schedulingASplitCopiesItsLines() throws {
        var test = TestBudget()
        let split = Transaction(
            id: "SPLIT", accountId: test.girokonto, date: date("2026-12-11"), amount: -10,
            subtransactions: [
                Subtransaction(transactionId: "SPLIT", amount: -4, categoryId: test.groceries),
                Subtransaction(transactionId: "SPLIT", amount: -6),
            ])
        try test.budget.apply(.addTransaction(split))
        let budget = try applied(test, .moveToScheduler(transactionId: "SPLIT", scheduleId: "S"))
        let schedule = try #require(budget.scheduledTransactions.first)
        #expect(schedule.subtransactions.map(\.amount) == [-4, -6])
        #expect(schedule.subtransactions.allSatisfy { $0.transactionId == "S" })
    }

    @Test func renamingAPayeeRenamesEveryTransaction() throws {
        var test = TestBudget()
        let a = try test.add(test.girokonto, -1, payee: "rewe")
        let payeeId = test.budget.transaction(withId: a)!.payeeId!
        let budget = try applied(test, .renamePayee(payeeId: payeeId, name: "REWE Markt"))
        #expect(budget.payeeName(of: budget.transaction(withId: a)!) == "REWE Markt")
    }

    @Test func renamingIntoAnExistingPayeeMerges() throws {
        var test = TestBudget()
        let a = try test.add(test.girokonto, -1, payee: "Rewe")
        _ = try test.add(test.girokonto, -2, payee: "REWE Markt")
        let payeeId = test.budget.transaction(withId: a)!.payeeId!
        let budget = try applied(test, .renamePayee(payeeId: payeeId, name: "rewe markt"))
        #expect(budget.payeeName(of: budget.transaction(withId: a)!) == "REWE Markt")
        #expect(budget.payee(withId: payeeId) == nil)
    }

    @Test func notifierCountsPerLevel() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -5, payee: "Uncategorised")
        _ = try test.transfer(from: test.girokonto, to: test.tagesgeld, -50, category: test.groceries)
        let bank = Transaction(
            accountId: test.girokonto, date: date("2026-10-11"), amount: -1, approved: false, source: .bank)
        try test.budget.apply(.addTransaction(bank, payeeName: "X"))
        let counts = test.budget.notifierCounts(forAccount: test.girokonto)
        #expect(counts.needsCategory == 1)
        #expect(counts.errors == 1)
        #expect(counts.forReview == 1)
        #expect(test.budget.notifierCounts(forAccount: EntityID.allAccounts).needsCategory == 1)
    }

    @Test func deleteAnalysisClassifiesTheSelection() throws {
        var test = TestBudget()
        let reconciled = try test.add(test.girokonto, -5, cleared: .reconciled)
        let transfer = try test.transfer(from: test.girokonto, to: test.tagesgeld, -50)
        let counterpart = test.budget.transactions.first { $0.transferTransactionId == transfer }!.id
        let index = test.budget.transactions.firstIndex { $0.id == counterpart }!
        test.budget.transactions[index].cleared = .reconciled
        let analysis = test.budget.deleteAnalysis([reconciled, transfer])
        #expect(analysis.deletable == [reconciled, transfer])
        #expect(analysis.reconciled == 1)
        #expect(analysis.otherSideReconciled == 1)
        #expect(analysis.transfers == 1)
    }

    @Test func transfersFromSplitsCannotBeDeleted() throws {
        var test = TestBudget()
        let split = Transaction(
            id: "SPLIT", accountId: test.girokonto, date: date("2026-10-11"), amount: -10,
            subtransactions: [
                Subtransaction(
                    id: "A", transactionId: "SPLIT", amount: -4
                ).transferring(to: test.tagesgeld),
                Subtransaction(id: "B", transactionId: "SPLIT", amount: -6, categoryId: test.groceries),
            ])
        try test.budget.apply(.addTransaction(split))
        let counterpart = test.budget.transactions.first {
            $0.accountId == test.tagesgeld && $0.transferSubtransactionId == "A"
        }!
        let analysis = test.budget.deleteAnalysis([counterpart.id, "SPLIT"])
        #expect(analysis.transfersIntoSplits == 1)
        #expect(analysis.deletable == ["SPLIT"])
        #expect(analysis.transfers == 1)
    }
}
