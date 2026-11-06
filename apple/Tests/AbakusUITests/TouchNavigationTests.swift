import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct TouchNavigationTests {
    private let fixture = RegisterFixture()

    private func open(_ storage: MemorySettingsStorage? = nil) -> (AppModel, TouchNavigation) {
        let app = AppModel(store: BudgetStore(budget: fixture.budget, today: { editDay }), defaults: storage)
        return (app, TouchNavigation(app: app))
    }

    @Test func pushingAnAccountShowsItsRegisterAndGoingBackKeepsIt() {
        let (app, tabs) = open()
        tabs.select(.accounts)
        tabs.showAccounts([.account(fixture.tagesgeld)])
        #expect(app.navigation.selection == .account(fixture.tagesgeld))
        tabs.showAccounts([])
        #expect(tabs.accountPath.isEmpty)
        #expect(app.navigation.selection == .account(fixture.tagesgeld))
    }

    @Test func plusWaitsOnlyWhileAClosedRegisterShows() throws {
        var budget = fixture.budget
        let index = try #require(budget.accounts.firstIndex { $0.id == fixture.karte })
        budget.accounts[index].closed = true
        let app = AppModel(store: BudgetStore(budget: budget, today: { editDay }), defaults: nil)
        let tabs = TouchNavigation(app: app)
        tabs.select(.accounts)
        tabs.showAccounts([.account(fixture.karte)])
        #expect(!tabs.canAddTransaction)
        tabs.showAccounts([])
        #expect(tabs.canAddTransaction)
        tabs.addTransactionClicked()
        #expect(app.register.editor?.clone.accountId != fixture.karte)
    }

    @Test func goingBackEndsTheRegistersVisit() {
        let (app, tabs) = open()
        tabs.select(.accounts)
        tabs.showAccounts([.account(fixture.tagesgeld)])
        app.register.togglePicking()
        #expect(tabs.barTakesDocksPlace)
        tabs.showAccounts([])
        #expect(!app.register.isPicking)
        #expect(!tabs.barTakesDocksPlace)
    }

    @Test func theDockReturnsWhenGoingBackFromAReconciliation() throws {
        let (app, tabs) = open()
        tabs.select(.accounts)
        tabs.showAccounts([.account(fixture.giro)])
        app.register.reconciliation.reconcileClicked()
        let form = try #require(app.register.reconciliation.statementForm)
        form.amountText = "1111"
        app.register.reconciliation.begin(form)
        #expect(tabs.barTakesDocksPlace)
        tabs.showAccounts([])
        #expect(!tabs.barTakesDocksPlace)
    }

    @Test func showingTheRegisterLeftByGoingBackPushesItAgain() {
        let (app, tabs) = open()
        tabs.select(.accounts)
        tabs.showAccounts([.allAccounts])
        tabs.showAccounts([])
        app.register.showApprovals()
        #expect(tabs.tab == .accounts)
        #expect(tabs.accountPath == [.allAccounts])
        #expect(app.register.filter == .unapproved)
    }

    @Test func showingTheRegisterShownBehindTheSettingsSwitchesToIt() {
        let (app, tabs) = open()
        tabs.showAccounts([.allAccounts])
        tabs.select(.settings)
        app.register.showPayeeTransactions("Rewe", showingScheduled: false)
        #expect(tabs.tab == .accounts)
        #expect(tabs.accountPath == [.allAccounts])
    }

    @Test func showingATransactionOfTheAccountLeftByGoingBackPushesIt() throws {
        let (app, tabs) = open()
        tabs.showAccounts([.account(fixture.giro)])
        tabs.showAccounts([])
        let transaction = try #require(fixture.budget.transactions.first { $0.accountId == fixture.giro })
        app.register.showTransaction(transaction.id)
        #expect(tabs.accountPath == [.account(fixture.giro)])
        #expect(app.register.selectedTransactions.map(\.id) == [transaction.id])
    }

    @Test func theTabAndNewTransactionCommandsWaitWhileASheetIsUp() {
        let budgetFixture = BudgetScreenFixture()
        let app = AppModel(
            store: BudgetStore(budget: budgetFixture.budget, today: { BudgetScreenFixture.today }), selection: .budget,
            defaults: nil, device: .iPhone)
        let tabs = TouchNavigation(app: app)
        #expect(!tabs.showsSheet)
        app.budget.touchLayout = .phone
        app.budget.categoryTapped(BudgetScreenFixture.kino)
        #expect(tabs.showsSheet)
        app.budget.touchSheetDismissed()
        tabs.showAccounts([.allAccounts])
        app.register.scheduledToggleClicked()
        #expect(tabs.showsSheet)
        app.register.scheduledToggleClicked()
        app.accounts.addAccountClicked()
        #expect(tabs.showsSheet)
    }

    @Test func theTabsSwitchBetweenTheBudgetAndTheRegisterLastPushed() {
        let (app, tabs) = open()
        tabs.showAccounts([.account(fixture.tagesgeld)])
        tabs.select(.budget)
        #expect(app.navigation.selection == .budget)
        tabs.select(.settings)
        #expect(tabs.tab == .settings)
        #expect(app.navigation.selection == .budget)
        tabs.select(.accounts)
        #expect(app.navigation.selection == .account(fixture.tagesgeld))
        #expect(tabs.accountPath == [.account(fixture.tagesgeld)])
    }

    @Test func theMenuCommandsSwitchTabs() {
        let (app, tabs) = open()
        tabs.showAccounts([.account(fixture.tagesgeld)])
        tabs.select(.settings)
        tabs.goToBudget()
        #expect(tabs.tab == .budget)
        tabs.select(.accounts)
        tabs.showAccounts([])
        tabs.goToBudget()
        #expect(tabs.tab == .budget)
        tabs.goToSettings()
        #expect(tabs.tab == .settings)
        tabs.goToAccounts()
        #expect(tabs.tab == .accounts)
        #expect(tabs.accountPath == [.account(fixture.tagesgeld)])
        #expect(app.navigation.selection == .account(fixture.tagesgeld))
    }

    @Test func aRegisterShownFromElsewhereOpensOnTheAccountsTab() {
        let (app, tabs) = open()
        tabs.select(.budget)
        app.navigation.selection = .allAccounts
        #expect(tabs.tab == .accounts)
        #expect(tabs.accountPath == [.allAccounts])
    }

    @Test func leavingTheBudgetTabCommitsTheEditedCell() {
        let budgetFixture = BudgetScreenFixture()
        let app = AppModel(
            store: BudgetStore(budget: budgetFixture.budget, today: { BudgetScreenFixture.today }), selection: .budget,
            defaults: nil)
        let tabs = TouchNavigation(app: app)
        app.budget.panelSize = BudgetScreenFixture.panel
        app.budget.beginEdit(app.budget.cell(BudgetScreenFixture.kino))
        app.budget.cellTextChanged("40")
        tabs.select(.settings)
        #expect(app.budget.editor == nil)
    }

    @Test func theAppOpensOnTheScreenLastShown() {
        let storage = MemorySettingsStorage()
        let (_, first) = open(storage)
        first.showAccounts([.account(fixture.tagesgeld)])
        let (secondApp, second) = open(storage)
        #expect(second.tab == .accounts)
        #expect(second.accountPath == [.account(fixture.tagesgeld)])
        #expect(secondApp.navigation.selection == .account(fixture.tagesgeld))
        second.select(.settings)
        let (thirdApp, third) = open(storage)
        #expect(third.tab == .settings)
        #expect(thirdApp.navigation.selection == .account(fixture.tagesgeld))
        third.select(.budget)
        let (fourthApp, fourth) = open(storage)
        #expect(fourth.tab == .budget)
        #expect(fourth.accountPath == [.account(fixture.tagesgeld)])
        #expect(fourthApp.navigation.selection == .budget)
        fourth.select(.accounts)
        fourth.showAccounts([])
        let (_, fifth) = open(storage)
        #expect(fifth.tab == .accounts)
        #expect(fifth.accountPath.isEmpty)
    }

    @Test func theAccountsTabRestoredOverTheBudgetShowsItsRegister() {
        let storage = MemorySettingsStorage()
        let (_, first) = open(storage)
        first.showAccounts([.account(fixture.tagesgeld)])
        let app = AppModel(
            store: BudgetStore(budget: fixture.budget, today: { editDay }), selection: .budget, defaults: storage)
        let tabs = TouchNavigation(app: app)
        #expect(tabs.tab == .accounts)
        #expect(app.navigation.selection == .account(fixture.tagesgeld))
    }

    @Test func aRegisterWhoseAccountIsGoneIsNotRestored() {
        let storage = MemorySettingsStorage()
        let (_, first) = open(storage)
        first.showAccounts([.account("GONE")])
        let (app, second) = open(storage)
        #expect(second.tab == .accounts)
        #expect(second.accountPath.isEmpty)
        #expect(app.navigation.selection == AppModel.defaultSelection(in: fixture.budget))
    }

    @Test func withoutAScreenLastShownTheAppOpensOnTheBudget() {
        let (app, tabs) = open(MemorySettingsStorage())
        #expect(tabs.tab == .budget)
        #expect(tabs.accountPath.isEmpty)
        #expect(app.navigation.selection == .budget)
    }

    @Test func thePayeesPushedFromTheSettingsAreAPageAndCloseWithIt() {
        let (app, tabs) = open()
        tabs.select(.settings)
        tabs.showSettings([.payees])
        #expect(app.payeeSettings != nil)
        #expect(tabs.settingsPath == [.payees])
        #expect(!tabs.showsPayeeSheet)
        #expect(!tabs.showsSheet)
        tabs.isPickingPayees = true
        #expect(tabs.barTakesDocksPlace)
        tabs.showSettings([])
        #expect(app.payeeSettings == nil)
        #expect(!tabs.isPickingPayees)
    }

    @Test func leavingTheSettingsClosesThePayeesShownThere() {
        let (app, tabs) = open()
        tabs.select(.settings)
        tabs.showSettings([.payees, .payee])
        tabs.goToBudget()
        #expect(app.payeeSettings == nil)
        #expect(tabs.settingsPath.isEmpty)
    }

    @Test func payeesClosedElsewhereTakeTheirPagesAndThePickingWithThem() throws {
        let (app, tabs) = open()
        tabs.select(.settings)
        tabs.showSettings([.payees])
        tabs.isPickingPayees = true
        try #require(app.payeeSettings).close()
        #expect(tabs.settingsPath.isEmpty)
        #expect(!tabs.isPickingPayees)
        #expect(!tabs.barTakesDocksPlace)
    }

    @Test func payeesOpenedLaterOnTheSettingsAreASheet() {
        let (app, tabs) = open()
        tabs.select(.settings)
        tabs.showSettings([.payees])
        app.payeeSettings?.close()
        app.openPayeeSettings(payeeName: nil)
        #expect(tabs.settingsPath.isEmpty)
        #expect(tabs.showsPayeeSheet)
        #expect(tabs.showsSheet)
    }

    @Test func aNewTransactionClosesThePayeesShownInTheSettings() {
        let (app, tabs) = open()
        tabs.select(.settings)
        tabs.showSettings([.payees])
        tabs.addTransactionClicked()
        #expect(app.payeeSettings == nil)
        #expect(tabs.settingsPath.isEmpty)
        #expect(app.register.editor != nil)
    }
}
