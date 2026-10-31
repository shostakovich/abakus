import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
struct PayeeSettingsFixture {
    var fixture = RegisterFixture()
    var aral = ""
    var rewe = ""

    init() {
        aral = fixture.add(fixture.giro, -60, payee: "Aral")
        rewe = fixture.add(fixture.giro, -20, payee: "REWE", category: fixture.groceries)
        fixture.add(fixture.giro, -30, payee: "REWE", category: fixture.groceries)
        fixture.add(fixture.karte, -5, payee: "Lidl")
    }

    func app(storage: MemorySettingsStorage? = nil) -> AppModel {
        AppModel(
            store: BudgetStore(budget: fixture.budget, today: { editDay }), selection: .account(fixture.giro),
            defaults: storage)
    }

    func dialog(_ app: AppModel, on name: String? = nil) throws -> PayeeSettingsModel {
        app.openPayeeSettings(payeeName: name)
        return try #require(app.payeeSettings)
    }

    func id(_ app: AppModel, _ name: String) -> String {
        app.store.budget.payee(named: name, includingTransfers: true)!.id
    }

    func id(_ name: String) -> String {
        fixture.budget.payee(named: name, includingTransfers: true)!.id
    }

    func spied(on name: String? = nil, appliesCommands: Bool = false)
        -> (dialog: PayeeSettingsModel, store: SpyBudgetStore)
    {
        let store = SpyBudgetStore(budget: fixture.budget, appliesCommands: appliesCommands)
        let dialog = PayeeSettingsModel(
            store: store, initialPayeeId: name.map(id), autoFill: AutoFillSettings())
        return (dialog, store)
    }
}

extension PayeeSettingsModel {
    func commandClick(_ payeeId: String) {
        var ids = Set(selection)
        if ids.remove(payeeId) == nil { ids.insert(payeeId) }
        selectionChanged(to: ids)
    }
}

@MainActor
@Suite struct PayeeSettingsOpeningTests {
    @Test func opensOnTheNamedPayee() throws {
        let setup = PayeeSettingsFixture()
        let app = setup.app()
        let dialog = try setup.dialog(app, on: "rewe")
        #expect(dialog.selection == [setup.id(app, "REWE")])
        #expect(dialog.state == .single)
        #expect(dialog.scrollRequest?.payeeId == setup.id(app, "REWE"))
        #expect(app.register.isBlockedByModal)
    }

    @Test func withoutAPayeeNothingIsSelected() throws {
        let setup = PayeeSettingsFixture()
        let dialog = try setup.dialog(setup.app())
        #expect(dialog.state == .noSelection)
        #expect(dialog.rows.contains { $0.name == "Transfer : Tagesgeld" })
    }

    @Test func closeRemembersTheSelectionEscapeDoesNot() throws {
        let setup = PayeeSettingsFixture()
        let app = setup.app()
        var dialog = try setup.dialog(app, on: "Aral")
        dialog.selectionChanged(to: [setup.id(app, "REWE")])
        dialog.close()
        #expect(app.payeeSettings == nil)
        dialog = try setup.dialog(app, on: "unknown payee")
        #expect(dialog.selection == [setup.id(app, "REWE")])
        dialog.selectionChanged(to: [setup.id(app, "Lidl")])
        dialog.escapePressed()
        #expect(try setup.dialog(app).selection == [setup.id(app, "REWE")])
    }

    @Test func aSecondOpenIsIgnored() throws {
        let setup = PayeeSettingsFixture()
        let app = setup.app()
        let first = try setup.dialog(app, on: "Aral")
        app.openPayeeSettings(payeeName: "REWE")
        #expect(app.payeeSettings === first)
        #expect(first.selection == [setup.id(app, "Aral")])
    }

    @Test func theCountLinkSearchesAllAccounts() throws {
        let setup = PayeeSettingsFixture()
        let app = setup.app()
        let dialog = try setup.dialog(app, on: "REWE")
        dialog.showTransactionsClicked()
        #expect(app.payeeSettings == nil)
        #expect(app.navigation.selection == .allAccounts)
        #expect(app.register.search.filter?.label == "Empfänger: REWE")
        #expect(
            Set(app.register.transactionIds)
                == Set(
                    app.store.budget.transactions.filter {
                        $0.payeeId == setup.id(app, "REWE")
                    }.map(\.id)))
    }

    @Test func theCountLinkClearsTheDateFilter() throws {
        let setup = PayeeSettingsFixture()
        let app = setup.app()
        app.navigation.selection = .allAccounts
        app.register.search.dateSelectorClicked()
        app.register.search.timeframePresetClicked(.thisMonth)
        #expect(app.register.search.dateFilter != nil)
        app.navigation.selection = .account(setup.fixture.giro)
        try setup.dialog(app, on: "REWE").showTransactionsClicked()
        #expect(app.navigation.selection == .allAccounts)
        #expect(app.register.search.dateFilter == nil)
        #expect(app.register.search.filter?.label == "Empfänger: REWE")
    }
}

@MainActor
@Suite struct PayeeSettingsSelectionTests {
    @Test func newlySelectedPayeesComeFirst() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, _) = setup.spied()
        let (aral, lidl, rewe) = (setup.id("Aral"), setup.id("Lidl"), setup.id("REWE"))
        dialog.selectionChanged(to: [aral])
        dialog.selectionChanged(to: [aral, rewe])
        #expect(dialog.selection == [rewe, aral])
        #expect(dialog.rows.filter(\.isSelected).count == 2)
        dialog.selectionChanged(to: [aral])
        #expect(dialog.selection == [aral])
        dialog.selectionChanged(to: [aral, lidl, rewe])
        #expect(dialog.selection == [rewe, lidl, aral])
        dialog.selectionChanged(to: [lidl])
        #expect(dialog.selection == [lidl])
        dialog.selectionChanged(to: [])
        #expect(dialog.state == .noSelection)
    }

    @Test func anUnchangedSelectionKeepsTheRename() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, _) = setup.spied(on: "Aral")
        dialog.startRenaming()
        dialog.selectionChanged(to: [setup.id("Aral")])
        #expect(dialog.isRenaming)
    }

    @Test func severalPayeesShowTheirNamesLastFirstAndPrefillTheName() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, _) = setup.spied(on: "Aral")
        dialog.commandClick(setup.id("REWE"))
        #expect(dialog.state == .multiple)
        #expect(dialog.multipleTitle == "2 Empfänger ausgewählt")
        #expect(dialog.selectedNamesText == "„Aral“, „REWE“")
        #expect(dialog.combineName == "REWE")
        #expect(dialog.focusRequest?.field == .combine)
    }
}

@MainActor
@Suite struct PayeeSettingsSinglePayeeTests {
    @Test func renamingSendsTheNameAndShowsTheRenamedPayee() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral", appliesCommands: true)
        dialog.startRenaming()
        #expect(dialog.isRenaming)
        #expect(dialog.focusRequest?.field == .rename)
        dialog.renameText = " Aral Tankstelle "
        dialog.saveRename()
        #expect(store.commands == [.renamePayee(payeeId: setup.id("Aral"), name: "Aral Tankstelle")])
        #expect(!dialog.isRenaming)
        #expect(dialog.selectedPayeeName == "Aral Tankstelle")
        #expect(dialog.rules.map(\.operand) == ["Aral"])
    }

    @Test func renamingIntoAnotherPayeeSelectsIt() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Lidl", appliesCommands: true)
        dialog.startRenaming()
        dialog.renameText = "rewe"
        dialog.saveRename()
        #expect(store.commands == [.renamePayee(payeeId: setup.id("Lidl"), name: "rewe")])
        #expect(dialog.selection == [setup.id("REWE")])
        #expect(dialog.scrollRequest?.payeeId == setup.id("REWE"))
        #expect(dialog.transactionCount == 3)
    }

    @Test func aBlankOrUnchangedNameSendsNothing() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral")
        for name in ["  ", "Aral"] {
            dialog.startRenaming()
            dialog.renameText = name
            dialog.saveRename()
            #expect(dialog.renameText == "Aral")
        }
        #expect(store.commands.isEmpty)
    }

    @Test func aRefusedNameShowsTheBudgetsWarning() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral")
        store.fail(with: BudgetError.transferPayeeName("Transfer : Giro"))
        dialog.startRenaming()
        dialog.renameText = "Transfer : Giro"
        dialog.saveRename()
        #expect(store.commands == [.renamePayee(payeeId: setup.id("Aral"), name: "Transfer : Giro")])
        #expect(dialog.dialogs.presented.last?.dialog.instruction == "Ungültiger Empfängername")
        #expect(
            dialog.dialogs.presented.last?.dialog.content.hasPrefix(
                "„Transfer : Giro“ ist kein gültiger Empfängername.")
                == true)
        #expect(dialog.selection == [setup.id("Aral")])
    }

    @Test func aTransferPayeeCannotBeRenamedOrUnlisted() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Transfer : Tagesgeld")
        #expect(dialog.isTransfer)
        dialog.startRenaming()
        #expect(!dialog.isRenaming)
        dialog.setSelectedPayeeEnabled(false)
        #expect(dialog.isSelectedPayeeEnabled)
        #expect(store.commands.isEmpty)
    }

    @Test func theListingCheckboxDisablesThePayee() throws {
        let setup = PayeeSettingsFixture()
        let aral = setup.id("Aral")
        var disabled = setup.fixture.budget
        disabled.payees[disabled.payees.firstIndex { $0.id == aral }!].hidden = true
        let (dialog, store) = setup.spied(on: "Aral")
        store.budgetAfterNextCommand = disabled
        dialog.setSelectedPayeeEnabled(false)
        #expect(store.commands == [.setPayeesHidden([aral], true)])
        #expect(dialog.rows.first { $0.name == "Aral" }?.isEnabled == false)
        #expect(!dialog.isSelectedPayeeEnabled)
    }

    @Test func theCountNamesTransactions() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, _) = setup.spied(on: "Aral")
        #expect(dialog.transactionCountText == "1 Buchung")
        dialog.selectionChanged(to: [setup.id("REWE")])
        #expect(dialog.transactionCountText == "2 Buchungen")
    }

    @Test func theRuleLabelEscapesTheName() throws {
        var setup = PayeeSettingsFixture()
        setup.fixture.add(setup.fixture.giro, -1, payee: "B&B <Hotel>")
        let (dialog, _) = setup.spied(on: "B&B <Hotel>")
        #expect(
            dialog.renameIfLabel
                == "Importierte Buchungen in <b>B&amp;B &lt;Hotel&gt;</b> umbenennen, wenn der Empfänger:")
    }
}

@MainActor
@Suite struct PayeeSettingsCategoryTests {
    @Test func aFullCategoryNameIsStored() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral")
        dialog.categoryTextChanged("Everyday Expenses: Fuel")
        dialog.commitCategory()
        let fuel = setup.fixture.category("Everyday Expenses", "Fuel")
        #expect(store.commands == [.setPayeeLastCategory(payeeId: setup.id("Aral"), categoryId: fuel)])
        #expect(dialog.categoryText == "Everyday Expenses: Fuel")
        #expect(dialog.categoryList == nil)
    }

    @Test func theHighlightedItemIsTaken() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral")
        dialog.categoryTextChanged("Fue")
        #expect(dialog.categoryList?.highlightedItem?.value == "Everyday Expenses: Fuel")
        dialog.commitCategory()
        #expect(dialog.categoryText == "Everyday Expenses: Fuel")
        let fuel = setup.fixture.category("Everyday Expenses", "Fuel")
        #expect(store.commands == [.setPayeeLastCategory(payeeId: setup.id("Aral"), categoryId: fuel)])
    }

    @Test func focusShowsTheListWithoutFooter() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, _) = setup.spied(on: "Aral")
        dialog.categoryFocused()
        let list = try #require(dialog.categoryList)
        #expect(list.footerTitle == nil)
        #expect(list.kind.headerTitle == "Kategorien")
        #expect(list.items.contains { $0.value == "Zu verteilen" })
        #expect(list.items.allSatisfy { $0.balance == nil })
    }

    @Test func anEmptyTextClearsTheCategory() throws {
        var setup = PayeeSettingsFixture()
        let rewe = setup.id("REWE")
        try setup.fixture.budget.apply(.setPayeeLastCategory(payeeId: rewe, categoryId: setup.fixture.groceries))
        let (dialog, store) = setup.spied(on: "REWE")
        #expect(dialog.categoryText == "Everyday Expenses: Groceries")
        dialog.categoryTextChanged("")
        dialog.commitCategory()
        #expect(store.commands == [.setPayeeLastCategory(payeeId: rewe, categoryId: nil)])
    }

    @Test func anUnknownNameAsksForANewCategory() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral", appliesCommands: true)
        dialog.categoryTextChanged("Auto: Tanken")
        dialog.commitCategory()
        #expect(dialog.addCategoryForm?.masterName == "Auto")
        #expect(dialog.addCategoryForm?.name == "Tanken")
        #expect(store.commands.isEmpty)
        dialog.addCategoryConfirmed(masterName: "Auto", name: "Tanken")
        #expect(dialog.addCategoryForm == nil)
        #expect(dialog.categoryText == "Auto: Tanken")
        let added = try #require(store.budget.category(fullName: "Auto: Tanken")?.id)
        #expect(
            store.commands == [
                .addNamedCategory(groupName: "Auto", name: "Tanken"),
                .setPayeeLastCategory(payeeId: setup.id("Aral"), categoryId: added),
            ])
    }

    @Test func aRefusedNewCategoryReportsAndRefocusesTheForm() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral")
        dialog.categoryTextChanged("Auto: Tanken")
        dialog.commitCategory()
        store.fail(with: BudgetError.categoryNameMissing)
        dialog.addCategoryConfirmed(masterName: "", name: "Tanken")
        let failed = try #require(dialog.addCategoryForm)
        let message = try #require(dialog.dialogs.presented.last?.dialog)
        #expect(message.instruction == "Bitte einen anderen Kategorienamen wählen.")
        #expect(message.content == BudgetError.categoryNameMissing.errorDescription)
        dialog.dialogs.presented.last?.answer(MessageChoice.close)
        #expect(!dialog.dialogs.isPresenting)
        #expect(dialog.addCategoryForm?.refocusRequest == failed.refocusRequest + 1)
        #expect(store.commands == [.addNamedCategory(groupName: "", name: "Tanken")])
    }

    @Test func cancellingTheNewCategoryRestoresTheText() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral")
        dialog.categoryTextChanged("Neue Kategorie …")
        dialog.commitCategory()
        #expect(dialog.addCategoryForm?.masterName == "")
        dialog.addCategoryCancelled()
        #expect(dialog.categoryText == "")
        #expect(store.commands.isEmpty)
    }

    @Test func anIncomeMasterIsRefused() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral")
        dialog.categoryTextChanged("Einnahmen: Bonus")
        dialog.commitCategory()
        #expect(dialog.addCategoryForm == nil)
        #expect(dialog.dialogs.presented.last?.dialog.instruction == "Bitte einen anderen Kategorienamen wählen.")
        #expect(store.commands.isEmpty)
    }

    @Test func closeKeepsAKnownCategoryEscapeDiscards() throws {
        let setup = PayeeSettingsFixture()
        let aral = setup.id("Aral")
        let fuel = setup.fixture.category("Everyday Expenses", "Fuel")
        var (dialog, store) = setup.spied(on: "Aral")
        var closed: [String?] = []
        dialog.onClose = { closed.append($0) }
        dialog.categoryTextChanged("Everyday Expenses: Fuel")
        dialog.escapePressed()
        dialog.escapePressed()
        #expect(closed == [nil])
        #expect(store.commands.isEmpty)
        (dialog, store) = setup.spied(on: "Aral")
        dialog.onClose = { closed.append($0) }
        dialog.categoryTextChanged("Everyday Expenses: Fuel")
        dialog.close()
        #expect(store.commands == [.setPayeeLastCategory(payeeId: aral, categoryId: fuel)])
        #expect(closed == [nil, aral])
    }
}

@MainActor
@Suite struct PayeeSettingsRuleTests {
    private func conditions(_ rules: [PayeeSettingsModel.RuleRow]) -> [PayeeRenameCondition] {
        rules.map { PayeeRenameCondition(id: $0.id, operator: $0.operator, text: $0.operand) }
    }

    @Test func rulesAreEditedLive() throws {
        let setup = PayeeSettingsFixture()
        let aral = setup.id("Aral")
        let (dialog, store) = setup.spied(on: "Aral")
        dialog.addRuleClicked()
        let rule = try #require(dialog.rules.first)
        #expect(rule.operator == .contains)
        #expect(dialog.focusRequest?.field == .operand(rule.id))
        #expect(!dialog.canRenameExisting)
        dialog.setOperand(rule.id, "ARAL ")
        dialog.setOperator(rule.id, .startsWith)
        #expect(
            store.commands.last
                == .setPayeeRenameConditions(
                    payeeId: aral, [PayeeRenameCondition(id: rule.id, operator: .startsWith, text: "ARAL ")]))
        #expect(dialog.canRenameExisting)
        dialog.addRuleClicked()
        #expect(dialog.rules.count == 2)
        #expect(!dialog.isLastRule(rule.id))
        dialog.removeRule(rule.id)
        #expect(store.commands.last == .setPayeeRenameConditions(payeeId: aral, conditions(dialog.rules)))
        #expect(dialog.rules.map(\.operand) == [""])
        #expect(store.commands.count == 5)
    }

    @Test func aRuleAddedByARenameSurvivesLaterEdits() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral", appliesCommands: true)
        dialog.startRenaming()
        dialog.renameText = "Aral Tankstelle"
        dialog.saveRename()
        #expect(dialog.rules.map(\.operand) == ["Aral"])
        dialog.addRuleClicked()
        dialog.setOperand(dialog.rules[1].id, "ARAL ")
        #expect(
            store.commands.last == .setPayeeRenameConditions(payeeId: setup.id("Aral"), conditions(dialog.rules)))
        #expect(dialog.rules.map(\.operand) == ["Aral", "ARAL "])
    }

    @Test func blankRulesDisappearWithTheSelection() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, _) = setup.spied(on: "Aral")
        dialog.addRuleClicked()
        dialog.selectionChanged(to: [setup.id("REWE")])
        dialog.selectionChanged(to: [setup.id("Aral")])
        #expect(dialog.rules.isEmpty)
    }

    @Test func renameExistingWithoutMatchesInforms() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral", appliesCommands: true)
        dialog.addRuleClicked()
        dialog.setOperand(dialog.rules[0].id, "Shell")
        dialog.renameExistingClicked()
        #expect(dialog.dialogs.presented.last?.dialog.instruction == "Keine Buchungen zum Umbenennen gefunden.")
        #expect(!store.commands.contains(.applyRenameRules(payeeId: setup.id("Aral"))))
    }

    @Test func renameExistingAsksFirst() throws {
        let setup = PayeeSettingsFixture()
        let rewe = setup.id("REWE")
        let (dialog, store) = setup.spied(on: "REWE", appliesCommands: true)
        dialog.addRuleClicked()
        dialog.setOperand(dialog.rules[0].id, "lid")
        dialog.renameExistingClicked()
        let confirm = try #require(dialog.dialogs.presented.last)
        #expect(confirm.dialog.title == "Buchungen umbenennen?")
        #expect(confirm.dialog.instruction == "Bei 1 Buchung wird der Empfänger in „REWE“ umbenannt:")
        #expect(confirm.dialog.content == "<b>Betroffene Empfänger:</b> „Lidl“")
        #expect(confirm.dialog.dismissal == AnyDialogChoice(RenameTransactionsChoice.cancel))
        confirm.answer(RenameTransactionsChoice.cancel)
        #expect(!store.commands.contains(.applyRenameRules(payeeId: rewe)))
        dialog.renameExistingClicked()
        dialog.dialogs.presented.last?.answer(RenameTransactionsChoice.rename)
        #expect(store.commands.last == .applyRenameRules(payeeId: rewe))
        #expect(dialog.transactionCount == 3)
    }
}

@MainActor
@Suite struct PayeeSettingsMultipleTests {
    @Test func combineSendsTheSelectionAndSelectsTheResult() throws {
        let setup = PayeeSettingsFixture()
        let (aral, lidl) = (setup.id("Aral"), setup.id("Lidl"))
        let (dialog, store) = setup.spied(on: "Aral", appliesCommands: true)
        dialog.commandClick(lidl)
        dialog.combineName = " Tanken & Einkaufen "
        dialog.combineClicked()
        #expect(store.commands == [.combinePayees([lidl, aral], name: "Tanken & Einkaufen")])
        let combined = try #require(store.budget.payee(named: "Tanken & Einkaufen"))
        #expect(dialog.selection == [combined.id])
        #expect(dialog.scrollRequest?.payeeId == combined.id)
    }

    @Test func combineNeedsANameAndShowsARefusal() throws {
        let setup = PayeeSettingsFixture()
        let (dialog, store) = setup.spied(on: "Aral")
        dialog.commandClick(setup.id("Lidl"))
        dialog.combineName = "   "
        #expect(!dialog.canCombine)
        dialog.combineClicked()
        #expect(store.commands.isEmpty)
        store.fail(with: BudgetError.transferPayeeName("Transfer : Depot"))
        dialog.combineName = "Transfer : Depot"
        dialog.combineClicked()
        #expect(dialog.dialogs.presented.last?.dialog.instruction == "Ungültiger Empfängername")
        #expect(dialog.selection.count == 2)
    }

    @Test func listingIsSwitchedForEverySelectedPayee() throws {
        let setup = PayeeSettingsFixture()
        let selected = [setup.id("Aral"), setup.id("Lidl"), setup.id("Transfer : Tagesgeld")]
        let (dialog, store) = setup.spied(on: "Aral")
        dialog.commandClick(selected[1])
        dialog.commandClick(selected[2])
        dialog.setSelectedPayeesEnabled(false)
        dialog.setSelectedPayeesEnabled(true)
        let newestFirst = Array(selected.reversed())
        #expect(store.commands == [.setPayeesHidden(newestFirst, true), .setPayeesHidden(newestFirst, false)])
    }
}
