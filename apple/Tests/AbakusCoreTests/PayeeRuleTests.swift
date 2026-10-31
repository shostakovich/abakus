import AbakusCore
import Foundation
import Testing

@Suite struct RenameConditionTests {
    private func rule(_ op: StringOperator, _ text: String) -> PayeeRenameCondition {
        PayeeRenameCondition(operator: op, text: text)
    }

    @Test func containsIgnoresCase() {
        #expect(rule(.contains, "amazon").matches("AMAZON MKTPLACE 1234"))
        #expect(!rule(.contains, "amazon").matches("Amazn"))
    }

    @Test func isNeedsTheWholeName() {
        #expect(rule(.is, "rewe").matches("REWE"))
        #expect(!rule(.is, "rewe").matches("REWE Markt"))
    }

    @Test func startsWithAndEndsWith() {
        #expect(rule(.startsWith, "paypal *").matches("PAYPAL *Spotify"))
        #expect(!rule(.startsWith, "spotify").matches("PAYPAL *Spotify"))
        #expect(rule(.endsWith, "spotify").matches("PAYPAL *Spotify"))
        #expect(!rule(.endsWith, "paypal").matches("PAYPAL *Spotify"))
    }

    @Test func aBlankOperandNeverMatches() {
        #expect(!rule(.contains, "  ").matches("anything"))
        #expect(!rule(.is, "").matches(""))
    }

    @Test func operatorsKeepAbakusNamesWithGermanLabels() {
        #expect(StringOperator.allCases.map(\.rawValue) == ["contains", "is", "starts_with", "ends_with"])
        #expect(StringOperator.allCases.map(\.label) == ["enthält", "ist", "beginnt mit", "endet mit"])
    }

    private func budget(_ payee: Payee, _ conditions: [PayeeRenameCondition]) -> Budget {
        var budget = Budget(budgetName: "Test", payees: [payee])
        try? budget.apply(.setPayeeRenameConditions(payeeId: payee.id, conditions))
        return budget
    }

    @Test func aPayeeAppliesToItsOwnNameAndItsRules() {
        let payee = Payee(name: "Amazon")
        let budget = budget(payee, [rule(.startsWith, "AMZN")])
        #expect(budget.appliesRenameRules(of: payee, to: "amazon"))
        #expect(budget.appliesRenameRules(of: payee, to: "AMZN Mktp DE"))
        #expect(!budget.appliesRenameRules(of: payee, to: "Zalando"))
    }

    @Test func transferNamesNeverMatch() {
        let payee = Payee(name: "Savings")
        #expect(
            !budget(payee, [rule(.contains, "Tagesgeld")]).appliesRenameRules(of: payee, to: "Transfer : Tagesgeld"))
    }

    @Test func conditionsAreStoredInOrderForTheirPayeeWithoutBlankOnes() {
        let payee = Payee(name: "Amazon")
        let budget = budget(payee, [rule(.contains, "AMZN"), rule(.is, " "), rule(.endsWith, "DE")])
        #expect(budget.renameConditions(ofPayee: payee.id).map(\.text) == ["AMZN", "DE"])
        #expect(budget.payeeRenameConditions.allSatisfy { $0.payeeId == payee.id })
        #expect(budget.renameConditions(ofPayee: payee.id).map(\.position) == [0, 1])
    }
}

@Suite struct PayeeRenameTests {
    private func payeeId(_ budget: Budget, _ name: String) -> String {
        budget.payee(named: name)!.id
    }

    private func operands(_ budget: Budget, _ name: String) -> [String] {
        budget.renameConditions(ofPayee: budget.payee(named: name)!.id).map(\.text)
    }

    @Test func renamingInPlaceRemembersTheOldName() throws {
        var test = TestBudget()
        let a = try test.add(test.girokonto, -1, payee: "Amazn")
        let id = payeeId(test.budget, "Amazn")
        let budget = try test.budget.applying(.renamePayee(payeeId: id, name: "Amazon"))
        #expect(budget.payeeName(of: budget.transaction(withId: a)!) == "Amazon")
        #expect(budget.payee(withId: id)?.name == "Amazon")
        #expect(budget.renameConditions(ofPayee: id).map(\.operator) == [.is])
        #expect(operands(budget, "Amazon") == ["Amazn"])
    }

    @Test func aCapitalisationChangeAddsNoRule() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "rewe")
        let budget = try test.budget.applying(.renamePayee(payeeId: payeeId(test.budget, "rewe"), name: "REWE"))
        #expect(budget.payee(named: "REWE")?.name == "REWE")
        #expect(operands(budget, "REWE").isEmpty)
    }

    @Test func mergingMovesTransactionsAndSchedules() throws {
        var test = TestBudget()
        let a = try test.add(test.girokonto, -1, payee: "Rewe Markt")
        _ = try test.add(test.girokonto, -2, payee: "REWE")
        try test.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(
                    transaction: Transaction(
                        id: "S", accountId: test.girokonto, date: date("2026-11-01"), amount: -3),
                    frequency: .monthly, payeeName: "Rewe Markt", isNew: true)))
        let old = payeeId(test.budget, "Rewe Markt")
        let budget = try test.budget.applying(.renamePayee(payeeId: old, name: "rewe"))
        #expect(budget.payee(withId: old) == nil)
        #expect(budget.payeeName(of: budget.transaction(withId: a)!) == "REWE")
        #expect(budget.scheduledTransactions.first { $0.id == "S" }?.payeeId == payeeId(budget, "REWE"))
        #expect(operands(budget, "REWE") == ["Rewe Markt"])
    }

    @Test func mergingTakesOverRulesWithoutDuplicates() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Amazon.de")
        _ = try test.add(test.girokonto, -2, payee: "Amazon")
        let source = payeeId(test.budget, "Amazon.de")
        let target = payeeId(test.budget, "Amazon")
        try test.budget.apply(
            .setPayeeRenameConditions(
                payeeId: source,
                [
                    PayeeRenameCondition(operator: .contains, text: "AMZN"),
                    .init(operator: .startsWith, text: "MKTP"),
                ]))
        try test.budget.apply(
            .setPayeeRenameConditions(payeeId: target, [PayeeRenameCondition(operator: .contains, text: "amzn")]))
        let budget = try test.budget.applying(.renamePayee(payeeId: source, name: "Amazon"))
        #expect(operands(budget, "Amazon") == ["amzn", "MKTP", "Amazon.de"])
    }

    @Test func theMergeTargetKeepsItsOwnSettings() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Edeka City")
        _ = try test.add(test.girokonto, -2, payee: "Edeka", category: test.groceries)
        let target = payeeId(test.budget, "Edeka")
        try test.budget.apply(.setPayeeLastCategory(payeeId: target, categoryId: test.groceries))
        try test.budget.apply(.setPayeesHidden([target], true))
        let budget = try test.budget.applying(.renamePayee(payeeId: payeeId(test.budget, "Edeka City"), name: "Edeka"))
        #expect(budget.payee(withId: target)?.hidden == true)
        #expect(budget.payee(withId: target)?.lastCategoryId == test.groceries)
    }

    @Test func theOldNameRuleMovesToTheNewTarget() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Amazn")
        let first = payeeId(test.budget, "Amazn")
        try test.budget.apply(.renamePayee(payeeId: first, name: "Amazon"))
        _ = try test.add(test.girokonto, -2, payee: "Amazn")
        let budget = try test.budget.applying(
            .renamePayee(payeeId: payeeId(test.budget, "Amazn"), name: "Amazon Prime"))
        #expect(operands(budget, "Amazon").isEmpty)
        #expect(operands(budget, "Amazon Prime") == ["Amazn"])
    }

    @Test func noRuleWhenTheTargetAlreadyMatchesTheOldName() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "AMZN Mktp")
        _ = try test.add(test.girokonto, -2, payee: "Amazon")
        try test.budget.apply(
            .setPayeeRenameConditions(
                payeeId: payeeId(test.budget, "Amazon"), [PayeeRenameCondition(operator: .startsWith, text: "AMZN")])
        )
        let budget = try test.budget.applying(.renamePayee(payeeId: payeeId(test.budget, "AMZN Mktp"), name: "Amazon"))
        #expect(operands(budget, "Amazon") == ["AMZN"])
    }

    @Test func aTransferPayeeIsNeverRenamed() throws {
        let test = TestBudget()
        let transfer = EntityID.transferPayee(accountId: test.tagesgeld)
        #expect(throws: BudgetError.transferPayeeCannotBeRenamed) {
            try test.budget.applying(.renamePayee(payeeId: transfer, name: "Savings"))
        }
    }

    @Test func aTransferNameOrABlankNameIsRefused() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "REWE")
        let id = payeeId(test.budget, "REWE")
        #expect(throws: BudgetError.transferPayeeName("Transfer : Tagesgeld")) {
            try test.budget.applying(.renamePayee(payeeId: id, name: " Transfer : Tagesgeld"))
        }
        #expect(throws: BudgetError.emptyPayeeName) {
            try test.budget.applying(.renamePayee(payeeId: id, name: "   "))
        }
    }

    @Test func renamingOneOfTwoPayeesWithTheSameLookupKeyMergesThem() throws {
        var test = TestBudget()
        let plain = Payee(id: "PLAIN", name: "Rewe")
        let emoji = Payee(id: "EMOJI", name: "🛒 Rewe")
        test.budget.payees += [plain, emoji]
        let first = Transaction(
            id: "T1", accountId: test.girokonto, date: october23, payeeId: "PLAIN", amount: -1)
        let second = Transaction(
            id: "T2", accountId: test.girokonto, date: october23, payeeId: "EMOJI", amount: -2)
        test.budget.transactions += [first, second]
        try test.budget.apply(.renamePayee(payeeId: "PLAIN", name: "🛒 Rewe"))
        #expect(test.budget.payees.count(where: { Payee.sameName($0.name, "Rewe") }) == 1)
        #expect(test.budget.transaction(withId: "T1")?.payeeId == "EMOJI")
        #expect(test.budget.transaction(withId: "T2")?.payeeId == "EMOJI")
    }
}

@Suite struct PayeeSettingsCommandTests {
    private func payeeId(_ budget: Budget, _ name: String) -> String {
        budget.payee(named: name)!.id
    }

    @Test func combiningMergesEverySelectedPayee() throws {
        var test = TestBudget()
        let a = try test.add(test.girokonto, -1, payee: "Shell 123")
        let b = try test.add(test.girokonto, -2, payee: "SHELL Station")
        let ids = [payeeId(test.budget, "Shell 123"), payeeId(test.budget, "SHELL Station")]
        let budget = try test.budget.applying(.combinePayees(ids, name: " Shell "))
        let shell = try #require(budget.payee(named: "Shell"))
        #expect(shell.name == "Shell")
        #expect(budget.transaction(withId: a)?.payeeId == shell.id)
        #expect(budget.transaction(withId: b)?.payeeId == shell.id)
        #expect(Set(budget.renameConditions(ofPayee: shell.id).map(\.text)) == ["Shell 123", "SHELL Station"])
        #expect(budget.payees.filter { !$0.isTransferPayee }.map(\.name).contains("SHELL Station") == false)
    }

    @Test func combiningSkipsTransferPayees() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Aral")
        let transfer = EntityID.transferPayee(accountId: test.tagesgeld)
        let budget = try test.budget.applying(.combinePayees([transfer, payeeId(test.budget, "Aral")], name: "Fuel"))
        #expect(budget.payee(withId: transfer)?.name == "Transfer : Tagesgeld")
        #expect(budget.payee(named: "Fuel") != nil)
    }

    @Test func combiningRefusesTransferAndBlankNames() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Aral")
        let ids = [payeeId(test.budget, "Aral")]
        #expect(throws: BudgetError.transferPayeeName("Transfer : Depot")) {
            try test.budget.applying(.combinePayees(ids, name: "Transfer : Depot"))
        }
        #expect(throws: BudgetError.emptyPayeeName) { try test.budget.applying(.combinePayees(ids, name: " ")) }
    }

    @Test func enablingSkipsTransferPayees() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Aral")
        let aral = payeeId(test.budget, "Aral")
        let transfer = EntityID.transferPayee(accountId: test.tagesgeld)
        let budget = try test.budget.applying(.setPayeesHidden([aral, transfer], true))
        #expect(budget.payee(withId: aral)?.hidden == true)
        #expect(budget.payee(withId: transfer)?.hidden == false)
    }

    @Test func theAutoFillCategoryTakesOnlyRealCategories() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Aral")
        let aral = payeeId(test.budget, "Aral")
        try test.budget.apply(.setPayeeLastCategory(payeeId: aral, categoryId: test.groceries))
        #expect(test.budget.payee(withId: aral)?.lastCategoryId == test.groceries)
        try test.budget.apply(.setPayeeLastCategory(payeeId: aral, categoryId: EntityID.splitCategory))
        try test.budget.apply(.setPayeeLastCategory(payeeId: aral, categoryId: "missing"))
        #expect(test.budget.payee(withId: aral)?.lastCategoryId == test.groceries)
        try test.budget.apply(.setPayeeLastCategory(payeeId: aral, categoryId: nil))
        #expect(test.budget.payee(withId: aral)?.lastCategoryId == nil)
    }

    @Test func blankRulesAreNotStored() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Aral")
        let aral = payeeId(test.budget, "Aral")
        try test.budget.apply(
            .setPayeeRenameConditions(
                payeeId: aral, [.init(operator: .contains, text: "ARAL"), .init(text: " ")]))
        #expect(test.budget.renameConditions(ofPayee: aral).map(\.text) == ["ARAL"])
    }

    @Test func aPayeeWithRulesOutlivesItsLastTransaction() throws {
        var test = TestBudget()
        let a = try test.add(test.girokonto, -1, payee: "Aral")
        try test.budget.apply(
            .setPayeeRenameConditions(
                payeeId: payeeId(test.budget, "Aral"), [.init(operator: .contains, text: "ARAL")]))
        try test.budget.apply(.deleteTransactions([a]))
        #expect(test.budget.payee(named: "Aral") != nil)
        #expect(test.budget.renameConditions(ofPayee: payeeId(test.budget, "Aral")).map(\.text) == ["ARAL"])
    }

    @Test func theListSortsByNameWithTransfers() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "zalando")
        _ = try test.add(test.girokonto, -1, payee: "Aral")
        let names = test.budget.payeesSortedByName.map(\.name)
        #expect(names.prefix(2) == ["Anfangssaldo", "Aral"])
        #expect(names.last == "zalando")
        #expect(names.contains("Transfer : Depot"))
    }

    @Test func theUseCountTakesTransactionsAndSchedules() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Miete")
        try test.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(
                    transaction: Transaction(accountId: test.girokonto, date: date("2026-11-01"), amount: -800),
                    frequency: .monthly, payeeName: "Miete", isNew: true)))
        let id = payeeId(test.budget, "Miete")
        #expect(test.budget.payeeUseCount(id) == 2)
        #expect(test.budget.payeeHasScheduledTransactions(id))
    }

    @Test func aSplitPartOfAScheduleCountsAsScheduledUse() throws {
        var test = TestBudget()
        let schedule = Transaction(
            id: "P", accountId: test.girokonto, date: date("2026-11-01"), categoryId: EntityID.splitCategory,
            amount: -10,
            subtransactions: [
                Subtransaction(id: "L1", transactionId: "P", amount: -6),
                Subtransaction(id: "L2", transactionId: "P", amount: -4),
            ])
        try test.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(
                    transaction: schedule, frequency: .monthly, payeeName: "Kaufland", subPayeeNames: ["L1": "Miete"],
                    isNew: true)))
        #expect(test.budget.payeeHasScheduledTransactions(payeeId(test.budget, "Miete")))
    }
}

@Suite struct RenameExistingPayeesTests {
    private func payeeId(_ budget: Budget, _ name: String) -> String {
        budget.payee(named: name)!.id
    }

    private func withRule(_ test: inout TestBudget, on name: String, _ op: StringOperator, _ text: String) throws {
        try test.budget.apply(
            .setPayeeRenameConditions(payeeId: payeeId(test.budget, name), [.init(operator: op, text: text)]))
    }

    @Test func thePreviewCountsMatchesAndNamesTheirPayees() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Amazon")
        _ = try test.add(test.girokonto, -2, payee: "AMZN Mktp")
        _ = try test.add(test.girokonto, -3, payee: "AMZN Mktp")
        _ = try test.add(test.girokonto, -4, payee: "amzn digital")
        _ = try test.add(test.girokonto, -5, payee: "Zalando")
        try withRule(&test, on: "Amazon", .startsWith, "amzn")
        let preview = test.budget.renameRulePreview(for: payeeId(test.budget, "Amazon"))
        #expect(preview.transactionCount == 3)
        #expect(preview.payeeNames == ["amzn digital", "AMZN Mktp"])
    }

    @Test func thePreviewIsEmptyWithoutMatches() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Amazon")
        try withRule(&test, on: "Amazon", .is, "Amazon Prime")
        #expect(test.budget.renameRulePreview(for: payeeId(test.budget, "Amazon")).transactionCount == 0)
    }

    @Test func renamingExistingPayeesMergesThem() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Amazon")
        let b = try test.add(test.girokonto, -2, payee: "AMZN Mktp")
        try withRule(&test, on: "Amazon", .startsWith, "amzn")
        let amazon = payeeId(test.budget, "Amazon")
        let budget = try test.budget.applying(.applyRenameRules(payeeId: amazon))
        #expect(budget.transaction(withId: b)?.payeeId == amazon)
        #expect(budget.payee(named: "AMZN Mktp") == nil)
        #expect(budget.renameConditions(ofPayee: amazon).map(\.text) == ["amzn"])
    }

    @Test func rulesAlsoMatchAndRenameThePayeesOfSplitParts() throws {
        var test = TestBudget()
        _ = try test.add(test.girokonto, -1, payee: "Amazon")
        let split = Transaction(
            id: "S", accountId: test.girokonto, date: october23, categoryId: EntityID.splitCategory, amount: -5,
            subtransactions: [
                Subtransaction(id: "L1", transactionId: "S", amount: -3),
                Subtransaction(id: "L2", transactionId: "S", amount: -2),
            ])
        try test.budget.apply(
            .saveTransaction(
                TransactionSave(
                    transaction: split, payeeName: "Kaufland", subPayeeNames: ["L1": "AMZN Mktp"], isNew: true)
            ))
        try withRule(&test, on: "Amazon", .startsWith, "amzn")
        let amazon = payeeId(test.budget, "Amazon")
        let preview = test.budget.renameRulePreview(for: amazon)
        #expect(preview.transactionCount == 1)
        #expect(preview.payeeNames == ["AMZN Mktp"])
        let budget = try test.budget.applying(.applyRenameRules(payeeId: amazon))
        #expect(budget.transaction(withId: "S")?.subtransactions.first?.payeeId == amazon)
        #expect(budget.payee(named: "AMZN Mktp") == nil)
    }

    @Test func aTransferPayeesRulesTurnMatchesIntoTransfers() throws {
        var test = TestBudget()
        let out = try test.add(test.girokonto, -50, payee: "SPARPLAN TG")
        let inside = try test.add(test.tagesgeld, 50, payee: "SPARPLAN TG")
        let transfer = EntityID.transferPayee(accountId: test.tagesgeld)
        try test.budget.apply(
            .setPayeeRenameConditions(payeeId: transfer, [.init(operator: .startsWith, text: "sparplan")]))
        #expect(test.budget.renameRulePreview(for: transfer).transactionCount == 1)
        let budget = try test.budget.applying(.applyRenameRules(payeeId: transfer))
        let converted = try #require(budget.transaction(withId: out))
        #expect(converted.payeeId == EntityID.transferPayee(accountId: test.tagesgeld))
        #expect(converted.payeeId == transfer)
        let counterpart = try #require(converted.transferTransactionId.flatMap(budget.transaction(withId:)))
        #expect(counterpart.accountId == test.tagesgeld)
        #expect(counterpart.amount == 50)
        #expect(budget.transaction(withId: inside)?.payeeId == payeeId(test.budget, "SPARPLAN TG"))
        #expect(budget.payee(named: "SPARPLAN TG") != nil)
    }
}

@Suite struct AutoFillTests {
    private func remembered() throws -> TestBudget {
        var test = TestBudget()
        let id = try test.add(test.girokonto, -42, payee: "Edeka", category: test.groceries)
        var saved = test.budget.transaction(withId: id)!
        saved.memo = "Wocheneinkauf"
        try test.budget.apply(.saveTransaction(TransactionSave(transaction: saved, payeeName: "Edeka", isNew: false)))
        return test
    }

    @Test func onlyTheCategoryByDefault() throws {
        let test = try remembered()
        let fill = try #require(test.budget.autoFill(payeeName: "edeka", accountId: test.girokonto, settings: .init()))
        #expect(fill.categoryId == test.groceries)
        #expect(fill.memo == nil)
        #expect(fill.amount == nil)
    }

    @Test func memoAndAmountWhenSwitchedOn() throws {
        let test = try remembered()
        let settings = AutoFillSettings(category: false, memo: true, amount: true)
        let fill = try #require(test.budget.autoFill(payeeName: "Edeka", accountId: test.girokonto, settings: settings))
        #expect(fill.categoryId == nil)
        #expect(fill.memo == "Wocheneinkauf")
        #expect(fill.amount == -42)
    }

    @Test func noCategoryOffBudgetOrForADisabledPayee() throws {
        var test = try remembered()
        #expect(test.budget.autoFill(payeeName: "Edeka", accountId: test.depot, settings: .init())?.categoryId == nil)
        try test.budget.apply(.setPayeesHidden([test.budget.payee(named: "Edeka")!.id], true))
        #expect(test.budget.autoFill(payeeName: "Edeka", accountId: test.girokonto, settings: .init()) == nil)
    }
}
