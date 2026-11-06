import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

/// What the iPhone and the iPad show differently from the Mac, and what they reach from everywhere.
@MainActor
@Suite struct RegisterTouchTests {
    private func touch(_ fixture: RegisterFixture, selection: SidebarSelection? = nil, appliesCommands: Bool = false)
        -> (model: RegisterViewModel, store: SpyBudgetStore)
    {
        let spied = fixture.spied(selection: selection, appliesCommands: appliesCommands)
        spied.model.isTouch = true
        return spied
    }

    @Test func listsWriteNoTwoDigitYearAndAnotherYearInFull() {
        var fixture = RegisterFixture()
        let now = fixture.add(fixture.giro, -5, on: "2014-05-10", payee: "Bakery")
        let earlier = fixture.add(fixture.giro, -5, on: "2013-12-24", payee: "Bakery")
        let (model, _) = touch(fixture)
        model.grid.headerClicked(.payee)
        let dates = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.transactionId, $0.date) })
        #expect(dates[now] == "10/05")
        #expect(dates[earlier] == "24/12/2013")

        let (mac, _) = fixture.spied()
        mac.grid.headerClicked(.payee)
        #expect(mac.rows.first { $0.transactionId == now }?.date == "10/05/14")
    }

    @Test func aSwipedDeleteThatAsksKeepsTheRowUntilItIsConfirmed() {
        var fixture = RegisterFixture()
        let reconciled = fixture.add(fixture.giro, -5, cleared: .reconciled)
        let (model, store) = touch(fixture, appliesCommands: true)
        model.performMenuAction(.delete, on: [reconciled])
        #expect(model.dialogs.presented.count == 1)
        model.dialogs.presented.last?.answer(DeleteChoice.cancel)
        #expect(store.commands.isEmpty)
        #expect(model.transactionIds.contains(reconciled))
    }

    @Test func approvalsShowAlleKontenInTheViewZuBestaetigenAndApproveAllAtOnce() throws {
        var fixture = RegisterFixture()
        let first = fixture.add(fixture.giro, -1, approved: false, source: .bank)
        let second = fixture.add(fixture.tagesgeld, -2, approved: false, source: .bank)
        fixture.add(fixture.giro, -3)
        let (model, store) = touch(fixture, appliesCommands: true)
        #expect(model.approvalCount == 2)
        #expect(model.approvalsLine == nil)

        model.showApprovals()
        #expect(model.navigation.selection == .allAccounts)
        #expect(model.filter == .unapproved)
        #expect(Set(model.transactionIds) == [first, second])
        #expect(model.approvalsLine == "2 Buchungen warten auf Bestätigung.")
        #expect(RegisterViewModel.approvalsTitle(2) == "2 Buchungen bestätigen")
        #expect(RegisterViewModel.approvalsTitle(1) == "1 Buchung bestätigen")

        model.approveAllClicked()
        guard case .approveTransactions(let approved) = try #require(store.commands.last) else {
            Issue.record("Nothing approved")
            return
        }
        #expect(Set(approved) == [first, second])
        #expect(model.approvalCount == 0)
        #expect(model.approvalsLine == nil)
        #expect(model.transactionIds.isEmpty)
    }

    @Test func theViewMenuHoldsTheViewsThenGeplantAndAuswaehlenThenKontoBearbeitenEachWithASymbol() {
        let (model, _) = touch(RegisterFixture())
        let menu = model.touchViewMenu(showsColumns: false)
        #expect(
            menu.map(\.title) == [
                "Alle Buchungen", "Zu bestätigen", "Vorgemerkt", "Ohne Kategorie", "", "Geplant", "Auswählen", "",
                "Konto bearbeiten",
            ])
        #expect(menu.filter { $0.kind != .separator }.allSatisfy { $0.systemImage != nil })
        #expect(menu.filter(\.isChecked).map(\.title) == ["Alle Buchungen"])
        #expect(menu.allSatisfy { !$0.title.contains("…") })

        let wide = model.touchViewMenu(showsColumns: true)
        #expect(wide.map(\.title).suffix(4) == ["Auswählen", "Memo ausblenden", "", "Konto bearbeiten"])
        guard case .action(let action) = wide.item(titled: "Memo ausblenden")?.kind else {
            Issue.record("No memo item")
            return
        }
        model.performMenuAction(action)
        #expect(model.touchViewMenu(showsColumns: true).item(titled: "Memo zeigen") != nil)
        #expect(!model.visibleColumns.contains(.memo))
    }

    @Test func geplantShowsTheSchedulerAndKontoBearbeitenEditsTheAccount() {
        let (model, _) = touch(RegisterFixture())
        var edits = 0
        model.onEditAccount = { edits += 1 }
        model.performMenuAction(.toggleScheduler)
        #expect(model.isSchedulerVisible)
        model.performMenuAction(.editAccount)
        #expect(edits == 1)
    }

    @Test func alleKontenHasNoKontoBearbeiten() {
        let (model, _) = touch(RegisterFixture(), selection: .allAccounts)
        #expect(model.touchViewMenu(showsColumns: false).item(titled: "Konto bearbeiten") == nil)
    }

    @Test func aNewTransactionTakesTheRegistersAccountElseTheLastUsedOne() throws {
        let fixture = RegisterFixture()
        let (model, _) = touch(fixture, selection: .account(fixture.tagesgeld), appliesCommands: true)
        model.addTransactionClicked()
        let first = try #require(model.editor)
        #expect(first.clone.accountId == fixture.tagesgeld)
        #expect(first.choosesAccount)
        first.enter("4.80", in: .main(.amount))
        first.activate(.save)

        model.navigation.selection = .budget
        model.addTransactionClicked()
        let second = try #require(model.editor)
        #expect(second.clone.accountId == fixture.tagesgeld)
        try second.choose(second.choice("Karte", for: .main(.account)), for: .main(.account))
        #expect(second.clone.accountId == fixture.karte)
    }

    @Test func aNewTransactionSkipsTheLastUsedAccountOnceItIsClosed() throws {
        let fixture = RegisterFixture()
        let (model, store) = touch(fixture, selection: .account(fixture.tagesgeld), appliesCommands: true)
        model.addTransactionClicked()
        let first = try #require(model.editor)
        first.enter("4.80", in: .main(.amount))
        first.activate(.save)
        var tagesgeld = try #require(store.budget.account(withId: fixture.tagesgeld))
        tagesgeld.closed = true
        try store.perform(.editAccount(tagesgeld))

        model.navigation.selection = .budget
        model.addTransactionClicked()
        #expect(try #require(model.editor).clone.accountId == fixture.giro)
    }

    @Test func theMacAddsToTheFirstBudgetAccountOutsideAnAccountsRegister() throws {
        let fixture = RegisterFixture()
        let (model, _) = fixture.spied(selection: .account(fixture.tagesgeld), appliesCommands: true)
        model.addTransactionClicked()
        let first = try #require(model.editor)
        first.enter("4.80", in: .main(.amount))
        first.activate(.save)

        model.navigation.selection = .allAccounts
        model.addTransactionClicked()
        #expect(try #require(model.editor).clone.accountId == fixture.giro)
    }

    @Test func theSheetNamesACategoryWithoutItsGroupAndATransferByItsAccount() throws {
        var fixture = RegisterFixture()
        let groceries = fixture.add(fixture.giro, -5, category: fixture.groceries)
        let transfer = fixture.add(fixture.giro, -9, target: fixture.tagesgeld)
        let (model, _) = touch(fixture)

        model.beginEditing(groceries)
        let sheet = try #require(model.editor)
        #expect(sheet.text(.main(.category)) == "Everyday Expenses: Groceries")
        #expect(sheet.sheetValue(.main(.category)) == EditorSheetValue(text: "Groceries"))
        #expect(sheet.sheetValue(.main(.date)).text == "10/05/2014")
        sheet.cancel()

        model.beginEditing(transfer)
        let moved = try #require(model.editor)
        #expect(moved.sheetValue(.main(.payee)) == EditorSheetValue(text: "Tagesgeld", isTransfer: true))
        #expect(!moved.choosesAccount)
        #expect(!moved.showsCategory)
        moved.cancel()

        let tracked = fixture.add(fixture.giro, -9, target: fixture.depot)
        let (other, _) = touch(fixture)
        other.beginEditing(tracked)
        #expect(try #require(other.editor).showsCategory)
    }

    @Test func aSplitReadsAufgeteiltWithItsPartsByCategoryAndAmount() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -50)
        let (model, _) = touch(fixture)
        model.beginEditing(id)
        let sheet = try #require(model.editor)
        try sheet.choose(sheet.choice("Aufteilung", for: .main(.category)), for: .main(.category))
        #expect(sheet.sheetValue(.main(.category)).text == "Aufgeteilt (2)")
        let part = try #require(sheet.subIds.first)
        try sheet.choose(sheet.choice("Groceries", for: .sub(part, .category)), for: .sub(part, .category))
        sheet.enter("30", in: .sub(part, .amount))
        #expect(
            sheet.partSummary(part)
                == EditorPartSummary(category: "Groceries", hasCategory: true, amount: "−$30.00", isInflow: false))
        let empty = try #require(sheet.subIds.last)
        #expect(!sheet.partSummary(empty).hasCategory)
    }
}
