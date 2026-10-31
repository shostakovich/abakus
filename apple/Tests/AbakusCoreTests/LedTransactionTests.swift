import AbakusCore
import Foundation
import Testing

@Suite struct LedTransactionTests {
    private func led(
        _ test: inout TestBudget, _ amount: Decimal = -30, payee: String = "Kasse",
        by leader: TransactionLeader = .kasse
    ) throws -> String {
        let id = try test.add(test.girokonto, amount, payee: payee)
        test.budget.transactions[test.budget.transactions.firstIndex { $0.id == id }!].ledBy = leader
        return id
    }

    private func save(_ transaction: Transaction, payeeName: String? = nil) -> BudgetCommand {
        .saveTransaction(TransactionSave(transaction: transaction, payeeName: payeeName, isNew: false))
    }

    @Test func aTransactionIsLedByItsOwnLeaderOrItsCounterparts() throws {
        var test = TestBudget()
        let plain = try test.add(test.girokonto, -5)
        let expense = try led(&test, by: .depot)
        let transfer = try test.transfer(from: test.girokonto, to: test.tagesgeld, -50)
        let counterpart = EntityID.transferCounterpart(of: transfer)
        test.budget.transactions[test.budget.transactions.firstIndex { $0.id == counterpart }!].ledBy = .kasse
        #expect(!test.budget.isLed(plain))
        #expect(test.budget.leader(of: expense) == .depot)
        #expect(test.budget.leader(of: transfer) == .kasse)
        #expect(test.budget.leader(of: counterpart) == .kasse)
        #expect(test.budget.ledTransactionIds == [expense, transfer, counterpart])
    }

    @Test func itsAmountDateAccountAndPayeeCannotChange() throws {
        var test = TestBudget()
        let id = try led(&test)
        _ = try test.add(test.girokonto, -8, payee: "Kasse")
        let original = try #require(test.budget.transaction(withId: id))
        var edits: [(Transaction, String?)] = []
        var amount = original
        amount.amount = -31
        edits.append((amount, nil))
        var day = original
        day.date = date("2026-10-11")
        edits.append((day, nil))
        var account = original
        account.accountId = test.tagesgeld
        edits.append((account, nil))
        edits.append((original, "Pizzeria"))
        edits.append((original, "Transfer : Tagesgeld"))
        for (edited, payeeName) in edits {
            #expect(throws: BudgetError.ledTransaction(.kasse)) {
                try test.budget.applying(save(edited, payeeName: payeeName))
            }
        }
    }

    @Test func itsCategoryMemoClearedStateAndApprovalCanChange() throws {
        var test = TestBudget()
        let id = try led(&test)
        var edited = try #require(test.budget.transaction(withId: id))
        edited.categoryId = test.groceries
        edited.memo = "Pizza"
        var budget = try test.budget.applying(save(edited, payeeName: "Kasse"))
        try budget.apply(.setCleared([id], .cleared))
        try budget.apply(.approveTransactions([id]))
        let saved = try #require(budget.transaction(withId: id))
        #expect(saved.categoryId == test.groceries)
        #expect(saved.memo == "Pizza")
        #expect(saved.cleared == .cleared)
        #expect(saved.ledBy == .kasse)
    }

    @Test func aSaveKeepsItsPayeeWhenAnotherPayeeHasTheSameName() throws {
        var test = TestBudget()
        let id = try led(&test)
        test.budget.payees.insert(Payee(id: "TWIN", name: "Kasse"), at: 0)
        var edited = try #require(test.budget.transaction(withId: id))
        edited.memo = "Pizza"
        let budget = try test.budget.applying(save(edited, payeeName: "Kasse"))
        #expect(budget.transaction(withId: id)?.payeeId == edited.payeeId)
    }

    @Test func itCannotBeSplit() throws {
        var test = TestBudget()
        let id = try led(&test)
        var edited = try #require(test.budget.transaction(withId: id))
        edited.subtransactions = [
            Subtransaction(transactionId: id, amount: -20, categoryId: test.groceries),
            Subtransaction(transactionId: id, amount: -10, categoryId: test.groceries),
        ]
        #expect(throws: BudgetError.ledTransaction(.kasse)) { try test.budget.applying(save(edited)) }
    }

    @Test func deletingAndMovingASelectionLeaveItOut() throws {
        var test = TestBudget()
        let id = try led(&test)
        let own = try test.add(test.girokonto, -5)
        let deleted = try test.budget.applying(.deleteTransactions([id, own]))
        #expect(deleted.transaction(withId: id) != nil)
        #expect(deleted.transaction(withId: own) == nil)
        let moved = try test.budget.applying(.moveTransactions([id, own], toAccountId: test.tagesgeld))
        #expect(moved.transaction(withId: id)?.accountId == test.girokonto)
        #expect(moved.transaction(withId: own)?.accountId == test.tagesgeld)
    }

    @Test func deletingASplitWhosePartLeadsToALedTransferLeavesItOut() throws {
        var test = TestBudget()
        let split = Transaction(
            id: "SPLIT", accountId: test.girokonto, date: date("2026-10-15"), amount: -50,
            subtransactions: [
                Subtransaction(id: "L1", transactionId: "SPLIT", amount: -30, categoryId: test.groceries),
                Subtransaction(id: "L2", transactionId: "SPLIT", amount: -20).transferring(to: test.tagesgeld),
            ])
        try test.budget.apply(.addTransaction(split))
        let counterpart = EntityID.transferCounterpart(of: "L2")
        test.budget.transactions[test.budget.transactions.firstIndex { $0.id == counterpart }!].ledBy = .kasse
        #expect(try test.budget.applying(.deleteTransactions(["SPLIT"])) == test.budget)
        #expect(test.budget.deleteAnalysis(["SPLIT"]).deletable.isEmpty)
    }

    @Test func itCannotMoveToTheScheduler() throws {
        var test = TestBudget()
        let id = try led(&test)
        #expect(throws: BudgetError.ledTransaction(.kasse)) {
            try test.budget.applying(.moveToScheduler(transactionId: id, scheduleId: "S1"))
        }
        let recurring = try test.budget.applying(.makeRecurring(transactionId: id, scheduleId: "S1", today: october23))
        #expect(recurring.transaction(withId: id) != nil)
    }

    @Test func combiningOrRenamingItsPayeeGoesThrough() throws {
        var test = TestBudget()
        let id = try led(&test, payee: "Pizzeria")
        _ = try test.add(test.girokonto, -12, payee: "Pizza Roma")
        let pizzeria = try #require(test.budget.transaction(withId: id)?.payeeId)
        let roma = try #require(test.budget.payee(named: "Pizza Roma")?.id)
        let combined = try test.budget.applying(.combinePayees([pizzeria, roma], name: "Pizza Roma"))
        #expect(combined.transaction(withId: id)?.payeeId == roma)
        let renamed = try test.budget.applying(.renamePayee(payeeId: pizzeria, name: "Pizza Roma"))
        #expect(renamed.transaction(withId: id)?.payeeId == roma)
    }

    @Test func renameRulesDoNotTurnItIntoATransfer() throws {
        var test = TestBudget()
        let id = try led(&test, payee: "Sparen")
        let own = try test.add(test.girokonto, -5, payee: "Sparen")
        let transferPayee = EntityID.transferPayee(accountId: test.tagesgeld)
        try test.budget.apply(
            .setPayeeRenameConditions(
                payeeId: transferPayee, [PayeeRenameCondition(payeeId: transferPayee, operator: .is, text: "Sparen")]))
        let budget = try test.budget.applying(.applyRenameRules(payeeId: transferPayee))
        #expect(budget.payeeName(of: budget.transaction(withId: id)!) == "Sparen")
        #expect(budget.transaction(withId: own)?.payeeId == transferPayee)
    }

    @Test func deleteAnalysisCountsTheLedTransactionsItLeavesOut() throws {
        var test = TestBudget()
        let kasse = try led(&test)
        let depot = try led(&test, by: .depot)
        let own = try test.add(test.girokonto, -5)
        let analysis = test.budget.deleteAnalysis([kasse, depot, own])
        #expect(analysis.deletable == [own])
        #expect(analysis.led == 2)
        #expect(analysis.leaders == [.kasse, .depot])
    }

    @Test func aRefusedCommandLeavesTheBudgetAsItWas() throws {
        var test = TestBudget()
        let id = try led(&test)
        var edited = try #require(test.budget.transaction(withId: id))
        edited.amount = -1
        var budget = test.budget
        #expect(throws: BudgetError.ledTransaction(.kasse)) { try budget.apply(.updateTransaction(edited)) }
        #expect(budget == test.budget)
    }

    @Test func onlyTheServerSetsTheLeader() throws {
        var test = TestBudget()
        let id = try test.add(test.girokonto, -5)
        var edited = try #require(test.budget.transaction(withId: id))
        edited.ledBy = .kasse
        #expect(try test.budget.applying(.updateTransaction(edited)).isLed(id) == false)
        var added = Transaction(id: "NEW", accountId: test.girokonto, date: october23, amount: -1)
        added.ledBy = .depot
        #expect(try test.budget.applying(.addTransaction(added)).isLed("NEW") == false)
    }
}
