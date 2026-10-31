import Foundation
import Testing

@testable import AbakusCore

@MainActor
@Suite struct SaveTransactionTests {
    @Test func savingANewTransactionAddsItWithItsPayee() throws {
        let store = BudgetStore(budget: TestBudget().budget)
        let new = Transaction(accountId: "GIRO", date: october23, amount: -12)
        try store.perform(.saveTransaction(TransactionSave(transaction: new, payeeName: "Bäcker", isNew: true)))
        let saved = try #require(store.budget.transaction(withId: new.id))
        #expect(store.budget.payeeName(of: saved) == "Bäcker")
    }

    @Test func editingAnUnapprovedTransactionApprovesIt() throws {
        var budget = TestBudget().budget
        let imported = Transaction(
            id: "IMP", accountId: "GIRO", date: october23, amount: -5, approved: false, source: .bank)
        try budget.apply(.addTransaction(imported, payeeName: "Kiosk"))
        var unchanged = try #require(budget.transaction(withId: "IMP"))
        try budget.apply(.saveTransaction(TransactionSave(transaction: unchanged, payeeName: "Kiosk", isNew: false)))
        #expect(budget.transaction(withId: "IMP")?.approved == false)
        unchanged.memo = "Zeitung"
        try budget.apply(.saveTransaction(TransactionSave(transaction: unchanged, payeeName: "Kiosk", isNew: false)))
        #expect(budget.transaction(withId: "IMP")?.approved == true)
    }

    @Test func clearedStateIsNotTakenFromTheClone() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10, cleared: .cleared)
        var clone = try #require(fixture.budget.transaction(withId: id))
        clone.cleared = .uncleared
        try fixture.budget.apply(.saveTransaction(TransactionSave(transaction: clone, payeeName: nil, isNew: false)))
        #expect(fixture.budget.transaction(withId: id)?.cleared == .cleared)
    }

    @Test func savingRemembersTheCategoryAndTheLastTransactionFillsMemoAndAmount() throws {
        var fixture = TestBudget()
        let new = Transaction(
            accountId: "GIRO", date: october23, categoryId: fixture.groceries, memo: "Wocheneinkauf", amount: -42)
        try fixture.budget.apply(.saveTransaction(TransactionSave(transaction: new, payeeName: "Edeka", isNew: true)))
        let payee = try #require(fixture.budget.payees.first { $0.name == "Edeka" })
        #expect(payee.lastCategoryId == fixture.groceries)
        let fill = fixture.budget.autoFill(
            payeeName: "Edeka", accountId: "GIRO", settings: AutoFillSettings(memo: true, amount: true))
        #expect(fill?.memo == "Wocheneinkauf")
        #expect(fill?.amount == -42)
        #expect(fixture.budget.autoFillCategory(payeeName: "edeka", accountId: "GIRO") == fixture.groceries)
        #expect(fixture.budget.autoFillCategory(payeeName: "Edeka", accountId: "DEPOT") == nil)
    }

    @Test func emptySubRowsAreDroppedAndOneLineCollapses() throws {
        var fixture = TestBudget()
        let id = "SPLIT"
        let subs = [
            Subtransaction(transactionId: id, amount: 0, categoryId: fixture.groceries),
            Subtransaction(transactionId: id, amount: 0),
        ]
        let new = Transaction(
            id: id, accountId: "GIRO", date: october23, categoryId: EntityID.splitCategory, amount: -20,
            subtransactions: subs)
        try fixture.budget.apply(.saveTransaction(TransactionSave(transaction: new, payeeName: "REWE", isNew: true)))
        let saved = try #require(fixture.budget.transaction(withId: id))
        #expect(!saved.isSplit)
        #expect(saved.categoryId == fixture.groceries)
        #expect(saved.amount == -20)
    }

    @Test func splitWithoutLinesBecomesUncategorized() {
        let transaction = Transaction(
            accountId: "GIRO", date: october23, categoryId: EntityID.splitCategory, amount: -5,
            subtransactions: [Subtransaction(transactionId: "X", amount: 0)])
        let normalized = SplitRules.normalized(transaction, parentPayeeName: "", in: TestBudget().budget)
        #expect(normalized.categoryId == nil)
        #expect(!normalized.isSplit)
    }

    @Test func singleLineStaysASplitWhenBothHaveAmounts() {
        let transaction = Transaction(
            accountId: "GIRO", date: october23, categoryId: EntityID.splitCategory, amount: -5,
            subtransactions: [Subtransaction(transactionId: "X", amount: -5, categoryId: "C")])
        #expect(SplitRules.normalized(transaction, parentPayeeName: "", in: TestBudget().budget).isSplit)
    }

    @Test func singleTransferLineCollapsesIntoATransferWhenThePayeeIsEmpty() throws {
        var fixture = TestBudget()
        let new = Transaction(
            id: "S", accountId: "GIRO", date: october23, categoryId: EntityID.splitCategory, amount: 0,
            subtransactions: [Subtransaction(transactionId: "S", amount: -30).transferring(to: "TAGES")])
        try fixture.budget.apply(.saveTransaction(TransactionSave(transaction: new, payeeName: "", isNew: true)))
        let saved = try #require(fixture.budget.transaction(withId: "S"))
        #expect(saved.payeeId == EntityID.transferPayee(accountId: "TAGES"))
        #expect(saved.amount == -30)
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "S"))?.amount == 30)
    }

    @Test func aCollapsedTransferLineStaysATransferInBothSavePaths() throws {
        var fixture = TestBudget()
        let split = Transaction(
            id: "S", accountId: "GIRO", date: date("2026-11-02"), categoryId: EntityID.splitCategory, amount: 0,
            subtransactions: [
                Subtransaction(transactionId: "S", amount: -100).transferring(to: "TAGES"),
                Subtransaction(transactionId: "S", amount: 0),
            ])
        let normalized = SplitRules.normalized(split, parentPayeeName: "", in: fixture.budget)
        try fixture.budget.apply(.saveTransaction(TransactionSave(transaction: normalized, payeeName: "", isNew: true)))
        #expect(fixture.budget.transaction(withId: "S")?.payeeId == EntityID.transferPayee(accountId: "TAGES"))
        #expect(fixture.budget.transaction(withId: EntityID.transferCounterpart(of: "S"))?.amount == 100)

        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: normalized, frequency: .monthly, payeeName: "", isNew: true)))
        #expect(fixture.budget.scheduledTransaction(withId: "S")?.payeeId == EntityID.transferPayee(accountId: "TAGES"))
    }

    @Test func autoDistributeAllocatesProportionallyAndRoundsIntoTheLargestLine() {
        let transaction = Transaction(
            accountId: "GIRO", date: october23, categoryId: EntityID.splitCategory, amount: -110,
            subtransactions: [
                Subtransaction(transactionId: "X", amount: -60),
                Subtransaction(transactionId: "X", amount: -40),
            ])
        #expect(SplitRules.unassigned(transaction) == -10)
        let distributed = SplitRules.autoDistribute(transaction)
        #expect(distributed.subtransactions.map(\.amount) == [-66, -44])
        let uneven = Transaction(
            accountId: "GIRO", date: october23, amount: -10,
            subtransactions: (0..<3).map { _ in Subtransaction(transactionId: "X", amount: 0) })
        let shares = SplitRules.autoDistribute(uneven).subtransactions.map(\.amount)
        #expect(Amount.sum(shares) == -10)
        #expect(shares.filter { $0 == decimal("-3.33") }.count == 2)
    }

    @Test func adjustOriginalSetsTheTotalToTheSumOfTheLines() {
        let transaction = Transaction(
            accountId: "GIRO", date: october23, amount: -110,
            subtransactions: [Subtransaction(transactionId: "X", amount: -60)])
        #expect(SplitRules.adjustOriginal(transaction).amount == -60)
    }

    @Test func changingThePayeeOfTheOnlyUserRenamesThePayee() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10, payee: "Rewe")
        let payeeId = try #require(fixture.budget.transaction(withId: id)?.payeeId)
        let clone = try #require(fixture.budget.transaction(withId: id))
        #expect(
            fixture.budget.payeeRenameCheck(original: clone, newPayeeName: "REWE Markt", categoryId: nil)
                == .renameSilently)
        try fixture.budget.apply(
            .saveTransaction(TransactionSave(transaction: clone, payeeName: "REWE Markt", isNew: false)))
        #expect(fixture.budget.transaction(withId: id)?.payeeId == payeeId)
        #expect(fixture.budget.payee(withId: payeeId)?.name == "REWE Markt")
    }

    @Test func renameCheckAsksWhenOthersUseThePayee() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10, payee: "Rewe")
        _ = try fixture.add(fixture.girokonto, -11, payee: "Rewe")
        _ = try fixture.add(fixture.girokonto, -12, payee: "Rewe", category: fixture.groceries)
        let clone = try #require(fixture.budget.transaction(withId: id))
        let check = fixture.budget.payeeRenameCheck(
            original: clone, newPayeeName: "REWE Markt", categoryId: fixture.groceries)
        #expect(
            check
                == .ask(
                    oldName: "Rewe", newName: "REWE Markt", matches: 2, uncategorized: 1,
                    categoryName: "Everyday Expenses: Groceries"))
        #expect(fixture.budget.payeeRenameCheck(original: clone, newPayeeName: "rewe", categoryId: nil) == nil)
        #expect(
            fixture.budget.payeeRenameCheck(original: clone, newPayeeName: "Transfer : Depot", categoryId: nil) == nil)
    }

    @Test func renameCheckAsksWhenOnlySplitPartsElsewhereUseThePayee() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10, payee: "Bäcker")
        let split = Transaction(
            id: "S", accountId: fixture.girokonto, date: october23, categoryId: EntityID.splitCategory,
            amount: -50,
            subtransactions: [
                Subtransaction(id: "L1", transactionId: "S", amount: -30),
                Subtransaction(id: "L2", transactionId: "S", amount: -20),
            ])
        try fixture.budget.apply(
            .saveTransaction(
                TransactionSave(transaction: split, payeeName: "Kaufland", subPayeeNames: ["L1": "Bäcker"], isNew: true)
            ))
        let clone = try #require(fixture.budget.transaction(withId: id))
        #expect(
            fixture.budget.payeeRenameCheck(original: clone, newPayeeName: "Bäckerei Müller", categoryId: nil)
                == .ask(oldName: "Bäcker", newName: "Bäckerei Müller", matches: 1, uncategorized: 0, categoryName: nil))
        try fixture.budget.apply(
            .saveTransaction(TransactionSave(transaction: clone, payeeName: "Bäckerei Müller", isNew: false)))
        let part = try #require(fixture.budget.transaction(withId: "S")?.subtransactions.first)
        #expect(fixture.budget.payeeName(of: part) == "Bäcker")
    }

    @Test func renameAndCategorizeUpdatesTheMatches() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10, payee: "Rewe")
        let other = try fixture.add(fixture.girokonto, -11, payee: "Rewe")
        var clone = try #require(fixture.budget.transaction(withId: id))
        clone.categoryId = fixture.groceries
        let save = TransactionSave(
            transaction: clone, payeeName: "REWE Markt", isNew: false,
            payeeRename: PayeeRename(choice: .renameAndCategorize))
        try fixture.budget.apply(.saveTransaction(save))
        let renamed = try #require(fixture.budget.transaction(withId: other))
        #expect(fixture.budget.payeeName(of: renamed) == "REWE Markt")
        #expect(renamed.categoryId == fixture.groceries)
    }

    @Test func justRenamingLeavesTheMatchesUncategorized() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10, payee: "Rewe")
        let other = try fixture.add(fixture.girokonto, -11, payee: "Rewe")
        var clone = try #require(fixture.budget.transaction(withId: id))
        clone.categoryId = fixture.groceries
        let save = TransactionSave(
            transaction: clone, payeeName: "REWE Markt", isNew: false, payeeRename: PayeeRename(choice: .rename))
        try fixture.budget.apply(.saveTransaction(save))
        let renamed = try #require(fixture.budget.transaction(withId: other))
        #expect(fixture.budget.payeeName(of: renamed) == "REWE Markt")
        #expect(renamed.categoryId == nil)
    }

    @Test func leavingThemAloneOnlyChangesThisTransaction() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10, payee: "Rewe")
        let other = try fixture.add(fixture.girokonto, -11, payee: "Rewe")
        let clone = try #require(fixture.budget.transaction(withId: id))
        let save = TransactionSave(
            transaction: clone, payeeName: "Lidl", isNew: false,
            payeeRename: PayeeRename(choice: .leave, stopAsking: true))
        try fixture.budget.apply(.saveTransaction(save))
        let untouched = try #require(fixture.budget.transaction(withId: other))
        #expect(fixture.budget.payeeName(of: untouched) == "Rewe")
        #expect(fixture.budget.payee(withId: untouched.payeeId ?? "")?.hidden == true)
        #expect(fixture.budget.payeeName(of: fixture.budget.transaction(withId: id)!) == "Lidl")
    }

    @Test func properPayeeNameUsesTheStoredCapitalization() throws {
        var fixture = TestBudget()
        _ = try fixture.add(fixture.girokonto, -10, payee: "Walmart")
        #expect(fixture.budget.properPayeeName("walmart") == "Walmart")
        #expect(fixture.budget.properPayeeName("transfer:tagesgeld") == "Transfer : Tagesgeld")
        #expect(fixture.budget.properPayeeName("Neu") == "Neu")
    }

    @Test func payeeLookupsIgnoreCaseAndSkipTransfersUnlessAsked() throws {
        var fixture = TestBudget()
        _ = try fixture.add(fixture.girokonto, -10, payee: "Walmart")
        #expect(fixture.budget.payee(named: " walmart ")?.name == "Walmart")
        #expect(fixture.budget.payee(named: "Transfer : Tagesgeld") == nil)
        let transfer = fixture.budget.payee(named: "transfer : tagesgeld", includingTransfers: true)
        #expect(transfer?.transferAccountId == "TAGES")
        #expect(Payee.sameName("REWE ", " rewe"))
        #expect(!EntityID.isCategorized(EntityID.uncategorizedCategory) && EntityID.isCategorized(fixture.groceries))
    }

    @Test func payeeLookupsIgnoreEmojiSharpSAndHowUmlautsAreWritten() throws {
        var fixture = TestBudget()
        _ = try fixture.add(fixture.girokonto, -10, payee: "🥨 Bäckerei Straße")
        #expect(fixture.budget.payee(named: "bäckerei strasse")?.name == "🥨 Bäckerei Straße")
        #expect(fixture.budget.payee(named: "BA\u{308}CKEREI STRASSE")?.name == "🥨 Bäckerei Straße")
        #expect(fixture.budget.properPayeeName("backerei strasse") == "backerei strasse")
        _ = try fixture.add(fixture.girokonto, -2, payee: "baeckerei strasse")
        #expect(fixture.budget.payees.count { $0.name.contains("strasse") || $0.name.contains("Straße") } == 2)
    }
}

@Suite struct ReconciledWarningTests {
    @Test func reconciledTransactionWarnsAboutAccountAmountOrDate() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10, cleared: .reconciled)
        let original = try #require(fixture.budget.transaction(withId: id))
        var edited = original
        #expect(fixture.budget.reconciledWarning(original: original, edited: edited, payeeName: "X") == nil)
        edited.amount = -11
        let warning = fixture.budget.reconciledWarning(original: original, edited: edited, payeeName: nil)
        #expect(warning == .transaction(accountOrAmountChanged: true))
        #expect(warning?.title == "Abgeglichene Buchung ändern")
        #expect(
            warning?.content
                == "Diese Buchung ist abgeglichen. Mit anderem Konto oder Betrag stimmt der abgeglichene Saldo nicht mehr."
        )
        edited = original
        edited.date = october23.addingDays(1)
        #expect(
            fixture.budget.reconciledWarning(original: original, edited: edited, payeeName: nil)
                == .transaction(accountOrAmountChanged: false))
    }

    @Test func reconciledCounterpartWarnsAboutChangesAndPayee() throws {
        var fixture = TestBudget()
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -200)
        try fixture.budget.apply(.setCleared([EntityID.transferCounterpart(of: "TR")], .reconciled))
        let original = try #require(fixture.budget.transaction(withId: "TR"))
        var edited = original
        edited.date = october23
        #expect(
            fixture.budget.reconciledWarning(original: original, edited: edited, payeeName: nil)
                == .counterpart(amountChanged: false))
        #expect(
            fixture.budget.reconciledWarning(original: original, edited: original, payeeName: "REWE")
                == .counterpartPayee)
    }

    @Test func confirmingUnreconcilesWhenTheDateMovesPastTheReconciliation() throws {
        var fixture = TestBudget()
        let id = try fixture.add(fixture.girokonto, -10, on: "2026-10-05", cleared: .reconciled)
        var account = try #require(fixture.budget.account(withId: "GIRO"))
        account.lastReconciledAt = date("2026-10-06").noon()
        try fixture.budget.apply(.editAccount(account))
        var edited = try #require(fixture.budget.transaction(withId: id))
        edited.amount = -11
        try fixture.budget.apply(
            .saveTransaction(
                TransactionSave(transaction: edited, payeeName: nil, isNew: false, confirmedReconciledChange: true)))
        #expect(fixture.budget.transaction(withId: id)?.cleared == .reconciled)
        edited.date = date("2026-10-07")
        try fixture.budget.apply(
            .saveTransaction(
                TransactionSave(transaction: edited, payeeName: nil, isNew: false, confirmedReconciledChange: true)))
        #expect(fixture.budget.transaction(withId: id)?.cleared == .cleared)
    }
}

@Suite struct CategoryLookupTests {
    @Test func fullAndSubNamesFindCategories() {
        let fixture = TestBudget()
        #expect(fixture.budget.category(fullName: "everyday expenses: groceries")?.id == fixture.groceries)
        #expect(fixture.budget.category(fullName: "Everyday Expenses:Groceries")?.id == fixture.groceries)
        #expect(fixture.budget.category(named: "Groceries")?.id == fixture.groceries)
        #expect(fixture.budget.category(named: "Zu verteilen") == nil)
    }

    @Test func incomeIsLookedUpAsZuVerteilen() {
        let budget = TestBudget().budget
        #expect(budget.incomeCategory(label: "zu verteilen") == budget.readyToAssignCategoryId)
        #expect(budget.incomeCategory(label: "Income for Oktober") == nil)
    }

    @Test func nameComponentsSplitAtTheColon() {
        #expect(CategoryNames.components("Hobby: Bücher") == ("Hobby", "Bücher"))
        #expect(CategoryNames.components("Hobby") == ("Hobby", ""))
        #expect(CategoryNames.components("a:b:c") == ("", ""))
        #expect(CategoryNames.isIncomeGroupName(" Einnahmen "))
    }

    @Test func doubleUnderscoreMasterNamesAreReserved() {
        for name in ["__supplementalincome__", "__PrimaryIncome__", "__Split__", "__Internal__"] {
            #expect(CategoryNames.isReservedGroupName(name))
        }
        for name in [DefaultCategories.readyToAssignName, DefaultCategories.splitCategoryName] {
            #expect(!CategoryNames.isReservedGroupName(name))
        }
    }

    @Test func addingACategoryCreatesTheMasterWhenNeeded() throws {
        var budget = TestBudget().budget
        try budget.apply(.addNamedCategory(groupName: "Hobby", name: "Bücher"))
        let added = try #require(budget.category(fullName: "Hobby: Bücher"))
        #expect(budget.budgetCategoryGroups.last?.name == "Hobby")
        try budget.apply(.addNamedCategory(groupName: "hobby", name: "Kino"))
        #expect(budget.category(fullName: "Hobby: Kino")?.categoryGroupId == added.categoryGroupId)
        #expect(throws: BudgetError.duplicateCategoryName) {
            try budget.apply(.addNamedCategory(groupName: "Hobby", name: "bücher"))
        }
        #expect(throws: BudgetError.categoryNameMissing) {
            try budget.apply(.addNamedCategory(groupName: "", name: "X"))
        }
    }

    @Test func categoryNamesFollowTheNamingRulesAndTexts() throws {
        var budget = TestBudget().budget
        let illegal = "Eine Kategorie darf weder „:“ noch „`“ enthalten."
        for (master, name) in [("Haus:Neu", "Strom"), ("Haus", "Str`om"), ("In`come", "Bonus")] {
            #expect(throws: BudgetError.categoryIllegalCharacters) {
                try budget.apply(.addNamedCategory(groupName: master, name: name))
            }
        }
        #expect(BudgetError.categoryIllegalCharacters.errorDescription == illegal)
        #expect(throws: BudgetError.categoryCantBeIncome) {
            try budget.apply(.addNamedCategory(groupName: "einnahmen", name: "Bonus"))
        }
        #expect(
            BudgetError.categoryCantBeIncome.errorDescription?.hasPrefix("Einnahmen gehen an „Zu verteilen“") == true)
        #expect(throws: BudgetError.categoryIsReserved) {
            try budget.apply(.addNamedCategory(groupName: "__Internal__", name: "Alt"))
        }
        #expect(
            BudgetError.categoryIsReserved.errorDescription
                == "Dieser Name ist reserviert. Bitte einen anderen wählen.")
    }

    @Test func dropDownBalanceIsTheBalanceOfTodaysMonth() throws {
        var fixture = TestBudget()
        _ = try fixture.add(fixture.girokonto, -30, on: "2026-09-10", category: fixture.groceries)
        _ = try fixture.add(fixture.girokonto, 50, on: "2026-09-12", category: fixture.groceries)
        _ = try fixture.add(fixture.girokonto, -45, on: "2026-10-10", category: fixture.groceries)
        _ = try fixture.add(fixture.depot, -99, on: "2026-10-10", category: fixture.groceries)
        #expect(fixture.budget.categoryBalances(today: date("2026-09-30"))[fixture.groceries] == 20)
        #expect(fixture.budget.categoryBalances(today: october23)[fixture.groceries] == -25)
        #expect(fixture.budget.categoryBalances(today: date("2026-11-01"))[fixture.groceries] == 0)
        #expect(fixture.budget.categoryBalances(today: date("2026-08-01"))[fixture.groceries] == 0)
        try fixture.budget.apply(.setAssigned(month: october23, categoryId: fixture.groceries, amount: 100))
        #expect(fixture.budget.categoryBalances(today: october23)[fixture.groceries] == 75)
    }
}
