import AbakusCore
import AppKit
import Foundation
import Testing

@testable import AbakusUI

@Suite struct BudgetCalloutOutsideClickTests {
    @Test func aRightClickOutsideIsNotWatched() {
        #expect(WindowEventMonitor.events.contains(.leftMouseDown))
        #expect(!WindowEventMonitor.events.contains(.rightMouseDown))
    }
}

@MainActor
@Suite struct BudgetQuickBudgetMenuTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    @Test func theMenuShowsTheCoreItemsWithDisabledHeadings() {
        let model = F().model().model
        let items = Array(model.callouts.quickBudgetMenu(month: october).dropFirst(3))
        let expected = model.sheet.quickBudgetMenu(month: october, formatter: model.formatter)
        #expect(items.map(\.title) == expected.map(\.label))
        #expect(items.first?.kind == .title)
        #expect(items.first?.isEnabled == false)
        #expect(items[1].kind == .action(.quickBudget(.assignedLastMonth)))
        #expect(items.last?.kind == .action(.quickBudget(.zero)))
    }

    @Test func aFillTheMonthDoesNotOfferAsksNothing() {
        let model = F().model().model
        model.callouts.quickBudgetChosen(.averageOutflowsLastYear, month: october)
        #expect(!model.dialogs.isPresenting)
    }

    @Test func anItemAsksFirstAndFillsOnlyOnTheFillButton() throws {
        let (model, store) = F().model()
        model.present(.monthQuickBudget(month: october))
        model.callouts.quickBudgetChosen(.outflowsLastMonth, month: october)
        model.callouts.quickBudgetMenuClosed()
        #expect(model.presentedPopup == nil)
        let dialog = try #require(model.dialogs.presented.last)
        #expect(dialog.dialog.instruction == "Leere Zuweisungen mit den Ausgaben aus September '26 füllen?")
        #expect(dialog.dialog.content == "Das lässt sich nicht rückgängig machen.")
        #expect(dialog.dialog.buttons.map(\.title) == ["Abbrechen", "Leere Zuweisungen füllen"])
        dialog.answer(QuickBudgetChoice.cancel)
        #expect(store.commands.isEmpty)
        model.callouts.quickBudgetChosen(.zero, month: october)
        let zero = try #require(model.dialogs.presented.last)
        #expect(zero.dialog.instruction == "Alle Zuweisungen im Oktober zurücksetzen?")
        zero.answer(QuickBudgetChoice.fill)
        #expect(store.commands == [.quickBudget(month: october, fill: .zero, today: F.today)])
        #expect(!model.dialogs.isPresenting)
    }
}

@MainActor
@Suite struct BudgetCategoryCalloutTests {
    typealias F = BudgetScreenFixture

    private func addedId(_ store: SpyBudgetStore) -> String? {
        for command in store.commands {
            switch command {
            case .addCategoryGroup(let id), .addCategory(_, let id): return id
            default: continue
            }
        }
        return nil
    }

    @Test func addingAMasterOpensItsCalloutAtTheNewRow() throws {
        let (model, store) = F().model(panel: CGSize(width: 1076, height: 300))
        model.scroll(to: 40)
        model.addMasterCategoryClicked()
        let id = try #require(addedId(store))
        #expect(model.presentedPopup == .editCategory(categoryId: id))
        #expect(model.popupAnchor == .categoryRow(id))
        let form = try #require(model.callouts.category)
        #expect(form.isNew && form.isMaster)
        #expect(form.title == "Neue Kategoriegruppe")
        #expect(model.callouts.categoryName == "Neue Kategoriegruppe")
        #expect(model.scrollOffset == 0)
        #expect(model.groups.first?.id == id)
    }

    @Test func cancelAndEscapeRemoveANewCategoryWithoutAsking() throws {
        let (model, store) = F().model()
        model.addMasterCategoryClicked()
        let master = try #require(addedId(store))
        model.callouts.categoryCancelled()
        #expect(store.commands.last == .deleteCategoryGroup(groupId: master))
        model.addSubCategoryClicked(masterId: F.sparen)
        let sub = try #require(model.callouts.category?.categoryId)
        #expect(model.callouts.category?.title == "Neue Kategorie")
        #expect(model.callouts.escapePressed())
        #expect(store.commands.last == .discardCategory(categoryId: sub))
        #expect(model.presentedPopup == nil)
        #expect(!model.dialogs.isPresenting)
    }

    @Test func aClickOutsideKeepsTheNewCategoryWithItsName() throws {
        let (model, store) = F().model()
        model.addSubCategoryClicked(masterId: F.freizeit)
        let id = try #require(addedId(store))
        #expect(store.commands == [.addCategory(groupId: F.freizeit, categoryId: id)])
        #expect(store.budget.category(withId: id)?.name == "Neue Kategorie")
        model.callouts.mouseDownOutside()
        #expect(model.presentedPopup == nil)
        #expect(store.commands.count == 1)
    }

    @Test func addingASubScrollsItsGroupIntoView() throws {
        let (model, store) = F().model(panel: CGSize(width: 1076, height: 300))
        model.addSubCategoryClicked(masterId: F.freizeit)
        let id = try #require(addedId(store))
        let top = try #require(model.groups.top(of: F.freizeit))
        let group = try #require(model.groups.first { $0.id == F.freizeit })
        #expect(group.subs.last?.id == id)
        #expect(model.scrollOffset == min(model.maxScrollOffset, top + group.height - model.layout.viewportHeight))
    }

    @Test func doneRenamesWithTheTrimmedName() {
        let (model, store) = F().model()
        model.present(.editCategory(categoryId: F.kleidung))
        #expect(model.callouts.category?.title == "Kategorie bearbeiten")
        model.callouts.categoryName = "  Schuhe "
        model.callouts.categoryDone()
        #expect(store.commands == [.renameCategory(categoryId: F.kleidung, name: "Schuhe")])
        #expect(model.presentedPopup == nil)
        model.present(.editCategory(categoryId: F.alltag))
        #expect(model.callouts.category?.title == "Kategoriegruppe bearbeiten")
        #expect(model.callouts.category?.deleteTitle == "Gruppe löschen")
        model.callouts.categoryName = "Täglich"
        model.callouts.categoryDone()
        #expect(store.commands.last == .renameCategoryGroup(groupId: F.alltag, name: "Täglich"))
    }

    @Test func anUnchangedNameClosesWithoutRenaming() {
        let (model, store) = F().model()
        model.present(.editCategory(categoryId: F.kleidung))
        model.callouts.categoryName = "Kleidung "
        model.callouts.categoryDone()
        #expect(model.presentedPopup == nil)
        #expect(store.commands.isEmpty)
    }

    @Test func aRefusedNameAsksOnceAndKeepsTheCalloutOpenAgainstOutsideClicks() throws {
        let (model, store) = F().model()
        model.present(.editCategory(categoryId: F.kleidung))
        model.callouts.categoryName = "lebensmittel"
        model.callouts.categoryDone()
        model.callouts.categoryDone()
        #expect(model.dialogs.presented.count == 1)
        let dialog = try #require(model.dialogs.presented.first)
        #expect(dialog.dialog.instruction == "Bitte einen anderen Namen wählen")
        #expect(dialog.dialog.content == "Diesen Kategorienamen gibt es schon.")
        #expect(!model.callouts.escapePressed())
        model.callouts.mouseDownOutside()
        #expect(model.presentedPopup == .editCategory(categoryId: F.kleidung))
        dialog.answer(MessageChoice.close)
        #expect(model.callouts.category?.focusRequest == 1)
        model.callouts.mouseDownOutside()
        #expect(model.presentedPopup == .editCategory(categoryId: F.kleidung))
        model.callouts.categoryName = "Mode"
        model.callouts.categoryDone()
        #expect(model.presentedPopup == nil)
        #expect(store.commands.last == .renameCategory(categoryId: F.kleidung, name: "Mode"))
    }

    @Test func deleteAsksWhichCategoryTakesOver() throws {
        let (model, store) = F().model()
        model.present(.editCategory(categoryId: F.kleidung))
        model.callouts.deleteCategoryClicked()
        #expect(model.presentedPopup == .editCategory(categoryId: F.kleidung))
        let form = try #require(model.callouts.category)
        #expect(form.deletionTitle == "Kategorie „Kleidung“ löschen")
        let deletion = try #require(form.deletion)
        #expect(deletion.successors.map(\.name) == ["Alltag", "Sparen", "Freizeit"])
        #expect(deletion.successors[0].categories.map(\.id) == [F.lebensmittel])
        #expect(!deletion.changesReconciledTransactions)
        model.callouts.confirmDeletionClicked()
        #expect(store.commands.isEmpty)
        model.callouts.deletionSuccessorId = F.kino
        model.callouts.confirmDeletionClicked()
        #expect(store.commands == [.deleteCategory(categoryId: F.kleidung, into: F.kino)])
        #expect(model.presentedPopup == nil)
        #expect(store.budget.category(withId: F.kleidung) == nil)
    }

    @Test func deleteWarnsWhenReconciledTransactionsChange() throws {
        var fixture = F()
        fixture.spend(12.5, F.kleidung, on: "2026-10-02")
        let ids = fixture.budget.transactions.map(\.id)
        try fixture.budget.apply(.setCleared(ids, .reconciled))
        let model = fixture.model().model
        model.present(.editCategory(categoryId: F.kleidung))
        model.callouts.deleteCategoryClicked()
        #expect(model.callouts.category?.deletion?.changesReconciledTransactions == true)
    }

    @Test func cancelAndEscapeLeaveTheDeletionForTheCallout() throws {
        let (model, store) = F().model()
        model.present(.editCategory(categoryId: F.kleidung))
        model.callouts.deleteCategoryClicked()
        model.callouts.deletionCancelled()
        #expect(model.callouts.category?.deletion == nil)
        model.callouts.deleteCategoryClicked()
        #expect(model.callouts.escapePressed())
        #expect(model.callouts.category?.deletion == nil)
        #expect(model.presentedPopup == .editCategory(categoryId: F.kleidung))
        #expect(store.commands.isEmpty)
    }

    @Test func onlyAnEmptyMasterOffersDeleteAndGoesAtOnce() throws {
        let (model, store) = F().model()
        model.present(.editCategory(categoryId: F.alltag))
        #expect(model.callouts.category?.canDelete == false)
        model.callouts.deleteCategoryClicked()
        #expect(store.commands.isEmpty)
        model.addMasterCategoryClicked()
        let master = try #require(model.callouts.category?.categoryId)
        model.callouts.categoryDone()
        model.present(.editCategory(categoryId: master))
        #expect(model.callouts.category?.canDelete == true)
        model.callouts.deleteCategoryClicked()
        #expect(store.commands.last == .deleteCategoryGroup(groupId: master))
        #expect(model.presentedPopup == nil)
    }

    @Test func theKeyFocusReturnsToThePanelOnlyAfterTheTaskDialogCloses() throws {
        let model = F().model().model
        let october = day("2026-10-01")
        model.present(.monthQuickBudget(month: october))
        #expect(!model.takesKeyFocusBack)
        model.callouts.quickBudgetChosen(.outflowsLastMonth, month: october)
        model.callouts.quickBudgetMenuClosed()
        #expect(model.presentedPopup == nil)
        #expect(!model.takesKeyFocusBack)
        try #require(model.dialogs.presented.last).answer(QuickBudgetChoice.cancel)
        #expect(model.takesKeyFocusBack)
    }
}

@MainActor
@Suite struct BudgetSummaryCalloutTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    @Test func theSummaryIsTheCoresAndHandsItsFilterToTheRegister() throws {
        var fixture = F()
        fixture.spend(30, F.lebensmittel, on: "2026-10-03")
        let (model, store) = fixture.model()
        var shownFilters: [AccountViewFilter] = []
        model.callouts.onShowInAccountView = { shownFilters.append($0) }
        model.subOutflowsClicked(month: october, categoryId: F.lebensmittel)
        let expected = store.budget.outflowSummary(
            .category(F.lebensmittel), month: october, today: F.today, formatter: model.formatter)
        #expect(model.callouts.summary == expected)
        model.callouts.showInAccountViewClicked()
        #expect(shownFilters == [try #require(expected.accountView)])
        #expect(model.presentedPopup == nil)
    }

    @Test func aRowShowsItsTransactionInTheRegister() throws {
        var fixture = F()
        fixture.spend(30, F.lebensmittel, on: "2026-10-03")
        let model = fixture.model().model
        var shown: [String] = []
        model.callouts.onShowTransaction = { shown.append($0) }
        model.masterOutflowsClicked(month: october, masterId: F.alltag)
        let row = try #require(model.callouts.summary?.rows.first)
        model.callouts.summaryRowClicked(row)
        #expect(shown == [row.transactionId])
        #expect(model.presentedPopup == nil)
    }

    @Test func theIncomeSummaryAndClose() {
        let model = F().model().model
        var shown = 0
        model.callouts.onShowInAccountView = { _ in shown += 1 }
        model.present(.incomeSummary(month: october))
        #expect(model.callouts.summary?.title == "Einnahmen im Oktober")
        model.callouts.showInAccountViewClicked()
        #expect(model.presentedPopup == .incomeSummary(month: october))
        model.callouts.summaryClosed()
        #expect(model.presentedPopup == nil)
        #expect(shown == 0)
    }

    @Test func theOutflowHelpNamesTheCategoryAndCanBeTurnedOff() throws {
        let model = F().model().model
        model.subOutflowsClicked(month: october, categoryId: F.kleidung)
        let help = try #require(model.callouts.outflowHelp)
        #expect(help.message.contains("Im Oktober 2026 gibt es noch keine Ausgaben in <b>„Alltag: Kleidung“</b>."))
        #expect(model.callouts.escapePressed())
        model.masterOutflowsClicked(month: october, masterId: F.freizeit)
        #expect(model.callouts.outflowHelp?.message.contains("<b>„Freizeit“</b>") == true)
        model.callouts.dontShowOutflowHelpAgainClicked()
        #expect(!model.showsEmptyOutflowHelp)
        #expect(model.presentedPopup == nil)
    }

    @Test func aDialogAboveTheCalloutKeepsEscapeAndClicks() {
        let model = F().model().model
        model.present(.incomeSummary(month: october))
        model.dialogs.show(.message("Hinweis", ""))
        #expect(!model.callouts.escapePressed())
        model.callouts.mouseDownOutside()
        #expect(model.presentedPopup == .incomeSummary(month: october))
    }
}

@MainActor
@Suite struct BudgetAccountViewTests {
    typealias F = BudgetScreenFixture

    @Test func showInAccountViewOpensTheFilteredRegister() throws {
        var fixture = F()
        fixture.spend(30, F.lebensmittel, on: "2026-10-03")
        let store = BudgetStore(budget: fixture.budget, today: { F.today })
        let app = AppModel(store: store, selection: .budget, defaults: nil)
        app.budget.panelSize = F.panel
        app.budget.subOutflowsClicked(month: day("2026-10-01"), categoryId: F.lebensmittel)
        app.budget.callouts.showInAccountViewClicked()
        #expect(app.navigation.selection == .account(F.giro))
        #expect(app.register.search.text == "Kategorie: Alltag: Lebensmittel, ")
        #expect(app.register.search.filter?.label == "Kategorie: Alltag: Lebensmittel")
        #expect(app.register.search.dateFilter?.label == "Dieser Monat")
        #expect(app.register.transactionIds.count == 1)
    }

    @Test func allOutflowsFromTwoAccountsOpenAllAccountsWithoutASearch() throws {
        var fixture = F()
        try fixture.budget.apply(
            .addAccount(
                NewAccount(
                    id: "BAR", name: "Bar", kind: .cash, startingBalance: 0,
                    startDate: day("2026-08-01"))))
        fixture.spend(30, F.lebensmittel, on: "2026-10-03")
        try fixture.budget.apply(
            .addTransaction(
                Transaction(accountId: "BAR", date: day("2026-10-05"), categoryId: F.kino, amount: -12),
                payeeName: "Kino"))
        let store = BudgetStore(budget: fixture.budget, today: { F.today })
        let app = AppModel(store: store, selection: .allAccounts, defaults: nil)
        app.register.search.run("Empfänger: Laden")
        #expect(app.register.search.filter != nil)
        app.navigation.selection = .budget
        app.budget.panelSize = F.panel
        app.budget.totalsOutflowsClicked(month: day("2026-10-01"))
        app.budget.callouts.showInAccountViewClicked()
        #expect(app.navigation.selection == .allAccounts)
        #expect(app.register.search.filter == nil)
        #expect(app.register.search.dateFilter?.label == "Dieser Monat")
        #expect(app.register.transactionIds.count == 2)
    }

    @Test func aSummaryRowOpensItsAccountWithTheTransactionSelected() throws {
        var fixture = F()
        fixture.spend(30, F.lebensmittel, on: "2026-10-03")
        let store = BudgetStore(budget: fixture.budget, today: { F.today })
        let app = AppModel(store: store, selection: .budget, defaults: nil)
        app.budget.panelSize = F.panel
        app.budget.subOutflowsClicked(month: day("2026-10-01"), categoryId: F.lebensmittel)
        let row = try #require(app.budget.callouts.summary?.rows.first)
        app.budget.callouts.summaryRowClicked(row)
        #expect(app.navigation.selection == .account(F.giro))
        #expect(app.register.selectedTransactionIds == [row.transactionId])
    }
}

@MainActor
@Suite struct BudgetPopoverPlacementTests {
    typealias F = BudgetScreenFixture
    let october = day("2026-10-01")

    @Test func aPopoverWithoutRoomBelowFlipsAboveWithItsArrowAtTheOpener() {
        let opener = CGRect(x: 400, y: 560, width: 20, height: 20)
        let placement = PopoverPlacement.place(
            CGSize(width: 300, height: 120), beside: opener, on: .below,
            in: CGSize(width: 1000, height: 640))
        #expect(placement.arrowEdge == .bottom)
        #expect(placement.frame.maxY == opener.minY)
        #expect(placement.frame.minX + placement.arrowOffset == opener.midX)
    }

    @Test func aPopoverThatFitsNeitherSideTakesTheRoomierOneCutToTheWindow() {
        let window = CGSize(width: 1000, height: 550)
        let size = CGSize(width: 300, height: 380)
        let high = CGRect(x: 400, y: 200, width: 20, height: 20)
        let below = PopoverPlacement.place(size, beside: high, on: .below, in: window).fitting(in: window)
        #expect(below.arrowEdge == .top)
        #expect(below.frame == CGRect(x: 260, y: 220, width: 300, height: 330))
        let low = CGRect(x: 400, y: 320, width: 20, height: 20)
        let above = PopoverPlacement.place(size, beside: low, on: .below, in: window).fitting(in: window)
        #expect(above.arrowEdge == .bottom)
        #expect(above.frame == CGRect(x: 260, y: 0, width: 300, height: 320))
        let fits = PopoverPlacement.place(size, beside: high, on: .below, in: CGSize(width: 1000, height: 700))
        #expect(fits.fitting(in: CGSize(width: 1000, height: 700)) == fits)
    }
}
