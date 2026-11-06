import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct AccountsControllerTests {
    private func app(_ fixture: RegisterFixture = RegisterFixture()) -> AppModel {
        AppModel(store: BudgetStore(budget: fixture.budget, today: { editDay }), defaults: nil)
    }

    @Test func addFormStartsAsAnUnnamedGirokontoWithoutBalance() throws {
        let app = app()
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        #expect(form.name.isEmpty)
        #expect(form.balanceText == "0.00")
        #expect(form.type == .checking)
        #expect(!form.canCreate)
        form.name = "  "
        #expect(!form.canCreate)
        form.name = "Haushaltskasse"
        #expect(form.canCreate)
    }

    @Test func createAddsTheAccountWithItsStartingBalanceAndSelectsIt() throws {
        let app = app()
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        form.name = "  Sparbuch  "
        form.balanceText = "300"
        form.type = .savings
        #expect(form.canCreate)
        app.accounts.createAccountClicked()
        #expect(app.accounts.addForm == nil)
        let account = try #require(app.store.budget.account(named: "Sparbuch"))
        #expect(account.kind == .savings)
        #expect(account.onBudget)
        let start = try #require(app.store.budget.transactions(inAccount: account.id).first)
        #expect(start.amount == 300)
        #expect(start.date == editDay)
        #expect(start.cleared == .cleared)
        #expect(start.categoryId == app.store.budget.readyToAssignCategoryId)
        #expect(app.navigation.selection == .account(account.id))
    }

    @Test func aZeroBalanceBooksNothing() throws {
        let app = app()
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        form.name = "Kreditkarte 2"
        app.accounts.createAccountClicked()
        let account = try #require(app.store.budget.account(named: "Kreditkarte 2"))
        #expect(app.store.budget.transactions(inAccount: account.id).isEmpty)
    }

    @Test func aTrackingAccountTakesANegativeBalanceWithoutAsking() throws {
        let app = app()
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        form.name = "Kredit"
        form.balanceText = "-5000"
        form.type = .tracking
        app.accounts.createAccountClicked()
        #expect(!app.dialogs.isPresenting)
        let account = try #require(app.store.budget.account(named: "Kredit"))
        #expect(!account.onBudget)
        let start = try #require(app.store.budget.transactions(inAccount: account.id).first)
        #expect(start.amount == -5000)
        #expect(start.categoryId == nil)
    }

    @Test func negativeAssetBalanceAsksFirst() throws {
        let app = app()
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        form.name = "Neues Konto"
        form.balanceText = "-20"
        app.accounts.createAccountClicked()
        let dialog = try #require(app.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Soll der Saldo negativ sein? (−$20.00)")
        #expect(dialog.buttons.map(\.title) == ["Der Betrag stimmt", "Korrigieren"])
        #expect(dialog.dismissal == AnyDialogChoice(BalanceSignChoice.fix))
        app.dialogs.presented.last?.answer(BalanceSignChoice.fix)
        #expect(app.accounts.addForm != nil)
        app.accounts.createAccountClicked()
        app.dialogs.presented.last?.answer(BalanceSignChoice.correct)
        #expect(app.accounts.addForm == nil)
        #expect(app.store.budget.account(named: "Neues Konto") != nil)
    }

    @Test func invalidNamesKeepTheDialogOpen() throws {
        let app = app()
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        form.name = "alle konten"
        form.type = .cash
        app.accounts.createAccountClicked()
        #expect(app.dialogs.presented.last?.dialog.instruction == "Bitte einen anderen Kontonamen wählen.")
        #expect(app.dialogs.presented.last?.dialog.content == "Ein Konto mit diesem Namen gibt es schon.")
        #expect(app.accounts.addForm != nil)
    }

    @Test func editRenamesAndRetypes() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.accounts.editAccountRequested(fixture.tagesgeld)
        let form = try #require(app.accounts.editForm)
        #expect(form.name == "Tagesgeld")
        #expect(form.typeChoices == [.checking, .savings, .cash])
        form.name = "Sparkonto "
        form.type = .cash
        app.accounts.editDoneClicked()
        #expect(app.accounts.editForm == nil)
        let account = try #require(app.store.budget.account(withId: fixture.tagesgeld))
        #expect(account.name == "Sparkonto")
        #expect(account.kind == .cash)
    }

    @Test func editingAnAccountInACollapsedGroupExpandsItAndScrollsToTheRow() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.sidebar.setGroup(.budgetAccounts, expanded: false)
        app.accounts.editAccountRequested(fixture.tagesgeld)
        #expect(!app.sidebar.collapsedGroups.contains(.budgetAccounts))
        #expect(app.sidebar.revealRequest?.selection == .account(fixture.tagesgeld))
    }

    @Test func aTrackingAccountStaysATrackingAccount() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.accounts.editAccountRequested(fixture.depot)
        #expect(try #require(app.accounts.editForm).typeChoices == [.tracking])
    }

    @Test func editRefusesDuplicateAndEmptyNames() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.accounts.editAccountRequested(fixture.tagesgeld)
        let form = try #require(app.accounts.editForm)
        form.name = "Giro"
        app.accounts.editDoneClicked()
        #expect(app.dialogs.presented.last?.dialog.content == "Es gibt schon ein Konto „Giro“.")
        #expect(app.accounts.editForm != nil)
        app.dialogs.presented.last?.answer(MessageChoice.close)
        form.name = " "
        app.accounts.editDoneClicked()
        #expect(app.dialogs.presented.last?.dialog.instruction == "Bitte einen Kontonamen eingeben.")
    }

    @Test func closingAsksOnceAndKeepsTheAccountOnScreen() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.navigation.selection = .account(fixture.giro)
        app.accounts.editAccountRequested(fixture.giro)
        try #require(app.accounts.editForm).name = "Hauskonto"
        app.accounts.closeAccountClicked()
        let question = try #require(app.dialogs.presented.last)
        #expect(question.dialog.instruction == "Konto „Giro“ schließen?")
        #expect(question.dialog.content == "Es hat noch einen Saldo von <b>$1,111.00</b>.")
        #expect(question.dialog.buttons.map(\.title) == ["Abbrechen", "Schließen"])
        question.answer(CloseAccountChoice.cancel)
        #expect(app.store.budget.account(withId: fixture.giro)?.closed == false)
        #expect(app.accounts.editForm != nil)
        app.accounts.closeAccountClicked()
        app.dialogs.presented.last?.answer(CloseAccountChoice.close)
        let account = try #require(app.store.budget.account(withId: fixture.giro))
        #expect(account.closed)
        #expect(account.name == "Hauskonto")
        #expect(app.accounts.editForm == nil)
        #expect(app.navigation.selection == .account(fixture.giro))
        #expect(app.register.banner == .closed)
    }

    @Test func aClosedAccountsFormOffersNoClosing() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.accounts.editAccountRequested(fixture.giro)
        #expect(try #require(app.accounts.editForm).canClose)
        app.accounts.closeAccountClicked()
        app.dialogs.presented.last?.answer(CloseAccountChoice.close)
        app.accounts.editAccountRequested(fixture.giro)
        #expect(try !#require(app.accounts.editForm).canClose)
        app.accounts.closeAccountClicked()
        #expect(!app.dialogs.isPresenting)
    }

    @Test func closingAnEmptyAccountSaysItCanBeReopened() throws {
        var fixture = RegisterFixture()
        try fixture.budget.apply(
            .addAccount(NewAccount(id: "LEER", name: "Leer", kind: .cash, startingBalance: 0, startDate: editDay)))
        let app = app(fixture)
        app.accounts.editAccountRequested("LEER")
        app.accounts.closeAccountClicked()
        #expect(app.dialogs.presented.last?.dialog.content == "Du kannst es später wieder öffnen.")
    }

    @Test func balancesWithoutANumberAreRefused() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        form.name = "Bar"
        form.balanceText = "abc"
        app.accounts.createAccountClicked()
        #expect(app.dialogs.presented.last?.dialog.instruction == "Ungültiger Saldo")
        #expect(app.dialogs.presented.last?.dialog.content == "„<b>abc</b>“ ist keine gültige Zahl.")
        app.dialogs.presented.last?.answer(MessageChoice.close)
        #expect(app.accounts.addForm === form)
        #expect(app.store.budget.accounts.count == 4)
    }

    @Test func aNewDayOrAJumpOfSeveralDaysEntersDueSchedules() throws {
        var fixture = RegisterFixture()
        let tomorrow = editDay.addingDays(1)
        let transaction = Transaction(id: "S1", accountId: fixture.giro, date: tomorrow, amount: -5)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, repeats: .every(1, .week), payeeName: "Bakery", isNew: true)))
        let app = app(fixture)
        app.dateChecked(today: tomorrow)
        #expect(app.store.budget.transactions.filter { $0.source == .scheduled }.count == 1)
        app.dateChecked(today: tomorrow.addingDays(14))
        #expect(!app.dialogs.isPresenting)
        #expect(app.store.budget.transactions.filter { $0.source == .scheduled }.count == 3)
    }

    @Test func accountPropertiesOpensTheEditCalloutOfTheShownAccount() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.navigation.selection = .account(fixture.tagesgeld)
        #expect(app.showsAccountProperties)
        app.accountPropertiesClicked()
        #expect(app.accounts.editForm?.accountId == fixture.tagesgeld)
        app.accounts.editCancelled()
        app.navigation.selection = .allAccounts
        #expect(!app.showsAccountProperties)
        app.accountPropertiesClicked()
        #expect(app.accounts.editForm == nil)
        app.navigation.selection = .budget
        #expect(!app.showsAccountProperties)
    }

    @Test func goToAccountsReturnsToTheLastShownRegister() {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.navigation.selection = .account(fixture.tagesgeld)
        app.goToBudget()
        app.goToAccounts()
        #expect(app.navigation.selection == .account(fixture.tagesgeld))
        app.navigation.selection = .allAccounts
        app.goToBudget()
        app.goToAccounts()
        #expect(app.navigation.selection == .allAccounts)
    }

    @Test func accountDialogsHoldBackTheRegisterKeys() {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.navigation.selection = .account(fixture.giro)
        app.accounts.editAccountRequested(fixture.giro)
        #expect(!app.register.selectAllKeyPressed())
        app.accounts.editCancelled()
        #expect(app.register.selectAllKeyPressed())
        #expect(!app.register.selectedTransactionIds.isEmpty)
    }
}
