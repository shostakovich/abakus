import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

/// The iPhone's and iPad's transaction sheet drives the Mac's editor, so a save makes the same command.
@MainActor
@Suite struct TransactionSheetTests {
    @Test func aPlainTransactionSavesAsTheMacSavesIt() throws {
        let fixture = RegisterFixture()
        let mac = fixture.spied()
        mac.model.addTransactionClicked()
        let row = try #require(mac.model.editor)
        row.retype("12/05/14")
        row.press(.tab)
        row.type("Bakery")
        row.press(.tab)
        row.retype("Groceries")
        row.press(.escape, .tab)
        row.type("Bread")
        row.press(.tab)
        row.type("4.80")
        row.activate(.save)

        let touch = fixture.spied()
        touch.model.addTransactionClicked()
        let sheet = try #require(touch.model.editor)
        sheet.datePicked(day("2014-05-12"))
        try sheet.choose(#require(sheet.newPayeeChoice("Bakery")), for: .main(.payee))
        try sheet.choose(sheet.choice("Groceries", for: .main(.category)), for: .main(.category))
        sheet.enter("Bread", in: .main(.memo))
        sheet.enter("4.80", in: .main(.amount))
        #expect(sheet.sheetConfirmButton == .save)
        sheet.activate(sheet.sheetConfirmButton)

        #expect(touch.model.editor == nil)
        let saves = Self.normalized(touch.store)
        #expect(saves.count == 1)
        #expect(saves == Self.normalized(mac.store))
        #expect(saves.first?.transaction.amount == decimal("-4.8"))
        #expect(saves.first?.transaction.categoryId == fixture.groceries)
    }

    @Test func aSplitSavesAsTheMacSavesIt() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -50)
        let mac = fixture.spied()
        mac.model.beginEditing(id, column: .category)
        let row = try #require(mac.model.editor)
        row.retype("Aufteilung")
        row.press(.escape, .tab)
        let (macFirst, macSecond) = (row.subIds[0], row.subIds[1])
        row.fieldClicked(.sub(macFirst, .category))
        row.retype("Everyday Expenses: Groceries")
        row.press(.escape)
        row.fieldClicked(.sub(macFirst, .amount))
        row.type("30")
        row.fieldClicked(.sub(macSecond, .amount))
        row.type("20")
        row.activate(.done)

        let touch = fixture.spied()
        touch.model.beginEditing(id)
        let sheet = try #require(touch.model.editor)
        sheet.choose(DefaultCategories.splitCategoryName, for: .main(.category))
        #expect(sheet.isSplitMode)
        let (first, second) = (sheet.subIds[0], sheet.subIds[1])
        try sheet.choose(sheet.choice("Groceries", for: .sub(first, .category)), for: .sub(first, .category))
        sheet.enter("30", in: .sub(first, .amount))
        sheet.enter("20", in: .sub(second, .amount))
        #expect(sheet.remainingAmount == 0)
        sheet.activate(sheet.sheetConfirmButton)

        let saves = Self.normalized(touch.store)
        #expect(saves.count == 1)
        #expect(saves == Self.normalized(mac.store))
        #expect(saves.first?.transaction.subtransactions.map(\.amount) == [-30, -20])
    }

    @Test func aTransferSavesAsTheMacSavesIt() throws {
        let fixture = RegisterFixture()
        let mac = fixture.spied()
        mac.model.makeTransferClicked()
        let row = try #require(mac.model.editor)
        row.press(.enter, .tab)
        row.type("50")
        row.activate(.save)

        let touch = fixture.spied()
        touch.model.makeTransferClicked()
        let sheet = try #require(touch.model.editor)
        let transfers = sheet.choices(for: .main(.payee), matching: sheet.text(.main(.payee)))
        let account = try #require(transfers.first { $0.isEnabled })
        #expect(account.label == "Tagesgeld")
        sheet.choose(account.value, for: .main(.payee))
        #expect(sheet.prompt(.main(.category)) == "(Keine Kategorie nötig)")
        sheet.enter("50", in: .main(.amount))
        sheet.activate(sheet.sheetConfirmButton)

        let saves = Self.normalized(touch.store)
        #expect(saves.count == 1)
        #expect(saves == Self.normalized(mac.store))
        #expect(saves.first?.transaction.payeeId == EntityID.transferPayee(accountId: fixture.tagesgeld))
    }

    @Test func theAmountWorksOutTypedArithmeticWhenTheKeypadCloses() throws {
        var fixture = RegisterFixture()
        fixture.budget.budgetMetaData = BudgetMetaData()
        let (model, _) = fixture.spied()
        model.addTransactionClicked()
        let sheet = try #require(model.editor)
        sheet.enter("12,50+7,30", in: .main(.amount))
        #expect(sheet.text(.main(.amount)) == "19,80")
        #expect(!sheet.isInflow(.main(.amount)))
        #expect(sheet.clone.amount == decimal("-19.8"))
        sheet.enter("5−7", in: .main(.amount))
        #expect(sheet.text(.main(.amount)) == "2,00")
        #expect(sheet.isInflow(.main(.amount)))
    }

    @Test func aLeadingSignCountsWithTheArithmeticAfterIt() throws {
        var fixture = RegisterFixture()
        fixture.budget.budgetMetaData = BudgetMetaData()
        let (model, _) = fixture.spied()
        model.addTransactionClicked()
        let sheet = try #require(model.editor)
        sheet.enter("−5−3", in: .main(.amount))
        #expect(sheet.clone.amount == -8)
        sheet.enter("−5+3", in: .main(.amount))
        #expect(sheet.clone.amount == -2)
        sheet.enter("+5−8", in: .main(.amount))
        #expect(sheet.clone.amount == -3)
        sheet.enter("-2+7", in: .main(.amount))
        #expect(sheet.clone.amount == 5)
        #expect(sheet.text(.main(.amount)) == "5,00")
        sheet.enter("−4", in: .main(.amount))
        #expect(sheet.clone.amount == -4)
        sheet.enter("+4", in: .main(.amount))
        #expect(sheet.clone.amount == 4)
    }

    @Test func aSavedTransactionChangesTheBalanceAndAvailableAtOnce() throws {
        let fixture = RegisterFixture()
        let (model, store) = fixture.spied(appliesCommands: true)
        let balance = store.budget.balances(forAccount: fixture.giro).working
        let available = store.budget.categoryBalances(today: editDay)[fixture.groceries] ?? 0
        model.addTransactionClicked()
        let sheet = try #require(model.editor)
        try sheet.choose(#require(sheet.newPayeeChoice("Bäckerei")), for: .main(.payee))
        try sheet.choose(sheet.choice("Groceries", for: .main(.category)), for: .main(.category))
        sheet.enter("4.80", in: .main(.amount))
        sheet.activate(sheet.sheetConfirmButton)
        #expect(store.budget.balances(forAccount: fixture.giro).working == balance - decimal("4.8"))
        #expect(store.budget.categoryBalances(today: editDay)[fixture.groceries] == available - decimal("4.8"))
    }

    @Test func aSplitLineAddedByAnAmountDoesNotTakeTheKeyboard() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -50)
        let (model, _) = fixture.spied()
        model.beginEditing(id)
        let sheet = try #require(model.editor)
        sheet.choose(DefaultCategories.splitCategoryName, for: .main(.category))
        let second = sheet.subIds[1]
        sheet.sheetFieldFocused(.sub(second, .amount))
        sheet.sheetTextChanged(.sub(second, .amount), to: "10")
        sheet.sheetFieldFocused(.main(.memo))
        #expect(sheet.subIds.count == 3)
        #expect(sheet.focusedField == .main(.memo))
        sheet.sheetTextChanged(.main(.memo), to: "Wocheneinkauf")
        sheet.sheetFieldUnfocused(.main(.memo))
        #expect(sheet.clone.memo == "Wocheneinkauf")
    }

    @Test func aTransactionWaitingForApprovalConfirmsWithApprove() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, approved: false, source: .bank)
        let (model, store) = fixture.spied()
        model.beginEditing(id)
        let sheet = try #require(model.editor)
        #expect(sheet.sheetConfirmButton == .approve)
        #expect(sheet.sheetMoreButtons == [.approveAndFindNext])
        #expect(sheet.sheetStatus == .waiting)
        #expect(sheet.sheetDeletes)
        sheet.activate(sheet.sheetConfirmButton)
        #expect(store.transactionSaves.first?.transaction.approved == true)
    }

    @Test func theStatusRowSwitchesBetweenVorgemerktAndGebuchtAtOnce() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let reconciled = fixture.add(fixture.giro, -5, cleared: .reconciled)
        let (model, store) = fixture.spied(appliesCommands: true)
        model.beginEditing(id)
        let sheet = try #require(model.editor)
        #expect(sheet.sheetStatus == .uncleared)
        sheet.sheetStatusChosen(.cleared)
        #expect(store.commands.last == .toggleCleared([id]))
        #expect(sheet.sheetStatus == .cleared)
        sheet.activate(.cancel)

        model.beginEditing(reconciled)
        let locked = try #require(model.editor)
        let count = store.commands.count
        locked.sheetStatusChosen(.uncleared)
        #expect(locked.sheetStatus == .reconciled)
        #expect(store.commands.count == count)
    }

    @Test func aNewTransactionHasNoStatusAndNoDelete() throws {
        let fixture = RegisterFixture()
        let (model, _) = fixture.spied()
        model.addTransactionClicked()
        let sheet = try #require(model.editor)
        #expect(sheet.sheetStatus == nil)
        #expect(!sheet.sheetDeletes)
        #expect(sheet.sheetMoreButtons == [.saveAndAddAnother])
    }

    @Test func thePayeePickerOffersASearchedNameOnlyWhenItIsNew() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -4)
        let (model, _) = fixture.spied()
        model.addTransactionClicked()
        let sheet = try #require(model.editor)
        #expect(sheet.newPayeeChoice("Shop") == nil)
        #expect(sheet.newPayeeChoice(" Kiosk ") == "Kiosk")
        #expect(sheet.newPayeeChoice("") == nil)
        #expect(
            sheet.choices(for: .main(.payee), matching: "Tages").map(\.label) == ["Umbuchung mit Konto:", "Tagesgeld"])
    }

    @Test func aLedTransactionKeepsWhatItsSourceLeads() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -30, payee: "Kasse", source: .kasse)
        let index = try #require(fixture.budget.transactions.firstIndex { $0.id == id })
        fixture.budget.transactions[index].ledBy = .kasse
        let (model, store) = fixture.spied()
        model.beginEditing(id)
        let sheet = try #require(model.editor)
        sheet.enter("99", in: .main(.amount))
        sheet.datePicked(day("2014-05-01"))
        sheet.choose("Bakery", for: .main(.payee))
        try sheet.choose(sheet.choice("Groceries", for: .main(.category)), for: .main(.category))
        #expect(!sheet.choices(for: .main(.category), matching: "").contains { $0.kind == .split })
        sheet.activate(sheet.sheetConfirmButton)
        let saved = try #require(store.transactionSaves.first).transaction
        #expect(saved.amount == -30)
        #expect(saved.date == day("2014-05-10"))
        #expect(saved.categoryId == fixture.groceries)
        #expect(store.transactionSaves.first?.payeeName == nil)
    }

    @Test func theSignTakesEffectWithoutTheKeyboard() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let (model, store) = fixture.spied()
        model.beginEditing(id)
        let sheet = try #require(model.editor)
        sheet.sheetFieldFocused(.main(.memo))
        sheet.sheetSignToggled(.main(.amount))
        #expect(sheet.clone.amount == 4)
        sheet.sheetTextChanged(.main(.memo), to: "Pfand")
        sheet.sheetFieldUnfocused(.main(.memo))
        sheet.activate(sheet.sheetConfirmButton)
        let saved = try #require(store.transactionSaves.first).transaction
        #expect(saved.amount == 4)
        #expect(saved.memo == "Pfand")
    }

    @Test func theSignButtonWinsOverASignTypedBeforeIt() throws {
        var fixture = RegisterFixture()
        fixture.budget.budgetMetaData = BudgetMetaData()
        let (model, _) = fixture.spied()
        model.addTransactionClicked()
        let sheet = try #require(model.editor)
        sheet.sheetFieldFocused(.main(.amount))
        sheet.sheetTextChanged(.main(.amount), to: "−5")
        sheet.sheetSignToggled(.main(.amount))
        #expect(sheet.text(.main(.amount)) == "5")
        sheet.sheetFieldUnfocused(.main(.amount))
        #expect(sheet.clone.amount == 5)

        sheet.sheetFieldFocused(.main(.amount))
        sheet.sheetTextChanged(.main(.amount), to: "−5−3")
        sheet.sheetSignToggled(.main(.amount))
        sheet.sheetFieldUnfocused(.main(.amount))
        #expect(sheet.clone.amount == 8)
    }

    @Test func swipingAwayIsHeldBackOnlyByChanges() throws {
        let (model, _) = RegisterFixture().spied()
        model.addTransactionClicked()
        let sheet = try #require(model.editor)
        #expect(!sheet.keepsSheet)
        sheet.sheetFieldFocused(.main(.memo))
        sheet.sheetTextChanged(.main(.memo), to: "B")
        #expect(sheet.keepsSheet)
    }

    @Test func aScheduledTransactionSavesAsTheMacSavesIt() throws {
        let fixture = RegisterFixture()
        let mac = fixture.spied()
        mac.model.scheduler.addClicked()
        let row = try #require(mac.model.scheduler.editor)
        row.retype("12/06/14")
        row.press(.tab)
        row.press(.down)
        row.press(.tab)
        row.type("Gym")
        row.press(.tab, .tab, .tab)
        row.type("30")
        row.activate(.save)

        let touch = fixture.spied()
        touch.model.scheduler.addClicked()
        let sheet = try #require(touch.model.scheduler.editor)
        sheet.datePicked(day("2014-06-12"))
        sheet.frequencyChosen(.everyOtherMonth)
        try sheet.choose(#require(sheet.newPayeeChoice("Gym")), for: .main(.payee))
        sheet.enter("30", in: .main(.amount))
        #expect(sheet.sheetTitle == "Neue geplante Buchung")
        sheet.activate(sheet.sheetConfirmButton)

        #expect(touch.model.scheduler.editor == nil)
        let saves = Self.scheduledSaves(touch.store)
        #expect(saves.count == 1)
        #expect(saves == Self.scheduledSaves(mac.store))
        #expect(saves.first?.frequency == .everyOtherMonth)
        #expect(saves.first?.transaction.amount == -30)
    }

    @Test func theSheetIsTitledAfterWhatItEdits() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10)
        fixture.addSchedule("S1")
        let (model, _) = fixture.spied()
        model.addTransactionClicked()
        #expect(model.editor?.sheetTitle == "Neue Buchung")
        model.editor?.cancel()
        model.beginEditing(id)
        #expect(model.editor?.sheetTitle == "Buchung")
        model.editor?.cancel()
        model.scheduler.beginEditing("S1")
        #expect(model.scheduler.editor?.sheetTitle == "Geplante Buchung")
    }

    static func scheduledSaves(_ store: SpyBudgetStore) -> [ScheduledSave] {
        store.commands.compactMap {
            guard case .saveScheduledTransaction(var save) = $0 else { return nil }
            if save.isNew { save.transaction.id = "new" }
            return save
        }
    }

    /// New transactions and split lines get fresh ids each time.
    static func normalized(_ store: SpyBudgetStore) -> [TransactionSave] {
        store.transactionSaves.map { save in
            var save = save
            let subIds = save.transaction.subtransactions.map(\.id)
            func line(_ id: String) -> String { subIds.firstIndex(of: id).map { "line\($0)" } ?? id }
            if save.isNew { save.transaction.id = "new" }
            for index in save.transaction.subtransactions.indices {
                save.transaction.subtransactions[index].id = "line\(index)"
                save.transaction.subtransactions[index].transactionId = save.transaction.id
            }
            save.subPayeeNames = Dictionary(uniqueKeysWithValues: save.subPayeeNames.map { (line($0.key), $0.value) })
            return save
        }
    }
}

extension TransactionEditor {
    /// What the keyboard does to a sheet's text field: focus, type, close.
    func enter(_ text: String, in field: EditorFieldID) {
        sheetFieldFocused(field)
        sheetTextChanged(field, to: text)
        sheetFieldUnfocused(field)
    }

    func choice(_ search: String, for field: EditorFieldID) throws -> String {
        let enabled = choices(for: field, matching: search).first { $0.isEnabled }
        return try #require(enabled).value
    }
}
