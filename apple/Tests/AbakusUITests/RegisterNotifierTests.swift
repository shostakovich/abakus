import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterNotifierTests {
    @Test func cleanAccountShowsNoNotifier() {
        let (model, _) = RegisterFixture().spied()
        #expect(model.notifiers.list.isEmpty)
    }

    @Test func noticesAreShortChipsWithTheFullTextAsTooltip() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1)
        fixture.add(fixture.giro, -2)
        fixture.add(fixture.giro, -3, category: fixture.groceries, approved: false, source: .bank)
        let (model, _) = fixture.spied()
        let notifiers = model.notifiers.list
        #expect(notifiers.map(\.kind) == [.warning, .reminder])
        #expect(notifiers[0].text == "2 brauchen eine Kategorie")
        #expect(notifiers[0].tooltip == "2 Buchungen brauchen eine Kategorie")
        #expect(notifiers[0].link == nil)
        #expect(notifiers[1].text == "1 bestätigen")
        #expect(notifiers[1].tooltip == "1 Buchung ist zu bestätigen")
    }

    @Test func aChipReadsItsTextAndLinkToVoiceOver() {
        let undo = RegisterNotifier(kind: .undo, text: "Buchung gelöscht", link: "Widerrufen")
        #expect(NotifierView.accessibilityLabel(undo) == "Buchung gelöscht, Widerrufen")
        let reminder = RegisterNotifier(kind: .reminder, text: "1 bestätigen")
        #expect(NotifierView.accessibilityLabel(reminder) == "1 bestätigen")
    }

    @Test func errorNotifierComesFirst() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, category: fixture.groceries, target: fixture.tagesgeld)
        fixture.add(fixture.giro, -1)
        let (model, _) = fixture.spied()
        let notifiers = model.notifiers.list
        #expect(notifiers.map(\.kind) == [.error, .warning])
        #expect(notifiers[0].text == "1 Umbuchung mit Kategorie")
        #expect(notifiers[0].tooltip == "1 Umbuchung zwischen Budgetkonten hat eine Kategorie")
        #expect(notifiers[1].text == "1 braucht eine Kategorie")
    }

    @Test func pluralTexts() {
        var fixture = RegisterFixture()
        for amount in [-1, -2] {
            fixture.add(fixture.giro, Decimal(amount), category: fixture.groceries, approved: false, source: .bank)
        }
        let (model, _) = fixture.spied()
        #expect(model.notifiers.list.first?.text == "2 bestätigen")
    }

    @Test func clickingANotifierSearchesItsRows() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1)
        let (model, _) = fixture.spied()
        model.notifiers.clicked(.warning)
        #expect(model.search.text == "Ist: Nicht kategorisiert, ")
        #expect(model.transactionIds == [id])
    }

    @Test func allAccountsAddsUpEveryAccount() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1)
        fixture.add(fixture.tagesgeld, -1)
        let (model, _) = fixture.spied(selection: .allAccounts)
        #expect(model.notifiers.list.first?.text == "2 brauchen eine Kategorie")
    }

    @Test func undoNotifierSitsLastWithItsMessage() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries)
        let (model, _) = fixture.spied()
        model.rowClicked(model.rows.first { $0.id == id }!, column: .payee, modifiers: [])
        model.deleteKeyPressed()
        #expect(model.notifiers.list.map(\.text) == ["Buchung gelöscht"])
        #expect(model.notifiers.list.first?.link == "Widerrufen")
    }
}

@MainActor
@Suite struct RegisterIconColumnTests {
    @Test func clearedClickTogglesTheRow() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries, approved: false, source: .bank)
        let (model, store) = fixture.spied()
        model.clearedClicked(model.rows.first { $0.id == id }!)
        #expect(store.commands == [.toggleCleared([id])])
        #expect(model.selectedTransactionIds == [id])
    }

    @Test func clearedClickOnASelectedRowTogglesTheWholeSelection() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1)
        fixture.add(fixture.giro, -2, cleared: .cleared)
        let (model, store) = fixture.spied()
        model.selectAll()
        let all = model.selectedTransactionIds
        model.clearedClicked(model.rows.first { $0.id == a }!)
        #expect(store.commands == [.toggleCleared(all)])
        #expect(all.count == 3)
    }

    @Test func clearedClickWhileEditingWritesTheStoredRowAndSurvivesDone() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries)
        var cleared = fixture.budget
        cleared.transactions[cleared.transactions.firstIndex { $0.id == id }!].cleared = .cleared
        let (model, store) = fixture.spied()
        model.beginEditing(id)
        store.budgetAfterNextCommand = cleared
        model.clearedClicked(model.rows.first { $0.id == id }!)
        #expect(store.commands == [.toggleCleared([id])])
        #expect(model.editor?.clone.cleared == .cleared)
        model.editor?.activate(.done)
        #expect(model.editor == nil)
    }

    @Test func keyboardToggleUsesTheBulkRule() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, cleared: .cleared)
        let b = fixture.add(fixture.giro, -2, cleared: .cleared)
        let (model, store) = fixture.spied()
        model.rowClicked(model.rows.first { $0.id == a }!, column: nil, modifiers: .command)
        model.rowClicked(model.rows.first { $0.id == b }!, column: nil, modifiers: .command)
        model.toggleClearedKeyPressed()
        #expect(store.commands == [.toggleCleared([b, a])])
    }

    @Test func keyboardToggleReachesTheAddEditorWithoutSelection() {
        let (model, store) = RegisterFixture().spied()
        model.addTransactionClicked()
        #expect(model.selectedTransactionIds.isEmpty)
        #expect(RegisterCommand.toggleCleared.isEnabled(in: model))
        RegisterCommand.toggleCleared.perform(in: model)
        #expect(model.editor?.clone.cleared == .cleared)
        #expect(store.commands.isEmpty)
    }

    @Test func theCheckApprovesTheSelectedUnapprovedRowsAtOnce() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, category: fixture.groceries, approved: false, source: .bank)
        let b = fixture.add(fixture.giro, -2, category: fixture.groceries, approved: false, source: .bank)
        let (model, store) = fixture.spied()
        model.selectAll()
        model.errorIconClicked(model.rows.first { $0.id == a }!)
        #expect(store.commands == [.approveTransactions([b, a])])
        #expect(model.popup == nil)
    }

    @Test func needsCategoryPopupFillsTheCategory() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1)
        let (model, store) = fixture.spied()
        model.errorIconClicked(model.rows.first { $0.id == a }!)
        #expect(model.statusPopupTitle == "Kategorie für die ausgewählte Buchung wählen")
        model.needsCategoryChosen(fixture.groceries)
        #expect(store.commands == [.fillMissingCategory([a], categoryId: fixture.groceries)])
    }

    @Test func removeCategoryPopupFixesTransfers() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, category: fixture.groceries, target: fixture.tagesgeld)
        let (model, store) = fixture.spied()
        model.errorIconClicked(model.rows.first { $0.id == a }!)
        #expect(model.statusPopupTitle == "1 ausgewählte Umbuchung")
        #expect(model.statusPopupOptions.map(\.title) == ["Kategorie entfernen"])
        model.statusPopupChosen(.removeCategory)
        #expect(store.commands == [.removeTransferCategories([a])])
    }

    @Test func approveShortcutApprovesTheSelection() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, category: fixture.groceries, approved: false, source: .bank)
        let (model, store) = fixture.spied()
        model.rowClicked(model.rows.first { $0.id == a }!, column: .payee, modifiers: [])
        model.approveKeyPressed()
        #expect(store.commands == [.approveTransactions([a])])
    }

    @Test func selectAllShortcutLeavesTextFieldsAlone() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1)
        let (model, _) = fixture.spied()
        #expect(model.selectAllKeyPressed())
        #expect(model.selection.count == 2)
        model.clearSelection()
        model.search.focusChanged(true)
        #expect(!model.selectAllKeyPressed())
        #expect(model.selection.isEmpty)
    }

    @Test func deleteKeyIsIgnoredWhileEditing() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1)
        let (model, store) = fixture.spied()
        model.beginEditing(a)
        model.deleteKeyPressed()
        #expect(store.commands.isEmpty)
    }

    @Test func deleteKeyIsIgnoredInTheSearchBox() throws {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1)
        let (model, store) = fixture.spied()
        model.rowClicked(try #require(model.rows.first { $0.id == a }), column: .payee, modifiers: [])
        model.search.focusChanged(true)
        model.deleteKeyPressed()
        #expect(store.commands.isEmpty)
        #expect(model.notifiers.undoSlot == nil)
        model.search.focusChanged(false)
        model.deleteKeyPressed()
        #expect(store.commands == [.deleteTransactions([a])])
    }

    @Test func switchingAccountsClosesMenusAndPopups() {
        let fixture = RegisterFixture()
        let (model, _) = fixture.spied()
        model.search.dateSelectorClicked()
        model.search.boxChanged("x")
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(model.popup == nil)
        #expect(model.search.timeframe == nil)
        #expect(model.search.dropDown == nil)
        model.columnOptionsClicked()
        model.navigation.selection = .account(fixture.giro)
        #expect(model.menuRequest == nil)
    }

    @Test func transferIconJumpsToTheOtherSide() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, target: fixture.tagesgeld)
        let (model, _) = fixture.spied()
        model.transferIconClicked(model.rows.first { $0.id == a }!)
        let counterpart = model.store.budget.transactions.first { $0.transferTransactionId == a }!
        #expect(model.navigation.selection == .account(fixture.tagesgeld))
        #expect(model.selectedTransactionIds == [counterpart.id])
    }

    @Test func aJumpToAHiddenOtherSideClearsThatAccountsSearch() throws {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, target: fixture.tagesgeld)
        let (model, _) = fixture.spied()
        let counterpart = try #require(model.store.budget.transaction(withId: a)?.transferTransactionId)
        model.navigation.selection = .account(fixture.tagesgeld)
        model.search.run("Empfänger: nobody")
        #expect(!model.transactionIds.contains(counterpart))
        model.navigation.selection = .account(fixture.giro)
        model.transferIconClicked(try #require(model.rows.first { $0.id == a }))
        #expect(model.navigation.selection == .account(fixture.tagesgeld))
        #expect(model.search.filter == nil)
        #expect(model.search.text.isEmpty)
        #expect(model.transactionIds.contains(counterpart))
        #expect(model.selectedTransactionIds == [counterpart])
    }
}

@MainActor
@Suite struct RegisterColumnMenuTests {
    @Test func columnMenuListsHideableColumnsThenApplyToAll() {
        let (model, _) = RegisterFixture().spied()
        let menu = model.columnMenu
        #expect(
            menu.map(\.title) == [
                "Status", "Memo", "Laufender Saldo", "", "Für alle Konten übernehmen",
            ])
        #expect(menu[0].isChecked)
        #expect(!menu[2].isChecked)
    }

    @Test func columnTabAndHeaderRightClickOfferTheColumnMenu() {
        let (model, _) = RegisterFixture().spied()
        model.columnOptionsClicked()
        #expect(model.menuRequest?.anchor == .columnTab)
        #expect(model.menuRequest?.items == model.columnMenu)
        #expect(model.headerContextMenu() == model.columnMenu)
    }

    @Test func togglingFromTheMenuShowsTheColumn() {
        let (model, _) = RegisterFixture().spied()
        model.performMenuAction(.toggleColumn(.runningBalance))
        #expect(model.visibleColumns.contains(.runningBalance))
        #expect(model.columnMenu.item(titled: "Laufender Saldo")?.isChecked == true)
    }

    @Test func applyToAllCopiesTheSettings() {
        let fixture = RegisterFixture()
        let (model, _) = fixture.spied()
        model.performMenuAction(.toggleColumn(.memo))
        model.performMenuAction(.applyColumnsToAllAccounts)
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(!model.visibleColumns.contains(.memo))
    }

    @Test func runningBalanceFollowsTheAccountOrder() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -11, on: "2014-05-02")
        let (model, _) = fixture.spied()
        model.performMenuAction(.toggleColumn(.runningBalance))
        model.grid.headerClicked(.date)
        #expect(model.rows.first { $0.id == a }?.runningBalance == "1,100.00")
        #expect(model.rows.last?.id == a)
    }

    @Test func runningBalanceTooltipShowsTheBalancesThroughTheDate() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -11, on: "2014-05-02")
        fixture.add(fixture.giro, -5, on: "2014-05-03")
        let (model, _) = fixture.spied()
        let row = model.rows.first { $0.id == a }!
        model.runningBalanceHovered(row, inside: true)
        #expect(model.popup == .runningBalance(rowId: a))
        let info = model.runningBalanceInfo(for: a)
        #expect(info?.title == "Saldo bis 02/05/14:")
        #expect(info?.lines.map(\.amount) == ["$1,111.00", "-$11.00", "$1,100.00"])
        #expect(info?.lines.last?.caption == "Arbeitssaldo (das Geld, das am 02/05/14 da war)")
        model.runningBalanceHovered(row, inside: false)
        #expect(model.popup == nil)
    }
}
