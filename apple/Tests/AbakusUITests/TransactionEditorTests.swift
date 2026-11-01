import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct EditLifecycleTests {
    @Test func secondClickOnTheOnlySelectedRowEditsTheClickedField() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, memo: "Brot")
        let (model, _) = fixture.spied()
        let row = try #require(model.rows.first { $0.id == id })
        model.rowClicked(row, column: .memo, modifiers: [])
        #expect(model.editor == nil)
        model.rowClicked(row, column: .memo, modifiers: [])
        let editor = try #require(model.editor)
        #expect(model.editingTransactionId == id)
        #expect(editor.focusedField == .main(.memo))
        #expect(editor.selectedText == "Brot")
    }

    @Test func enterOnASingleSelectionEditsStartingWithTheDate() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -4)
        let (model, _) = fixture.spied()
        model.selectAll()
        model.grid.editSelected()
        #expect(model.editor == nil)
        model.grid.navigationKeyPressed(.down, extending: false, caretOnly: false, pageRows: 1)
        model.grid.editSelected()
        let editor = try #require(model.editor)
        #expect(editor.focusedField == .main(.date))
        #expect(editor.text(.main(.date)) == "29/04/14")
        #expect(editor.buttons == [.done, .cancel])
    }

    @Test func addingANewTransactionUsesTheAccountAndTodayThenTheLastUsedDate() throws {
        let fixture = RegisterFixture()
        let (model, store) = fixture.spied(appliesCommands: true)
        model.addTransactionClicked()
        let editor = try #require(model.editor)
        #expect(model.grid.isAdding)
        #expect(editor.clone.accountId == fixture.giro)
        #expect(editor.text(.main(.date)) == "20/05/14")
        #expect(editor.buttons == [.saveAndAddAnother, .save, .cancel])
        #expect(editor.focusedField == .main(.date))
        editor.retype("12/05/14")
        editor.press(.tab)
        editor.type("Bakery")
        editor.press(.tab, .tab, .tab)
        editor.type("3")
        editor.press(.enter)
        let next = try #require(model.editor)
        #expect(next !== editor)
        #expect(next.text(.main(.date)) == "12/05/14")
        let save = try #require(store.transactionSaves.first)
        #expect(store.commands.count == 1)
        #expect(save.isNew)
        #expect(save.payeeName == "Bakery")
        #expect(save.transaction.amount == -3)
        #expect(save.transaction.date == day("2014-05-12"))
        #expect(model.selectedTransactionIds.isEmpty)
        next.activate(.cancel)
        model.addTransactionClicked()
        #expect(model.editor?.text(.main(.date)) == "12/05/14")
    }

    @Test func allAccountsStartsInTheFirstOpenAccountAndOffersTheAccountField() throws {
        let fixture = RegisterFixture()
        let (model, _) = fixture.spied(selection: .allAccounts)
        model.addTransactionClicked()
        let editor = try #require(model.editor)
        #expect(editor.clone.accountId == fixture.giro)
        #expect(editor.mainColumns().first == .account)
        #expect(editor.tabOrder.first == .field(.main(.account)))
        editor.fieldClicked(.main(.account))
        #expect(editor.dropDown?.kind == .account)
        #expect(editor.dropDown?.items.map(\.label) == ["Giro", "Tagesgeld", "Karte", "Trackingkonten", "Depot"])
        editor.retype("Ta")
        #expect(editor.text(.main(.account)) == "Tagesgeld")
        editor.press(.tab)
        #expect(editor.clone.accountId == fixture.tagesgeld)
        #expect(editor.focusedField == .main(.date))
    }

    @Test func emptyNewTransactionIsDiscarded() throws {
        let (model, store) = RegisterFixture().spied()
        model.addTransactionClicked()
        try #require(model.editor).activate(.save)
        #expect(model.editor == nil)
        #expect(store.commands.isEmpty)
    }

    @Test func makeATransferPrefillsThePayeeAndHighlightsTheFirstAccount() throws {
        let (model, _) = RegisterFixture().spied()
        model.grid.beginNew(transfer: true)
        let editor = try #require(model.editor)
        #expect(editor.focusedField == .main(.payee))
        #expect(editor.text(.main(.payee)) == "Transfer : ")
        let list = try #require(editor.dropDown)
        #expect(list.items.map(\.label).prefix(2) == [DropDownItem.emptyPayeesPrompt, "Umbuchung mit Konto:"])
        #expect(list.highlightedItem?.value == "Transfer : Tagesgeld")
        editor.press(.enter)
        #expect(editor.text(.main(.payee)) == "Transfer : Tagesgeld")
        #expect(editor.clone.payeeId == EntityID.transferPayee(accountId: "TAGES"))
        #expect(editor.focusedField == .main(.memo))
        #expect(editor.prompt(.main(.category)) == "(Keine Kategorie nötig)")
    }

    @Test func clickingAnotherRowWithChangesGlowsInsteadOfLeaving() throws {
        var fixture = RegisterFixture()
        let first = fixture.add(fixture.giro, -4)
        let second = fixture.add(fixture.giro, -5)
        let (model, _) = fixture.spied()
        model.beginEditing(first, column: .memo)
        let editor = try #require(model.editor)
        editor.type("Neu")
        let other = try #require(model.rows.first { $0.id == second })
        model.rowClicked(other, column: .payee, modifiers: [])
        #expect(editor.glowCount == 1)
        #expect(model.editor === editor)
        #expect(model.selectedTransactionIds == [first])
        editor.activate(.cancel)
        model.beginEditing(first, column: .memo)
        model.rowClicked(other, column: .payee, modifiers: [])
        #expect(model.editor == nil)
        #expect(model.selectedTransactionIds == [second])
    }

    @Test func aClickOutsideProtectsChangedSplitLines() throws {
        var fixture = RegisterFixture()
        let id = "SPLIT"
        fixture.add(
            fixture.giro, -50, id: id,
            subtransactions: [
                Subtransaction(id: "L1", transactionId: id, amount: -30, categoryId: fixture.groceries),
                Subtransaction(id: "L2", transactionId: id, amount: -20),
            ])
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .memo)
        var editor = try #require(model.editor)
        #expect(!editor.clickedOutside())
        model.beginEditing(id, column: .memo)
        editor = try #require(model.editor)
        editor.fieldClicked(.sub("L1", .payee))
        editor.retype("Bakery")
        editor.press(.tab)
        #expect(editor.clickedOutside())
        #expect(editor.glowCount == 1)
        editor.activate(.cancel)
        model.beginEditing(id, column: .memo)
        editor = try #require(model.editor)
        editor.fieldClicked(.sub("L2", .memo))
        editor.type("Seife")
        #expect(editor.clickedOutside())
    }

    @Test func switchingAccountsDropsTheEditor() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, _) = fixture.spied()
        model.beginEditing(id)
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(model.editor == nil)
        model.navigation.selection = .account(fixture.giro)
        #expect(model.editor == nil)
    }
}

@MainActor
@Suite struct EditorKeyboardTests {
    @Test func tabFollowsTheVisibleColumnsThenTheButtonsAndWraps() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, _) = fixture.spied()
        model.beginEditing(id)
        let editor = try #require(model.editor)
        var visited: [EditorFocus] = [try #require(editor.focus)]
        for _ in 0..<8 {
            editor.press(.tab)
            visited.append(try #require(editor.focus))
        }
        #expect(
            visited == [
                .field(.main(.date)), .field(.main(.payee)), .field(.main(.category)), .field(.main(.memo)),
                .field(.main(.outflow)), .field(.main(.inflow)), .button(.done), .button(.cancel),
                .field(.main(.date)),
            ])
        editor.press(.backTab)
        #expect(editor.focus == .button(.cancel))
    }

    @Test func tabFromMemoSkipsOutflowForIncome() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, 100, category: fixture.budget.readyToAssignCategoryId)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .memo)
        let editor = try #require(model.editor)
        editor.press(.tab)
        #expect(editor.focusedField == .main(.inflow))
    }

    @Test func escapeRestoresAChangedFieldThenCancels() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, memo: "Brot")
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .memo)
        let editor = try #require(model.editor)
        editor.retype("Kuchen")
        editor.press(.escape)
        #expect(editor.text(.main(.memo)) == "Brot")
        #expect(model.editor === editor)
        editor.press(.escape)
        #expect(model.editor == nil)
    }

    @Test func enterSavesThroughTheDefaultButton() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        var edited = try #require(fixture.budget.transaction(withId: id))
        edited.memo = "Brötchen"
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .memo)
        try #require(model.editor).type("Brötchen")
        model.editor?.press(.enter)
        #expect(model.editor == nil)
        #expect(
            store.commands == [.saveTransaction(TransactionSave(transaction: edited, payeeName: nil, isNew: false))])
        #expect(model.selectedTransactionIds == [id])
        #expect(model.grid.scrollRequest?.target == .row(id))
    }

    @Test func dateShortcutsMoveTheDate() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, on: "2014-05-10")
        let (model, _) = fixture.spied()
        model.beginEditing(id)
        let editor = try #require(model.editor)
        editor.press(.character("+"))
        #expect(editor.text(.main(.date)) == "11/05/14")
        #expect(editor.isCalendarOpen)
        editor.press(.escape)
        #expect(!editor.isCalendarOpen)
        editor.press(.down, .down)
        #expect(editor.text(.main(.date)) == "09/05/14")
        editor.press(.character("m"))
        #expect(editor.text(.main(.date)) == "01/05/14")
        editor.press(.character("M"))
        #expect(editor.text(.main(.date)) == "31/05/14")
        editor.press(.character("y"))
        #expect(editor.text(.main(.date)) == "01/01/14")
        editor.press(.character("R"))
        #expect(editor.text(.main(.date)) == "31/12/14")
        editor.press(.character("t"))
        #expect(editor.text(.main(.date)) == "20/05/14")
        editor.calendarDatePicked(day("2014-05-03"))
        #expect(editor.clone.date == day("2014-05-03"))
    }

    @Test func anUnreadableDateRevertsShowsTheCalloutAndBlocksTheSave() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, on: "2014-05-10")
        let (model, store) = fixture.spied()
        model.beginEditing(id)
        let editor = try #require(model.editor)
        editor.retype("abc")
        editor.press(.tab)
        #expect(editor.text(.main(.date)) == "10/05/14")
        #expect(editor.dateCallout?.title == "Ungültiges Datum")
        #expect(
            editor.dateCallout?.message
                == "Nicht verstanden: „<b>abc</b>“<br/>Datum im Format <b>TT/MM/JJ</b> eingeben.")
        #expect(editor.focusedField == .main(.date))
        editor.retype("01/01/40")
        editor.press(.tab)
        #expect(editor.dateCallout?.message.hasPrefix("Datum außerhalb des Bereichs: „<b>01/01/40</b>“") == true)
        editor.retype("15/05/14")
        editor.activate(.done)
        #expect(model.editor === editor)
        #expect(store.commands.isEmpty)
        editor.activate(.done)
        #expect(store.transactionSaves.map(\.transaction.date) == [day("2014-05-15")])
    }

    @Test func buttonsTakeEnterAndSpaceWhenFocused() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .inflow)
        let editor = try #require(model.editor)
        editor.press(.tab, .tab)
        #expect(editor.focus == .button(.cancel))
        editor.press(.enter)
        #expect(model.editor == nil)
    }
}

@MainActor
@Suite struct PayeeFieldTests {
    func editor(_ fixture: RegisterFixture, _ id: String) throws -> TransactionEditor {
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .payee)
        return try #require(model.editor)
    }

    @Test func typingCompletesTheFirstPayeeThatStartsWithTheText() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "Walmart")
        fixture.add(fixture.giro, -1, payee: "Wasserwerk")
        let id = fixture.add(fixture.giro, -4, payee: "Shop")
        let editor = try editor(fixture, id)
        editor.retype("wa")
        let list = try #require(editor.dropDown)
        #expect(list.items.map(\.label) == ["Walmart", "Wasserwerk"])
        #expect(list.highlightedItem?.label == "Walmart")
        #expect(editor.text(.main(.payee)) == "walmart")
        #expect(editor.selectedText == "lmart")
        editor.type("s")
        #expect(editor.text(.main(.payee)) == "wasserwerk")
        editor.press(.tab)
        #expect(editor.payeeName == "Wasserwerk")
        #expect(editor.text(.main(.payee)) == "Wasserwerk")
        #expect(editor.focusedField == .main(.category))
    }

    @Test func aColonThatDoesNotStartATransferStillHighlightsThePayee() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "Amazon: Prime")
        let id = fixture.add(fixture.giro, -4, payee: "Shop")
        let editor = try editor(fixture, id)
        editor.retype("amazon:")
        #expect(editor.dropDown?.highlightedItem?.label == "Amazon: Prime")
        #expect(editor.text(.main(.payee)) == "amazon: Prime")
        editor.retype("tr:")
        #expect(editor.dropDown?.highlightedItem?.label == "Tagesgeld")
    }

    @Test func containsMatchesAreListedButNotHighlighted() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "Walmart")
        let id = fixture.add(fixture.giro, -4, payee: "Shop")
        let editor = try editor(fixture, id)
        editor.retype("mart")
        #expect(editor.dropDown?.items.map(\.label) == ["Walmart"])
        #expect(editor.dropDown?.highlighted == nil)
        editor.press(.enter)
        #expect(editor.dropDown == nil)
        #expect(editor.focusedField == .main(.payee))
        editor.press(.tab)
        #expect(editor.payeeName == "mart")
    }

    @Test func arrowKeysSkipHeadersAndRewriteTheText() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, payee: "Shop")
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .payee)
        let editor = try #require(model.editor)
        editor.retype("")
        editor.press(.down)
        let list = try #require(editor.dropDown)
        #expect(list.items.map(\.label) == ["Shop", "Umbuchung mit Konto:", "Tagesgeld", "Karte", "Depot"])
        editor.press(.down)
        #expect(editor.dropDown?.highlightedItem?.label == "Shop")
        editor.press(.down)
        #expect(editor.dropDown?.highlightedItem?.label == "Tagesgeld")
        #expect(editor.text(.main(.payee)) == "Transfer : Tagesgeld")
        editor.press(.escape)
        #expect(editor.dropDown == nil)
        #expect(model.editor === editor)
        #expect(editor.focusedField == .main(.payee))
    }

    @Test func transferPrefixCompletesTheAccountName() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, payee: "Shop")
        let editor = try editor(fixture, id)
        editor.retype("tr:")
        #expect(editor.text(.main(.payee)) == "Transfer : Tagesgeld")
        #expect(editor.selectedText == "Tagesgeld")
        editor.type("k")
        #expect(editor.dropDown?.items.map(\.label) == ["Umbuchung mit Konto:", "Karte"])
    }

    @Test func backspaceWithTheListOpenDeletesToTheEnd() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "Walmart")
        let id = fixture.add(fixture.giro, -4, payee: "Shop")
        let editor = try editor(fixture, id)
        editor.retype("wal")
        #expect(editor.text(.main(.payee)) == "walmart")
        editor.backspace()
        #expect(editor.text(.main(.payee)) == "wal")
        #expect(editor.dropDown == nil)
        editor.backspace()
        #expect(editor.text(.main(.payee)) == "wa")
        #expect(editor.dropDown == nil)
    }

    @Test func invalidTransfersAreRefusedWithTheOriginalDialogs() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, payee: "Shop")
        let editor = try editor(fixture, id)
        editor.retype("Transfer : Nirgendwo")
        editor.press(.tab)
        #expect(editor.taskDialog?.instruction == "Ungültiger Empfänger")
        #expect(
            editor.taskDialog?.content
                == "„Nirgendwo“ ist kein gültiger Kontoname. Beginnt ein Empfänger mit „Transfer :“, muss ein "
                + "gültiger Kontoname folgen.")
        #expect(editor.text(.main(.payee)) == "Shop")
        editor.answer(MessageChoice.close)
        editor.fieldClicked(.main(.payee))
        editor.retype("Transfer : Giro")
        editor.press(.tab)
        #expect(editor.taskDialog?.instruction == "Ein Konto kann nicht auf sich selbst umbuchen.")
    }

    @Test func memorizedCategoryIsFilledIn() throws {
        var fixture = RegisterFixture()
        let bakery = Transaction(accountId: fixture.giro, date: editDay, categoryId: fixture.groceries, amount: -1)
        try fixture.budget.apply(
            .saveTransaction(TransactionSave(transaction: bakery, payeeName: "Bakery", isNew: true)))
        let (model, _) = fixture.spied()
        model.addTransactionClicked()
        let editor = try #require(model.editor)
        editor.fieldClicked(.main(.payee))
        editor.type("Bak")
        editor.press(.tab)
        #expect(editor.clone.categoryId == fixture.groceries)
        #expect(editor.text(.main(.category)) == "Everyday Expenses: Groceries")
        #expect(editor.focusedField == .main(.category))
    }

    @Test func properCapitalizationOnCommit() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "Walmart")
        let id = fixture.add(fixture.giro, -4, payee: "Shop")
        let editor = try editor(fixture, id)
        editor.retype("walmart")
        editor.press(.escape)
        editor.press(.tab)
        #expect(editor.text(.main(.payee)) == "Walmart")
    }
}

@MainActor
@Suite struct CategoryFieldTests {
    @Test func listGroupsByMasterWithZuVerteilenAndBalances() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, on: "2014-05-10", category: fixture.groceries)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        let list = try #require(editor.dropDown)
        #expect(
            list.items.prefix(6).map(\.label)
                == [
                    "Aufteilung", "Einnahmen:", "Zu verteilen", "Giving:", "Tithing",
                    "Charitable",
                ])
        #expect(list.highlightedItem?.label == "Groceries")
        let groceries = try #require(list.items.first { $0.label == "Groceries" })
        #expect(groceries.balance == -4)
        #expect(editor.selectedText == "Everyday Expenses: Groceries")
    }

    @Test func prefixAndMasterColonMatching() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("gro")
        #expect(editor.dropDown?.items.map(\.label) == ["Everyday Expenses:", "Groceries"])
        #expect(editor.text(.main(.category)) == "groceries")
        editor.retype("rainy:")
        #expect(editor.text(.main(.category)) == "Rainy Day Funds: Emergency Fund")
        #expect(editor.selectedText == "Emergency Fund")
        editor.retype("Rainy Day Funds: c")
        #expect(
            editor.dropDown?.items.map(\.label) == ["Rainy Day Funds:", "Car Repairs", "Car Insurance", "Christmas"])
        editor.press(.enter)
        #expect(editor.text(.main(.category)) == "Rainy Day Funds: Car Repairs")
        #expect(editor.focusedField == .main(.memo))
        editor.fieldClicked(.main(.category))
        editor.retype("zu")
        #expect(editor.text(.main(.category)) == "zu verteilen")
        editor.press(.tab)
        #expect(editor.clone.categoryId == fixture.budget.readyToAssignCategoryId)
    }

    @Test func theSplitItemIsHighlightedOnlyWhenNoCategoryMatches() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("sp")
        #expect(editor.dropDown?.highlightedItem?.label == "Spending Money")
        #expect(editor.text(.main(.category)) == "spending Money")
        editor.retype("aufte")
        #expect(editor.dropDown?.highlightedItem?.label == DefaultCategories.splitCategoryName)
    }

    @Test func unknownCategoryOpensTheNewCategoryDialogPrefilled() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, store) = fixture.spied(appliesCommands: true)
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Hobby: Bücher")
        editor.press(.tab)
        let form = try #require(editor.addCategoryForm)
        #expect(form.masterName == "Hobby")
        #expect(form.name == "Bücher")
        editor.addCategoryConfirmed(masterName: "Hobby", name: "Bücher")
        #expect(store.commands == [.addNamedCategory(groupName: "Hobby", name: "Bücher")])
        #expect(!editor.hasOpenDialog)
        #expect(editor.text(.main(.category)) == "Hobby: Bücher")
        #expect(store.budget.category(fullName: "Hobby: Bücher")?.id == editor.clone.categoryId)
        #expect(editor.focusedField == .main(.memo))
        editor.fieldClicked(.main(.category))
        editor.paste("Einnahmen: Bonus")
        editor.press(.tab)
        #expect(editor.taskDialog?.instruction == "Bitte einen anderen Kategorienamen wählen.")
        #expect(store.commands.count == 1)
    }

    @Test func aRefusedNewCategoryKeepsTheFormOpen() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Hobby: Bücher")
        editor.press(.tab)
        store.fail(with: BudgetError.duplicateCategoryName)
        editor.addCategoryConfirmed(masterName: "Hobby", name: "Bücher")
        let form = try #require(editor.addCategoryForm)
        #expect(editor.taskDialog?.instruction == "Bitte einen anderen Kategorienamen wählen.")
        #expect(editor.taskDialog?.content == BudgetError.duplicateCategoryName.errorDescription)
        editor.answer(MessageChoice.close)
        #expect(editor.addCategoryForm?.refocusRequest == form.refocusRequest + 1)
        #expect(editor.clone.categoryId == nil)
    }

    @Test func splitCannotBeChosenForATransfer() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, target: fixture.depot)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Aufteilung")
        editor.press(.escape, .tab)
        #expect(editor.taskDialog?.instruction == "Diese Buchung lässt sich nicht aufteilen.")
        #expect(!editor.isSplitMode)
    }
}

@MainActor
@Suite struct AmountFieldTests {
    @Test func oneSignedAmountBehindTwoFields() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .inflow)
        let editor = try #require(model.editor)
        editor.retype("12.5")
        editor.press(.backTab)
        #expect(editor.text(.main(.inflow)) == "12.50")
        #expect(editor.text(.main(.outflow)) == "")
        #expect(editor.clone.amount == 12.5)
        editor.press(.tab)
        #expect(editor.clone.amount == 12.5)
        editor.press(.backTab)
        editor.retype("-1,234")
        editor.press(.tab)
        #expect(editor.text(.main(.inflow)) == "1,234.00")
        #expect(editor.clone.amount == 1234)
        editor.press(.backTab)
        editor.retype("7")
        editor.press(.tab)
        #expect(editor.text(.main(.outflow)) == "7.00")
        #expect(editor.text(.main(.inflow)) == "")
        editor.retype("0")
        editor.press(.backTab)
        #expect(editor.clone.amount == -7)
    }

    @Test func operatorsOpenTheCalculator() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .outflow)
        let editor = try #require(model.editor)
        editor.type("+")
        #expect(editor.calculator?.calculator.display == "10.00")
        editor.type("5")
        editor.press(.enter)
        #expect(editor.calculator == nil)
        #expect(editor.text(.main(.outflow)) == "15.00")
        editor.press(.tab)
        #expect(editor.clone.amount == -15)
        editor.press(.backTab)
        editor.retype("")
        editor.type("-")
        #expect(editor.calculator == nil)
        #expect(editor.text(.main(.outflow)) == "-")
    }
}

@MainActor
@Suite struct SplitEditorTests {
    @Test func choosingSplitAddsTwoLinesAndTracksTheRemainder() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -50)
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("aufte")
        editor.press(.tab)
        #expect(editor.isSplitMode)
        #expect(editor.subIds.count == 2)
        #expect(editor.focusedField == .main(.memo))
        #expect(editor.remainingTexts == ("$50.00", "$0.00"))
        let first = editor.subIds[0]
        editor.fieldClicked(.sub(first, .category))
        editor.retype("Groceries")
        editor.press(.escape)
        editor.retype("Everyday Expenses: Groceries")
        editor.press(.escape, .tab, .tab)
        #expect(editor.focusedField == .sub(first, .outflow))
        editor.type("30")
        editor.press(.tab)
        #expect(editor.remainingTexts == ("$20.00", "$0.00"))
        #expect(editor.subIds.count == 2)
        let second = editor.subIds[1]
        editor.fieldClicked(.sub(second, .outflow))
        editor.type("10")
        editor.press(.tab)
        #expect(editor.subIds.count == 3)
        #expect(editor.focusedField == .sub(editor.subIds[2], .payee))
        editor.activate(.done)
        #expect(editor.taskDialog?.instruction == "Was soll mit den noch nicht aufgeteilten <b>-$10.00</b> geschehen?")
        editor.answer(UnassignedChoice.manuallyAdjust)
        #expect(model.editor === editor)
        editor.activate(.done)
        editor.answer(UnassignedChoice.autoDistribute)
        #expect(model.editor == nil)
        let saved = try #require(store.transactionSaves.first).transaction
        #expect(store.commands.count == 1)
        #expect(saved.categoryId == nil && saved.isSplit)
        #expect(saved.subtransactions.map(\.amount) == [decimal("-37.5"), decimal("-12.5")])
        #expect(saved.subtransactions.map(\.categoryId) == [fixture.groceries, nil])
    }

    @Test func adjustOriginalSetsTheTotal() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -50)
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Aufteilung")
        editor.press(.escape, .tab)
        let first = editor.subIds[0]
        editor.fieldClicked(.sub(first, .outflow))
        editor.type("20")
        editor.activate(.done)
        #expect(editor.taskDialog?.dismissal == AnyDialogChoice(UnassignedChoice.cancel))
        editor.answer(UnassignedChoice.cancel)
        #expect(!editor.dialogs.isPresenting)
        #expect(store.commands.isEmpty)
        #expect(model.editor === editor)
        editor.activate(.done)
        editor.answer(UnassignedChoice.adjustTotal)
        let saved = try #require(store.transactionSaves.first).transaction
        #expect(saved.amount == -20)
        #expect(saved.subtransactions.map(\.amount) == [-20])
    }

    @Test func splitLinesTakeTransfersFromThePayeeList() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -50)
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Aufteilung")
        editor.press(.escape, .tab)
        let first = editor.subIds[0]
        editor.fieldClicked(.sub(first, .payee))
        #expect(editor.prompt(.sub(first, .payee)) == "Empfänger")
        editor.type("tr:t")
        #expect(editor.dropDown?.kind == .payee)
        #expect(editor.dropDown?.highlightedItem?.value == "Transfer : Tagesgeld")
        editor.press(.tab)
        #expect(editor.text(.sub(first, .payee)) == "Transfer : Tagesgeld")
        #expect(editor.prompt(.sub(first, .category)) == "(Keine Kategorie nötig)")
        #expect(editor.focusedField == .sub(first, .memo))
        editor.retype("Sparen")
        editor.press(.tab)
        editor.type("50")
        editor.activate(.done)
        let save = try #require(store.transactionSaves.first)
        let line = try #require(save.transaction.subtransactions.first)
        #expect(save.transaction.subtransactions.count == 1)
        #expect(save.subPayeeNames == [first: "Transfer : Tagesgeld"])
        #expect(line.payeeId == EntityID.transferPayee(accountId: fixture.tagesgeld))
        #expect(line.memo == "Sparen")
        #expect(line.amount == -50)
    }

    @Test func splitLinesTakeTheirOwnPayeeAndItsCategory() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -4, payee: "Bakery")
        let bakery = try #require(fixture.budget.payee(named: "Bakery")).id
        try fixture.budget.apply(.setPayeeLastCategory(payeeId: bakery, categoryId: fixture.groceries))
        let id = fixture.add(fixture.giro, -50)
        let (model, store) = fixture.spied(appliesCommands: true)
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Aufteilung")
        editor.press(.escape, .tab)
        let (first, second) = (editor.subIds[0], editor.subIds[1])
        editor.fieldClicked(.sub(first, .payee))
        editor.type("Bak")
        #expect(editor.dropDown?.highlightedItem?.value == "Bakery")
        editor.press(.tab)
        #expect(editor.text(.sub(first, .category)) == "Everyday Expenses: Groceries")
        editor.fieldClicked(.sub(first, .outflow))
        editor.type("30")
        editor.fieldClicked(.sub(second, .payee))
        editor.type("Kiosk")
        editor.fieldClicked(.sub(second, .outflow))
        editor.type("20")
        editor.activate(.done)
        #expect(store.transactionSaves.first?.subPayeeNames == [first: "Bakery", second: "Kiosk"])
        let saved = try #require(store.budget.transaction(withId: id))
        #expect(saved.subtransactions.map { store.budget.payeeName(of: $0) } == ["Bakery", "Kiosk"])
        #expect(saved.subtransactions.map(\.categoryId) == [fixture.groceries, nil])
    }

    @Test func escapeRestoresALinePayee() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "Kiosk")
        let kiosk = try #require(fixture.budget.payee(named: "Kiosk")).id
        let id = "SPLIT"
        fixture.add(
            fixture.giro, -50, id: id,
            subtransactions: [
                Subtransaction(id: "L1", transactionId: id, amount: -30, payeeId: kiosk),
                Subtransaction(id: "L2", transactionId: id, amount: -20),
            ])
        let (model, store) = fixture.spied(appliesCommands: true)
        model.beginEditing(id, column: .memo)
        let editor = try #require(model.editor)
        editor.fieldClicked(.sub("L1", .payee))
        #expect(editor.text(.sub("L1", .payee)) == "Kiosk")
        editor.retype("Bakery")
        editor.press(.tab)
        editor.fieldClicked(.sub("L1", .payee))
        editor.press(.escape)
        #expect(editor.text(.sub("L1", .payee)) == "Kiosk")
        editor.activate(.done)
        #expect(store.budget.transaction(withId: id)?.subtransactions.first?.payeeId == kiosk)
        #expect(store.budget.payee(named: "Bakery") == nil)
    }

    @Test func aTransferWithATrackingAccountSuggestsTheCategoryLastUsedBetweenThem() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -80, on: "2014-05-01", category: fixture.groceries, target: fixture.depot)
        fixture.add(
            fixture.karte, -10, on: "2014-05-08", category: fixture.category("Monthly Bills", "Rent/Mortgage"),
            target: fixture.depot)
        let id = fixture.add(fixture.giro, -50)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .payee)
        let editor = try #require(model.editor)
        editor.retype("Transfer : Depot")
        editor.press(.tab)
        #expect(editor.clone.categoryId == fixture.groceries)
        #expect(editor.text(.main(.category)) == "Everyday Expenses: Groceries")
    }

    @Test func aSplitLineTransferWithATrackingAccountSuggestsTheCategory() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -80, on: "2014-05-01", category: fixture.groceries, target: fixture.depot)
        let id = fixture.add(fixture.giro, -50)
        let (model, _) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Aufteilung")
        editor.press(.escape, .tab)
        let first = editor.subIds[0]
        editor.fieldClicked(.sub(first, .payee))
        editor.type("Transfer : Depot")
        editor.press(.tab)
        #expect(editor.clone.subtransactions.first?.categoryId == fixture.groceries)
        #expect(editor.text(.sub(first, .category)) == "Everyday Expenses: Groceries")
    }

    @Test func choosingANormalCategoryLeavesSplitMode() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -50)
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Aufteilung")
        editor.press(.escape, .tab)
        editor.fieldClicked(.main(.category))
        editor.retype("Groceries")
        editor.press(.tab)
        #expect(!editor.isSplitMode)
        editor.activate(.done)
        let saved = try #require(store.transactionSaves.first).transaction
        #expect(saved.categoryId == fixture.groceries)
        #expect(saved.subtransactions.isEmpty)
    }
}

@MainActor
@Suite struct EditorRulesTests {
    @Test func reconciledTransactionsAskBeforeSaving() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, cleared: .reconciled)
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .outflow)
        let editor = try #require(model.editor)
        editor.retype("5")
        editor.activate(.done)
        let dialog = try #require(editor.taskDialog)
        #expect(dialog.title == "Abgeglichene Buchung ändern")
        #expect(dialog.buttons.map(\.title) == ["Ändern", "Abbrechen"])
        #expect(dialog.defaultChoice == AnyDialogChoice(ReconciledChoice.keep))
        editor.answer(ReconciledChoice.keep)
        #expect(model.editor == nil)
        #expect(store.commands.isEmpty)
        model.beginEditing(id, column: .outflow)
        model.editor?.retype("5")
        model.editor?.activate(.done)
        model.editor?.answer(ReconciledChoice.change)
        let save = try #require(store.transactionSaves.first)
        #expect(save.transaction.amount == -5)
        #expect(save.confirmedReconciledChange)
    }

    @Test func unapprovedTransactionsOfferApproveAndFindNext() throws {
        var fixture = RegisterFixture()
        let first = fixture.add(fixture.giro, -4, on: "2014-05-01", approved: false, source: .bank)
        let second = fixture.add(fixture.giro, -5, on: "2014-05-02", approved: false, source: .bank)
        let (model, store) = fixture.spied()
        model.beginEditing(first)
        let editor = try #require(model.editor)
        #expect(editor.buttons == [.approveAndFindNext, .approve, .delete, .cancel])
        editor.activate(.approveAndFindNext)
        #expect(store.transactionSaves.map(\.transaction.id) == [first])
        #expect(store.transactionSaves.map(\.transaction.approved) == [true])
        #expect(model.editingTransactionId == second)
        model.editor?.activate(.delete)
        #expect(store.commands.last == .deleteTransactions([second]))
    }

    @Test func editingAnUnapprovedTransactionApprovesIt() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, approved: false, source: .bank)
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .memo)
        model.editor?.type("geprüft")
        model.editor?.press(.tab)
        model.editor?.activate(.cancel)
        #expect(store.commands.isEmpty)
        model.beginEditing(id, column: .memo)
        model.editor?.type("geprüft")
        model.editor?.activate(.approve)
        #expect(store.transactionSaves.map(\.transaction.approved) == [true])
        #expect(store.transactionSaves.map(\.transaction.memo) == ["geprüft"])
    }

    @Test func payeeRenameAsksAboutTheOtherTransactions() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, payee: "Rewe")
        fixture.add(fixture.giro, -5, payee: "Rewe")
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .payee)
        let editor = try #require(model.editor)
        editor.retype("REWE City")
        #expect(editor.dropDown == nil)
        editor.activate(.done)
        let dialog = try #require(editor.taskDialog)
        #expect(dialog.instruction == "Passende Buchungen auch ändern?")
        #expect(dialog.commandLinks.map(\.title) == ["Umbenennen", "Unverändert lassen"])
        #expect(dialog.checkbox == "Bei diesem Empfänger nicht mehr fragen")
        #expect(dialog.dismissal == AnyDialogChoice(PayeeRenameChoice.cancel))
        editor.answer(PayeeRenameChoice.cancel)
        #expect(!editor.dialogs.isPresenting)
        #expect(store.commands.isEmpty)
        #expect(model.editor === editor)
        editor.activate(.done)
        editor.answer(PayeeRenameChoice.rename)
        #expect(model.editor == nil)
        let save = try #require(store.transactionSaves.first)
        #expect(save.payeeName == "REWE City")
        #expect(save.payeeRename == PayeeRename(choice: .rename))
    }

    @Test func renamingCanCategorizeTheOthers() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, payee: "Rewe")
        fixture.add(fixture.giro, -5, payee: "Rewe")
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .payee)
        let editor = try #require(model.editor)
        editor.retype("REWE City")
        editor.press(.tab)
        editor.retype("Groceries")
        editor.press(.tab)
        editor.activate(.done)
        #expect(
            editor.taskDialog?.commandLinks.map(\.title) == [
                "Umbenennen und kategorisieren", "Nur umbenennen", "Unverändert lassen",
            ])
        editor.answer(PayeeRenameChoice.renameAndCategorize)
        #expect(model.editor == nil)
        #expect(store.transactionSaves.map(\.payeeRename) == [PayeeRename(choice: .renameAndCategorize)])
        #expect(store.transactionSaves.map(\.transaction.categoryId) == [fixture.groceries])
    }

    @Test func leavingTheOthersAloneCanStopTheBulkRename() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, payee: "Rewe")
        fixture.add(fixture.giro, -5, payee: "Rewe")
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .payee)
        let editor = try #require(model.editor)
        editor.retype("REWE City")
        editor.activate(.done)
        editor.answer(PayeeRenameChoice.leave, isChecked: true)
        #expect(model.editor == nil)
        #expect(store.transactionSaves.map(\.payeeRename) == [PayeeRename(choice: .leave, stopAsking: true)])
    }

    @Test func incomeCategorizedOutflowAsksJustChecking() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, store) = fixture.spied(appliesCommands: true)
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Zu verteilen")
        editor.press(.tab)
        editor.activate(.done)
        #expect(store.transactionSaves.map(\.transaction.categoryId) == [fixture.budget.readyToAssignCategoryId])
        #expect(model.incomeCheck?.transactionId == id)
        var swapped = try #require(store.budget.transaction(withId: id))
        swapped.amount = 4
        model.incomeCheckAnswered(swap: true)
        #expect(store.commands.last == .updateTransaction(swapped))
        #expect(model.incomeCheck == nil)
    }

    @Test func aTransferBecomesAPaymentAndAPaymentATransfer() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -40, target: fixture.tagesgeld)
        let (model, store) = fixture.spied(appliesCommands: true)
        model.beginEditing(id, column: .payee)
        let editor = try #require(model.editor)
        editor.retype("Shop")
        editor.press(.escape)
        editor.activate(.done)
        model.beginEditing(id, column: .payee)
        model.editor?.retype("Transfer : Karte")
        model.editor?.press(.tab)
        model.editor?.activate(.done)
        #expect(store.transactionSaves.map(\.payeeName) == ["Shop", "Transfer : Karte"])
        #expect(
            store.transactionSaves.map { store.budget.transferAccountId(of: $0.transaction) } == [nil, fixture.karte])
        #expect(store.transactionSaves.last?.transaction.transferTransactionId == nil)
    }
}
