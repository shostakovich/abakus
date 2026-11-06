import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterSearchTests {
    private func searchModel() -> (RegisterFixture, RegisterViewModel, [String: String]) {
        var fixture = RegisterFixture()
        var ids: [String: String] = [:]
        ids["rewe"] = fixture.add(fixture.giro, -40, payee: "REWE", category: fixture.groceries, memo: "Milch")
        ids["aral"] = fixture.add(fixture.giro, -60.5, on: "2014-05-12", payee: "Aral")
        ids["split"] = fixture.add(
            fixture.giro, -50, on: "2014-05-14", payee: "Kaufland", id: "SPLIT",
            subtransactions: [
                Subtransaction(id: "S1", transactionId: "SPLIT", amount: -30, memo: "Essen"),
                Subtransaction(id: "S2", transactionId: "SPLIT", amount: -20, memo: "Seife"),
            ])
        let (model, _) = fixture.spied()
        model.today = { day("2014-05-20") }
        return (fixture, model, ids)
    }

    @Test func typingFiltersAtOnce() {
        let (_, model, ids) = searchModel()
        model.search.boxChanged("rew")
        #expect(model.transactionIds == [ids["rewe"]!])
        #expect(model.search.info?.message == "1 Treffer für „rew“")
        model.search.boxChanged("milch")
        #expect(model.transactionIds == [ids["rewe"]!])
    }

    @Test func findsPayeeCategoryMemoAmountAndSplitParts() {
        let (_, model, ids) = searchModel()
        for (text, id) in [
            ("aral", "aral"), ("groceries", "rewe"), ("MILCH", "rewe"), ("60.50", "aral"), ("seife", "split"),
        ] {
            model.search.boxChanged(text)
            #expect(model.transactionIds == [ids[id]!], "\(text)")
        }
    }

    @Test func textWithAColonIsSearchedAsText() {
        let (_, model, _) = searchModel()
        model.search.boxChanged("Empfänger: Aral")
        #expect(model.transactionIds.isEmpty)
    }

    @Test func returnHandsTheKeysToTheList() {
        let (_, model, _) = searchModel()
        let before = model.gridFocusRequest
        model.search.boxChanged("rewe")
        model.search.submitted()
        #expect(model.gridFocusRequest == before + 1)
        #expect(model.search.text == "rewe")
    }

    @Test func escapeEmptiesTheBoxThenLeavesIt() {
        let (_, model, ids) = searchModel()
        model.search.boxChanged("rewe")
        #expect(model.search.escapePressed())
        #expect(model.search.text == "")
        #expect(Set(ids.values).isSubset(of: model.transactionIds))
        #expect(!model.search.escapePressed())
    }

    @Test func emptyingTheBoxEndsTheSearch() {
        let (_, model, ids) = searchModel()
        model.search.boxChanged("rewe")
        model.search.boxChanged("")
        #expect(!model.search.isSearching)
        #expect(model.search.info == nil)
        #expect(Set(ids.values).isSubset(of: model.transactionIds))
    }

    @Test func aSplitFoundByAPartOpensWithAllItsParts() {
        let (_, model, _) = searchModel()
        model.search.boxChanged("essen")
        #expect(model.rows.filter(\.isSubtransaction).map(\.id) == ["S1", "S2"])
        #expect(model.summary.second.amountText == "−$50.00")
    }

    @Test func clearingTheSearchRestoresTheSplitExpansion() {
        let (_, model, _) = searchModel()
        model.search.boxChanged("essen")
        model.search.clearClicked()
        #expect(!model.rows.contains { $0.isSubtransaction })
        #expect(model.search.text == "")
    }

    @Test func theSearchTotalSumsWhatItFinds() {
        let (_, model, _) = searchModel()
        model.search.boxChanged("50")
        #expect(model.summary.second.title == "Suchsumme (2)")
        #expect(model.summary.second.amountText == "−$110.50")
    }

    @Test func gebuchtAndVorgemerktAreJustNumbers() {
        let (_, model, _) = searchModel()
        #expect(model.summary.first.tooltip == "Summe der gebuchten und abgeglichenen Buchungen.")
        #expect(model.summary.second.tooltip == "Summe der vorgemerkten Buchungen, die die Bank noch nicht kennt.")
    }

    @Test func cmdFRequestsSearchFocus() {
        let (model, _) = RegisterFixture().spied()
        let before = model.search.focusRequest
        model.search.focus()
        #expect(model.search.focusRequest == before + 1)
    }

    @Test func searchClearsTheSelection() {
        let (_, model, _) = searchModel()
        model.selectAll()
        model.search.run("rewe")
        #expect(model.selection.isEmpty)
    }

    @Test func searchesAndViewsStayWithTheirAccount() {
        let (fixture, model, _) = searchModel()
        model.search.run("rewe")
        model.viewMenuChosen(.filter(.uncleared))
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(model.search.text == "")
        #expect(model.filter == .all)
        model.navigation.selection = .account(fixture.giro)
        #expect(model.search.text == "rewe")
        #expect(model.filter == .uncleared)
    }
}

@MainActor
@Suite struct RegisterViewTests {
    private struct Views {
        var fixture = RegisterFixture()
        let waiting: String
        let waitingElsewhere: String
        let uncleared: String
        let uncategorized: String
        let cleared: String

        init() {
            waiting = fixture.add(
                fixture.giro, -1, payee: "Netflix", category: fixture.groceries, cleared: .cleared, approved: false,
                source: .bank)
            waitingElsewhere = fixture.add(
                fixture.tagesgeld, -2, category: fixture.groceries, approved: false, source: .bank)
            uncleared = fixture.add(fixture.giro, -3, payee: "REWE", category: fixture.groceries)
            uncategorized = fixture.add(fixture.giro, -4, payee: "Kiosk", cleared: .cleared)
            cleared = fixture.add(fixture.giro, -5, payee: "Aral", category: fixture.groceries, cleared: .cleared)
        }

        @MainActor
        func model(selection: SidebarSelection? = nil) -> (RegisterViewModel, SpyBudgetStore) {
            fixture.spied(selection: selection, appliesCommands: true)
        }
    }

    @Test func theViewMenuListsTheFourViewsWithACheckMarkThenTheColumns() {
        let (model, _) = Views().model()
        #expect(
            model.viewMenu.map(\.title) == [
                "Alle Buchungen", "Zu bestätigen", "Vorgemerkt", "Ohne Kategorie", "", "Geplante Buchungen", "",
                "Status",
                "Memo",
            ])
        #expect(model.viewMenu.filter(\.isChecked).map(\.title) == ["Alle Buchungen", "Status", "Memo"])
        model.viewMenuChosen(.filter(.uncleared))
        #expect(model.viewMenu.first { $0.isChecked }?.title == "Vorgemerkt")
        #expect(model.viewMenuTitle == "Ansicht: vorgemerkt")
    }

    @Test func eachViewFiltersTheAccount() {
        let views = Views()
        let (model, _) = views.model()
        model.viewMenuChosen(.filter(.unapproved))
        #expect(model.transactionIds == [views.waiting])
        model.viewMenuChosen(.filter(.uncleared))
        #expect(Set(model.transactionIds) == [views.uncleared])
        model.viewMenuChosen(.filter(.needsCategory))
        #expect(model.transactionIds == [views.uncategorized])
        model.viewMenuChosen(.filter(.all))
        #expect(model.transactionIds.count == 5)
        #expect(model.viewMenuTitle == "Ansicht")
    }

    @Test func aViewOtherThanAlleBuchungenIsNamedWithTheWayBack() {
        let (model, _) = Views().model()
        #expect(model.activeViewLine == nil)
        model.viewMenuChosen(.filter(.needsCategory))
        #expect(model.activeViewLine == "Ansicht: ohne Kategorie")
        model.allTransactionsClicked()
        #expect(model.filter == .all)
        #expect(model.activeViewLine == nil)
    }

    @Test func theEmptyListNamesItsView() {
        let views = Views()
        let (model, _) = views.model(selection: .account(views.fixture.karte))
        #expect(model.emptyListTitle == "Keine Buchungen")
        model.viewMenuChosen(.filter(.needsCategory))
        #expect(model.emptyListTitle == "Keine Buchungen in „Ohne Kategorie“")
        model.search.boxChanged("rewe")
        #expect(model.emptyListTitle == "Keine Treffer")
    }

    @Test func theSearchNarrowsTheView() {
        let views = Views()
        let (model, _) = views.model()
        model.viewMenuChosen(.filter(.uncleared))
        model.search.boxChanged("aral")
        #expect(model.transactionIds.isEmpty)
        model.search.boxChanged("rewe")
        #expect(model.transactionIds == [views.uncleared])
        model.viewMenuChosen(.filter(.all))
        #expect(model.transactionIds == [views.uncleared])
    }

    @Test func theChipsSwitchToTheirViewAndEndTheSearch() {
        let views = Views()
        let (model, store) = views.model()
        model.search.boxChanged("aral")
        model.notifiers.clicked(.reminder)
        #expect(model.filter == .unapproved)
        #expect(model.search.text == "")
        #expect(model.transactionIds == [views.waiting])
        #expect(store.commands.isEmpty)
        #expect(model.notifiers.list.map(\.kind) == [.warning])
        model.notifiers.clicked(.warning)
        #expect(model.filter == .needsCategory)
        #expect(model.transactionIds == [views.uncategorized])
    }

    @Test func aWaitingImportWithoutCategoryIsCountedAndListedByBothViews() {
        var fixture = RegisterFixture()
        let waiting = fixture.add(fixture.giro, -3, payee: "Kiosk", approved: false, source: .bank)
        let (model, _) = fixture.spied()
        #expect(model.notifiers.list.map(\.text) == ["1 braucht eine Kategorie", "1 bestätigen"])
        #expect(model.approvalCount == 1)
        model.notifiers.clicked(.reminder)
        #expect(model.transactionIds == [waiting])
        model.notifiers.clicked(.warning)
        #expect(model.transactionIds == [waiting])
    }

    @Test func alleBestaetigenApprovesAWaitingTransferBetweenBudgetAccountsWithACategory() {
        var fixture = RegisterFixture()
        let transfer = fixture.add(
            fixture.giro, -50, category: fixture.groceries, approved: false, source: .bank, target: fixture.tagesgeld)
        let (model, store) = fixture.spied()
        #expect(model.notifiers.list.first { $0.kind == .reminder }?.text == "1 bestätigen")
        model.notifiers.clicked(.reminder)
        #expect(model.transactionIds == [transfer])
        model.approveAllClicked()
        #expect(store.commands == [.approveTransactions([transfer])])
    }

    @Test func onlyTheChipOfTheShownViewGoesAndASearchKeepsThem() {
        let (model, _) = Views().model()
        model.search.boxChanged("e")
        #expect(model.notifiers.list.map(\.kind) == [.warning, .reminder])
        model.viewMenuChosen(.filter(.needsCategory))
        #expect(model.notifiers.list.map(\.kind) == [.reminder])
        model.viewMenuChosen(.filter(.uncleared))
        #expect(model.notifiers.list.map(\.kind) == [.warning, .reminder])
    }

    @Test func theErrorChipLeadsNowhere() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, category: fixture.groceries, target: fixture.tagesgeld)
        let (model, _) = fixture.spied()
        let error = model.notifiers.list.first { $0.kind == .error }
        #expect(error?.isClickable == false)
        model.notifiers.clicked(.error)
        #expect(model.filter == .all)
    }

    @Test func theViewZuBestaetigenApprovesOnlyWhatItShows() throws {
        let views = Views()
        let (model, store) = views.model(selection: .allAccounts)
        model.viewMenuChosen(.filter(.unapproved))
        #expect(model.approvalsLine == "2 Buchungen warten auf Bestätigung.")
        model.search.boxChanged("netflix")
        #expect(model.approvalsLine == "1 Buchung wartet auf Bestätigung.")
        model.approveAllClicked()
        #expect(store.commands == [.approveTransactions([views.waiting])])
        #expect(model.approvalsLine == nil)
        #expect(model.transactionIds.isEmpty)
    }

    @Test func otherViewsHaveNoApprovalLine() {
        let (model, store) = Views().model()
        #expect(model.approvalsLine == nil)
        model.approveAllClicked()
        #expect(store.commands.isEmpty)
    }

    @Test func theBudgetAndTheKontenListOpenAlleKontenInAView() {
        let views = Views()
        let (model, _) = views.model()
        model.search.boxChanged("rewe")
        model.showApprovals()
        #expect(model.navigation.selection == .allAccounts)
        #expect(model.filter == .unapproved)
        #expect(Set(model.transactionIds) == [views.waiting, views.waitingElsewhere])
        model.showAllAccounts(in: .needsCategory)
        #expect(model.filter == .needsCategory)
        #expect(model.transactionIds == [views.uncategorized])
        model.navigation.selection = .account(views.fixture.giro)
        #expect(model.filter == .all)
        #expect(model.search.text == "rewe")
    }

    @Test func revealingAHiddenTransactionShowsAlleBuchungen() {
        let views = Views()
        let (model, _) = views.model()
        model.viewMenuChosen(.filter(.unapproved))
        model.showTransaction(views.cleared)
        #expect(model.filter == .all)
        #expect(model.selectedTransactionIds == [views.cleared])
    }

    @Test func aReconciliationStartsWithAlleBuchungenAndBringsTheViewBack() throws {
        let (model, _) = Views().model()
        model.viewMenuChosen(.filter(.uncleared))
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "0"
        model.reconciliation.begin(form)
        #expect(model.isReconciling)
        #expect(model.filter == .all)
        model.reconciliation.stopReconcilingClicked()
        #expect(model.filter == .uncleared)
    }

    @Test func whileReconcilingNeitherTheMenusNorTheChipsSwitchTheView() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -3, payee: "Kiosk", approved: false, source: .bank)
        let (model, _) = fixture.spied(appliesCommands: true)
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "0"
        model.reconciliation.begin(form)
        #expect(model.viewMenu.map(\.title) == ["Status", "Memo"])
        #expect(model.touchViewMenu(showsColumns: false).map(\.title) == ["Auswählen", "", "Konto bearbeiten"])
        #expect(model.notifiers.list.map(\.isClickable) == [false, false])
        model.notifiers.clicked(.reminder)
        model.notifiers.clicked(.warning)
        model.viewMenuChosen(.filter(.uncleared))
        #expect(model.filter == .all)
        #expect(model.approvalsLine == nil)
        #expect(model.search.info?.message.hasSuffix("(Datum des Banksaldos)") == true)
        model.reconciliation.stopReconcilingClicked()
        #expect(model.viewMenu.first?.title == "Alle Buchungen")
        #expect(model.notifiers.list.map(\.isClickable) == [true, true])
    }
}
