import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterViewModelTests {
    @Test func appModelShowsTheRegisterOfTheSelectedAccount() {
        let app = AppModel(store: BudgetStore(budget: RegisterFixture().budget), defaults: nil)
        #expect(app.register.accountName == "Giro")
        app.sidebar.select(.budget)
        #expect(app.register.accountKey == nil)
        #expect(app.register.rows.isEmpty)
    }

    @Test func visibleColumnsFollowTheAccountKind() {
        var fixture = RegisterFixture()
        let base: [RegisterColumn] = [.date, .payee, .category, .memo, .amount, .cleared]
        #expect(fixture.model().visibleColumns == base)
        fixture.add(fixture.giro, -1)
        #expect(fixture.model().visibleColumns == base)
        #expect(fixture.model(selection: .allAccounts).visibleColumns.prefix(2) == [.account, .date])
    }

    @Test func columnMenuTogglesOnlyHideableColumns() {
        let model = RegisterFixture().model()
        #expect(model.columnMenuItems.map(\.label) == ["Status", "Memo"])
        model.toggleColumnVisibility(.memo)
        model.toggleColumnVisibility(.payee)
        #expect(!model.visibleColumns.contains(.memo))
        #expect(model.visibleColumns.contains(.payee))
        #expect(RegisterFixture().model(selection: .allAccounts).columnMenuItems.count == 2)
    }

    @Test func theContextMenuKeepsTheSelectionAndStartsWithAnAction() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1)
        fixture.add(fixture.giro, -2)
        let model = fixture.model()
        model.selectAll()
        #expect(model.contextMenu(for: model.rows[0])?.first?.title == "Kategorisieren als")
        #expect(model.selection.count == 3)
    }

    @Test func theViewMenuHoldsTheViewsAndTheColumns() {
        let model = RegisterFixture().model()
        #expect(
            model.viewMenu.map(\.title).filter { !$0.isEmpty } == [
                "Alle Buchungen", "Zu bestätigen", "Vorgemerkt", "Ohne Kategorie", "Status", "Memo",
            ])
        model.viewMenuChosen(.filter(.uncleared))
        #expect(model.filter == .uncleared)
    }

    @Test func theHeaderShowsTheReconcileDateAndEditsTheAccount() {
        var fixture = RegisterFixture()
        let index = fixture.budget.accounts.firstIndex { $0.id == fixture.giro }!
        fixture.budget.accounts[index].lastReconciledAt = day("2014-04-30").noon()
        let model = fixture.model()
        #expect(model.reconciledLabel == "Abgeglichen am 30/04")
        fixture.budget.accounts[index].lastReconciledAt = day("2013-09-27").noon()
        #expect(fixture.model().reconciledLabel == "Abgeglichen am 27/09/2013")
        #expect(fixture.model(selection: .allAccounts).reconciledLabel == nil)
    }

    @Test func searchPromptNamesTheAccount() {
        let fixture = RegisterFixture()
        let giro = fixture.model()
        let allAccounts = fixture.model(selection: .allAccounts)
        #expect(giro.search.prompt == "Giro durchsuchen")
        #expect(allAccounts.search.prompt == "Alle Konten durchsuchen")
    }

    @Test func searchTextIsKeptPerAccount() {
        let fixture = RegisterFixture()
        let model = fixture.model()
        model.search.boxChanged("rewe")
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(model.search.text == "")
        model.navigation.selection = .account(fixture.giro)
        #expect(model.search.text == "rewe")
    }

    @Test func searchFilterFeedsTheInfoBarAndTheSearchTotal() {
        var fixture = RegisterFixture()
        let match = fixture.add(fixture.giro, -40, payee: "REWE")
        let model = fixture.model()
        model.search.boxChanged("rewe")
        #expect(model.transactionIds == [match])
        #expect(model.search.info?.message == "1 Treffer für „rewe“")
        let summary = model.summary
        #expect(summary.first.kind == .blank)
        #expect(summary.second.title == "Suchsumme (1)")
        #expect(summary.second.amountText == "−$40.00")
        #expect(!summary.showsOperands)
        model.search.clearClicked()
        #expect(!model.search.isSearching)
        #expect(model.search.text == "")
    }

    @Test func summaryShowsTheAccountBalances() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1200)
        let summary = fixture.model().summary
        #expect(summary.first.title == "Gebucht")
        #expect(summary.first.amountText == "$1,111.00")
        #expect(summary.second.title == "Vorgemerkt")
        #expect(summary.second.amountText == "−$1,200.00")
        #expect(summary.second.isNegative)
        #expect(summary.working.amountText == "−$89.00")
        #expect(summary.showsOperands)
    }

    @Test func selectingSeveralRowsPutsTheSelectedTotalInTheStatusBar() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -11)
        let model = fixture.model()
        model.selectAll()
        #expect(model.selectedTotal?.title == "Auswahl (2)")
        #expect(model.selectedTotal?.amountText == "$1,100.00")
        #expect(model.selectedTotal?.tooltip == "Summe aller ausgewählten Buchungen")
        #expect(model.summary.first.title == "Gebucht")
        #expect(model.summary.showsOperands)
    }

    @Test func scheduledToggleKeepsItsStatePerAccount() {
        var fixture = RegisterFixture()
        fixture.budget.scheduledTransactions.append(
            ScheduledTransaction(accountId: fixture.giro, nextDate: day("2014-06-01"), amount: -5))
        let model = fixture.model()
        #expect(model.scheduler.scheduledTransactions.count == 1)
        #expect(model.scheduledToggleTooltip == "Geplante Buchungen zeigen")
        model.scheduledToggleClicked()
        #expect(model.isSchedulerVisible)
        #expect(model.scheduledToggleTooltip == "Geplante Buchungen ausblenden")
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(!model.isSchedulerVisible)
        #expect(model.scheduler.scheduledTransactions.count == 0)
    }

    @Test func reconcileNeedsASingleAccount() {
        let fixture = RegisterFixture()
        let model = fixture.model()
        #expect(model.reconciliation.isReconcileEnabled)
        model.reconciliation.reconcileClicked()
        #expect(model.reconciliation.statementForm?.accountId == fixture.giro)
    }

    @Test func addingATransactionOpensTheAddEditor() {
        let model = RegisterFixture().model()
        model.addTransactionClicked()
        #expect(model.grid.isAdding)
        #expect(model.editor?.text(.main(.payee)) == "")
        model.editor?.activate(.cancel)
        model.grid.beginNew(transfer: true)
        #expect(model.editor?.text(.main(.payee)) == "Transfer : ")
        #expect(model.showsTransferButton)
        var single = Budget(budgetName: "Single")
        try? single.apply(
            .addAccount(
                NewAccount(
                    id: "ONLY", name: "Only", kind: .cash, startingBalance: 1,
                    startDate: day("2014-01-01"))))
        let lonely = RegisterViewModel(
            store: BudgetStore(budget: single), navigation: NavigationState(selection: .account("ONLY")))
        #expect(!lonely.showsTransferButton)
    }

    @Test func liveChangesReachTheRowsAndTotals() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10)
        let model = fixture.model()
        #expect(model.summary.second.amountText == "−$10.00")
        try model.store.perform(.setCleared([id], .cleared))
        #expect(model.rows.last?.cleared == .cleared)
        #expect(model.summary.first.amountText == "$1,101.00")
    }

    @Test func scrollOffsetsAreRememberedPerAccount() {
        let fixture = RegisterFixture()
        let model = fixture.model()
        #expect(model.savedScrollOffset() == nil)
        model.saveScrollOffset(48)
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(model.savedScrollOffset() == nil)
        model.navigation.selection = .account(fixture.giro)
        #expect(model.savedScrollOffset() == 48)
    }
}
