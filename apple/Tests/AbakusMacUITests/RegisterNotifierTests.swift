import AbakusCore
import Foundation
import Testing

@testable import AbakusMacUI
@testable import AbakusUI
@testable import AbakusUITests

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
        #expect(NotifierLabel.accessibilityLabel(undo) == "Buchung gelöscht, Widerrufen")
        let reminder = RegisterNotifier(kind: .reminder, text: "1 bestätigen")
        #expect(NotifierLabel.accessibilityLabel(reminder) == "1 bestätigen")
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

    @Test func clickingANotifierShowsItsView() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1)
        let (model, _) = fixture.spied()
        model.notifiers.clicked(.warning)
        #expect(model.filter == .needsCategory)
        #expect(model.viewMenuTitle == "Ansicht: ohne Kategorie")
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

    @Test func clearedClickOnASelectedRowTogglesOnlyThatRow() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1)
        fixture.add(fixture.giro, -2, cleared: .cleared)
        let (model, store) = fixture.spied()
        model.selectAll()
        model.clearedClicked(model.rows.first { $0.id == a }!)
        #expect(store.commands == [.toggleCleared([a])])
        #expect(model.selectedTransactionIds.count == 3)
    }

    @Test func theLockAsksBeforeItUnlocksAReconciledRow() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries, cleared: .reconciled)
        let (model, store) = fixture.spied()
        model.clearedClicked(model.rows.first { $0.id == id }!)
        let dialog = try #require(model.dialogs.presented.last)
        #expect(dialog.dialog.instruction == "Diese Buchung ist abgeglichen. Entsperren?")
        #expect(dialog.dialog.buttons.map(\.title) == ["Abbrechen", "Entsperren"])
        #expect(store.commands.isEmpty)
        dialog.answer(UnlockChoice.unlock)
        #expect(store.commands == [.setCleared([id], .cleared)])
    }

    @Test func theLockStaysLockedWithoutTheConfirmation() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries, cleared: .reconciled)
        let (model, store) = fixture.spied()
        model.clearedClicked(model.rows.first { $0.id == id }!)
        try #require(model.dialogs.presented.last).answer(UnlockChoice.cancel)
        #expect(store.commands.isEmpty)
    }

    @Test func theCheckOnASelectedRowApprovesOnlyThatRow() {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, category: fixture.groceries, approved: false, source: .bank)
        fixture.add(fixture.giro, -2, category: fixture.groceries, approved: false, source: .bank)
        let (model, store) = fixture.spied()
        model.selectAll()
        model.errorIconClicked(model.rows.first { $0.id == a }!)
        #expect(store.commands == [.approveTransactions([a])])
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

    @Test func switchingAccountsClosesMenus() {
        let fixture = RegisterFixture()
        let (model, _) = fixture.spied(selection: .account(fixture.tagesgeld))
        model.scheduledToggleClicked()
        model.scheduler.columnOptionsClicked()
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

    @Test func aJumpToAHiddenOtherSideClearsThatAccountsSearchAndView() throws {
        var fixture = RegisterFixture()
        let a = fixture.add(fixture.giro, -1, target: fixture.tagesgeld)
        let (model, _) = fixture.spied()
        let counterpart = try #require(model.store.budget.transaction(withId: a)?.transferTransactionId)
        model.navigation.selection = .account(fixture.tagesgeld)
        model.search.run("nobody")
        model.viewMenuChosen(.filter(.needsCategory))
        #expect(!model.transactionIds.contains(counterpart))
        model.navigation.selection = .account(fixture.giro)
        model.transferIconClicked(try #require(model.rows.first { $0.id == a }))
        #expect(model.navigation.selection == .account(fixture.tagesgeld))
        #expect(model.filter == .all)
        #expect(model.search.text.isEmpty)
        #expect(model.transactionIds.contains(counterpart))
        #expect(model.selectedTransactionIds == [counterpart])
    }
}

@MainActor
@Suite struct RegisterColumnMenuTests {
    @Test func theViewMenuSwitchesStatusAndMemoForEveryAccount() {
        let fixture = RegisterFixture()
        let (model, _) = fixture.spied()
        #expect(model.viewMenu.suffix(2).map(\.title) == ["Status", "Memo"])
        #expect(model.viewMenu.suffix(2).allSatisfy { $0.isChecked })
        model.viewMenuChosen(.toggleColumn(.cleared))
        #expect(!model.visibleColumns.contains(.cleared))
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(!model.visibleColumns.contains(.cleared))
        #expect(model.viewMenu.first { $0.title == "Status" }?.isChecked == false)
    }

    @Test func aReconciliationShowsTheStatusEvenWhenItIsHidden() throws {
        let (model, _) = RegisterFixture().spied()
        model.viewMenuChosen(.toggleColumn(.cleared))
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "1111"
        model.reconciliation.begin(form)
        #expect(model.visibleColumns.contains(.cleared))
    }
}

@MainActor
@Suite struct RegisterInfoBarTests {
    @Test func zuBestaetigenWithASearchShowsTheApprovalsAndTheHits() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "Netflix", category: fixture.groceries, approved: false, source: .bank)
        fixture.add(fixture.giro, -2, payee: "Spotify", category: fixture.groceries, approved: false, source: .bank)
        let (model, _) = fixture.spied()
        model.viewMenuChosen(.filter(.unapproved))
        model.search.boxChanged("netflix")
        #expect(
            RegisterPanelContent.infoBars(of: model) == [
                .approvals("1 Buchung wartet auf Bestätigung."),
                .search(RegisterSearchInfo(message: "1 Treffer für „netflix“", clearButtonTitle: "Suche zurücksetzen")),
            ])
    }
}
