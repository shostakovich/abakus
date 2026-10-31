import Testing

@testable import AbakusCore

@Suite struct TransferTests {
    @Test func transferCreatesTheOtherSide() throws {
        var fixture = TestBudget()
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -200, memo: "Sparen")
        let source = try #require(fixture.budget.transaction(withId: "TR"))
        let counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR")))
        #expect(source.transferTransactionId == EntityID.transferCounterpart(of: "TR"))
        #expect(source.payeeId == EntityID.transferPayee(accountId: "TAGES"))
        #expect(counterpart.accountId == fixture.tagesgeld)
        #expect(counterpart.payeeId == EntityID.transferPayee(accountId: fixture.girokonto))
        #expect(counterpart.transferTransactionId == "TR")
        #expect(counterpart.amount == 200)
        #expect(counterpart.memo == "Sparen")
        #expect(counterpart.date == source.date)
        #expect(fixture.budget.payeeName(of: counterpart) == "Transfer : Girokonto")
    }

    @Test func counterpartDoesNotCopyCategoryOrClearedState() throws {
        var fixture = TestBudget()
        let transaction = Transaction(
            id: "TR", accountId: fixture.girokonto, date: october23, categoryId: fixture.groceries, amount: -50,
            cleared: .cleared
        ).transferring(to: fixture.depot)
        try fixture.budget.apply(.addTransaction(transaction))
        let counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR")))
        #expect(counterpart.categoryId == nil)
        #expect(counterpart.cleared == .uncleared)
    }

    @Test func typedTransferPayeeResolvesTheAccount() throws {
        var fixture = TestBudget()
        let transaction = Transaction(id: "TR", accountId: fixture.girokonto, date: october23, amount: -10)
        try fixture.budget.apply(.addTransaction(transaction, payeeName: "transfer: tagesgeld"))
        #expect(
            fixture.budget.transaction(withId: "TR")?.payeeId == EntityID.transferPayee(accountId: fixture.tagesgeld))
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR"))?.amount == 10)
    }

    @Test func transferToTheSameAccountIsRefused() {
        var fixture = TestBudget()
        #expect(throws: BudgetError.transferToSameAccount) {
            _ = try fixture.transfer(from: fixture.girokonto, to: fixture.girokonto, -10)
        }
    }

    @Test func unknownTransferAccountIsRefused() {
        var fixture = TestBudget()
        let transaction = Transaction(accountId: fixture.girokonto, date: october23, amount: -10)
        #expect(throws: BudgetError.invalidTransferPayee("Transfer : Nowhere")) {
            try fixture.budget.apply(.addTransaction(transaction, payeeName: "Transfer : Nowhere"))
        }
    }

    @Test func editingSyncsAmountDateAndMemo() throws {
        var fixture = TestBudget()
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -200)
        var source = try #require(fixture.budget.transaction(withId: "TR"))
        source.amount = -250
        source.date = date("2026-10-15")
        source.memo = "Mehr"
        try fixture.budget.apply(.updateTransaction(source))
        let counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR")))
        #expect(counterpart.amount == 250)
        #expect(counterpart.date == date("2026-10-15"))
        #expect(counterpart.memo == "Mehr")
    }

    @Test func editingTheCounterpartSyncsBack() throws {
        var fixture = TestBudget()
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -200)
        var counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR")))
        counterpart.amount = 300
        try fixture.budget.apply(.updateTransaction(counterpart))
        #expect(fixture.budget.transaction(withId: "TR")?.amount == -300)
    }

    @Test func changingTheTargetMovesTheCounterpart() throws {
        var fixture = TestBudget()
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -200)
        let source = try #require(fixture.budget.transaction(withId: "TR"))
        try fixture.budget.apply(.updateTransaction(source, payeeName: "Transfer : Depot"))
        let counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR")))
        #expect(counterpart.accountId == fixture.depot)
        #expect(fixture.budget.transactions(inAccount: fixture.tagesgeld).count == 1)
    }

    @Test func movingTheSourceRetargetsTheCounterpart() throws {
        var fixture = TestBudget()
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -200)
        var source = try #require(fixture.budget.transaction(withId: "TR"))
        source.accountId = fixture.depot
        try fixture.budget.apply(.updateTransaction(source))
        let counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR")))
        #expect(counterpart.payeeId == EntityID.transferPayee(accountId: fixture.depot))
        #expect(fixture.budget.payeeName(of: counterpart) == "Transfer : Depot")
    }

    @Test func replacingTheTransferPayeeDeletesTheCounterpart() throws {
        var fixture = TestBudget()
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -200)
        let source = try #require(fixture.budget.transaction(withId: "TR"))
        try fixture.budget.apply(.updateTransaction(source, payeeName: "REWE"))
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR")) == nil)
        let updated = try #require(fixture.budget.transaction(withId: "TR"))
        #expect(!fixture.budget.isTransfer(updated))
        #expect(updated.transferTransactionId == nil)
        #expect(fixture.budget.payeeName(of: updated) == "REWE")
    }

    @Test func deletingEitherSideDeletesBoth() throws {
        var fixture = TestBudget()
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -200)
        try fixture.budget.apply(.deleteTransactions([EntityID.transferCounterpart(of: "TR")]))
        #expect(fixture.budget.transaction(withId: "TR") == nil)
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR")) == nil)
    }

    @Test func approvingASideApprovesTheOther() throws {
        var fixture = TestBudget()
        let transaction = Transaction(
            id: "TR", accountId: fixture.girokonto, date: october23, amount: -10, approved: false
        ).transferring(to: fixture.tagesgeld)
        try fixture.budget.apply(.addTransaction(transaction))
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR"))?.approved == false)
        var source = try #require(fixture.budget.transaction(withId: "TR"))
        source.approved = true
        try fixture.budget.apply(.updateTransaction(source))
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "TR"))?.approved == true)
    }
}

@Suite struct SplitTransferTests {
    private func splitWithTransfer(_ fixture: inout TestBudget) throws {
        let parent = Transaction(
            id: "SPLIT", accountId: fixture.girokonto, date: october23, amount: -80,
            subtransactions: [
                Subtransaction(
                    id: "SUB1", transactionId: "SPLIT", amount: -30, categoryId: fixture.groceries),
                Subtransaction(
                    id: "SUB2", transactionId: "SPLIT", amount: -50, memo: "Sparen"
                ).transferring(to: fixture.tagesgeld),
            ])
        try fixture.budget.apply(.addTransaction(parent, payeeName: "Kaufland"))
    }

    @Test func splitLineTransferCreatesACounterpart() throws {
        var fixture = TestBudget()
        try splitWithTransfer(&fixture)
        let split = try #require(fixture.budget.transaction(withId: "SPLIT"))
        #expect(split.categoryId == nil)
        #expect(split.subtransactions[1].transferTransactionId == EntityID.transferCounterpart(of: "SUB2"))
        let counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "SUB2")))
        #expect(counterpart.accountId == fixture.tagesgeld)
        #expect(counterpart.amount == 50)
        #expect(counterpart.memo == "Sparen")
        #expect(fixture.budget.isTransferFromSplit(counterpart))
    }

    @Test func counterpartOfASplitLineKeepsItsAmountAndPayee() throws {
        var fixture = TestBudget()
        try splitWithTransfer(&fixture)
        var counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "SUB2")))
        counterpart.amount = 60
        #expect(throws: BudgetError.transferFromSplitAmountLocked) {
            try fixture.budget.apply(.updateTransaction(counterpart))
        }
        let original = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "SUB2")))
        #expect(throws: BudgetError.transferFromSplitPayeeLocked) {
            try fixture.budget.apply(.updateTransaction(original, payeeName: "REWE"))
        }
    }

    @Test func movingTheCounterpartDateMovesTheSplit() throws {
        var fixture = TestBudget()
        try splitWithTransfer(&fixture)
        var counterpart = try #require(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "SUB2")))
        counterpart.date = date("2026-10-25")
        counterpart.memo = "Neu"
        try fixture.budget.apply(.updateTransaction(counterpart))
        let split = try #require(fixture.budget.transaction(withId: "SPLIT"))
        #expect(split.date == date("2026-10-25"))
        #expect(split.subtransactions[1].memo == "Neu")
    }

    @Test func deletingTheCounterpartAloneIsSkipped() throws {
        var fixture = TestBudget()
        try splitWithTransfer(&fixture)
        try fixture.budget.apply(.deleteTransactions([EntityID.transferCounterpart(of: "SUB2")]))
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "SUB2")) != nil)
    }

    @Test func deletingTheSplitDeletesItsTransferCounterparts() throws {
        var fixture = TestBudget()
        try splitWithTransfer(&fixture)
        try fixture.budget.apply(.deleteTransactions(["SPLIT"]))
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "SUB2")) == nil)
    }

    @Test func removingTheSplitLineDeletesItsCounterpart() throws {
        var fixture = TestBudget()
        try splitWithTransfer(&fixture)
        var split = try #require(fixture.budget.transaction(withId: "SPLIT"))
        split.subtransactions.removeLast()
        split.amount = -30
        try fixture.budget.apply(.updateTransaction(split))
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "SUB2")) == nil)
    }

    @Test func editingASplitKeepsItsTransferLinks() throws {
        var fixture = TestBudget()
        try splitWithTransfer(&fixture)
        var split = try #require(fixture.budget.transaction(withId: "SPLIT"))
        split.subtransactions[1].transferTransactionId = nil
        split.subtransactions[1].amount = -40
        split.subtransactions[0].amount = -40
        try fixture.budget.apply(.updateTransaction(split))
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "SUB2"))?.amount == 40)
        #expect(fixture.budget.transactions(inAccount: fixture.tagesgeld).count == 2)
    }

    @Test func splitAmountsMustAddUp() {
        var fixture = TestBudget()
        let parent = Transaction(
            accountId: fixture.girokonto, date: october23, amount: -80,
            subtransactions: [Subtransaction(transactionId: "", amount: -30)])
        #expect(throws: BudgetError.splitAmountMismatch) { try fixture.budget.apply(.addTransaction(parent)) }
    }

    @Test func aSplitCannotBeATransfer() {
        var fixture = TestBudget()
        let parent = Transaction(
            accountId: fixture.girokonto, date: october23, amount: -30,
            subtransactions: [Subtransaction(transactionId: "", amount: -30)]
        ).transferring(to: fixture.tagesgeld)
        #expect(throws: BudgetError.splitCannotBeTransfer) { try fixture.budget.apply(.addTransaction(parent)) }
    }
}

@Suite struct TransactionCommandTests {
    @Test func reconcilingApprovesTheTransaction() throws {
        var fixture = TestBudget()
        let transaction = Transaction(
            id: "X", accountId: fixture.girokonto, date: october23, amount: -1, approved: false)
        try fixture.budget.apply(.addTransaction(transaction))
        try fixture.budget.apply(.setCleared(["X"], .reconciled))
        #expect(fixture.budget.transaction(withId: "X")?.cleared == .reconciled)
        #expect(fixture.budget.transaction(withId: "X")?.approved == true)
    }

    @Test func typedPayeesAreCreatedOnceCaseInsensitively() throws {
        var fixture = TestBudget()
        _ = try fixture.add(fixture.girokonto, -1, payee: "REWE")
        _ = try fixture.add(fixture.girokonto, -2, payee: "rewe")
        #expect(fixture.budget.payees.count { $0.name.lowercased() == "rewe" } == 1)
    }

    @Test func unusedPayeesStay() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -1, payee: "Einmalig")
        let other = try fixture.add(fixture.girokonto, -2, payee: "Zweimalig")
        try fixture.budget.apply(.deleteTransactions([id]))
        var edited = try #require(fixture.budget.transaction(withId: other))
        edited.memo = "Brot"
        try fixture.budget.apply(.updateTransaction(edited, payeeName: "Andere"))
        #expect(fixture.budget.payees.contains { $0.name == "Einmalig" })
        #expect(fixture.budget.payees.contains { $0.name == "Zweimalig" })
    }

    @Test func updatingAMissingTransactionFails() {
        var fixture = TestBudget()
        let ghost = Transaction(id: "GHOST", accountId: fixture.girokonto, date: october23, amount: 1)
        #expect(throws: BudgetError.transactionNotFound("GHOST")) {
            try fixture.budget.apply(.updateTransaction(ghost))
        }
    }
}
