import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct AccountsControllerTests {
    private func app(_ fixture: RegisterFixture = RegisterFixture()) -> AppModel {
        AppModel(store: BudgetStore(budget: fixture.budget, today: { editDay }), defaults: nil)
    }

    @Test func addFormStartsUntypedWithAUniqueName() throws {
        var fixture = RegisterFixture()
        try fixture.budget.apply(
            .addAccount(
                NewAccount(name: "Neues Konto", kind: .cash, startingBalance: 0, startDate: editDay)))
        let app = app(fixture)
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        #expect(form.name == "Neues Konto 2")
        #expect(form.balanceText == "0.00")
        #expect(form.date == editDay)
        #expect(form.type == nil)
        #expect(!form.canCreate)
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
        #expect(start.categoryId == app.store.budget.readyToAssignCategoryId)
        #expect(app.navigation.selection == .account(account.id))
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
        form.balanceText = "-20"
        form.type = .checking
        app.accounts.createAccountClicked()
        let dialog = try #require(app.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Soll der Anfangssaldo negativ sein? (-$20.00)")
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

    @Test func closingTheSelectedAccountSelectsItsNeighbour() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.accounts.editAccountRequested(fixture.giro)
        let form = try #require(app.accounts.editForm)
        #expect(!app.accounts.isClosed(form))
        app.accounts.closeOrReopenClicked()
        #expect(app.store.budget.account(withId: fixture.giro)?.closed == true)
        #expect(app.navigation.selection == .account(fixture.tagesgeld))
        app.accounts.editAccountRequested(fixture.giro)
        #expect(app.accounts.isClosed(try #require(app.accounts.editForm)))
        app.accounts.closeOrReopenClicked()
        #expect(app.store.budget.account(withId: fixture.giro)?.closed == false)
    }

    @Test func adjustBalanceAddsAnAdjustmentAfterTheSignCheck() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.accounts.editAccountRequested(fixture.giro)
        app.accounts.adjustBalanceClicked()
        let form = try #require(app.accounts.balanceForm)
        #expect(app.accounts.editForm == nil)
        #expect(form.title == "Saldo von „Giro“ anpassen")
        #expect(form.fieldLabel == "Neuer Arbeitssaldo")
        #expect(form.amountText == "1111.00")
        #expect(form.workingBalanceText == "$1,111.00")
        form.amountText = "-5"
        let before = app.store.budget.transactions
        app.accounts.adjustClicked()
        let signCheck = try #require(app.dialogs.presented.last)
        #expect(signCheck.dialog.instruction == "Soll der Saldo negativ sein?")
        #expect(signCheck.dialog.dismissal == AnyDialogChoice(BalanceSignChoice.fix))
        signCheck.answer(signCheck.dialog.dismissal)
        #expect(!app.dialogs.isPresenting)
        #expect(app.accounts.balanceForm != nil)
        #expect(app.store.budget.transactions == before)
        app.accounts.adjustClicked()
        app.dialogs.presented.last?.answer(BalanceSignChoice.correct)
        #expect(app.accounts.balanceForm == nil)
        let adjustment = try #require(app.store.budget.transactions(inAccount: fixture.giro).last)
        #expect(app.store.budget.payeeName(of: adjustment) == "Saldoanpassung")
        #expect(adjustment.amount == -1116)
    }

    @Test func fixingTheSignKeepsTheBalanceForm() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.accounts.editAccountRequested(fixture.giro)
        app.accounts.adjustBalanceClicked()
        try #require(app.accounts.balanceForm).amountText = "-5"
        app.accounts.adjustClicked()
        app.dialogs.presented.last?.answer(BalanceSignChoice.fix)
        #expect(!app.dialogs.isPresenting)
        #expect(app.accounts.balanceForm != nil)
        #expect(app.store.budget.balances(forAccount: fixture.giro).working == 1111)
    }

    @Test func balancesWithoutANumberAreRefused() throws {
        let fixture = RegisterFixture()
        let app = app(fixture)
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        form.type = .cash
        form.balanceText = "abc"
        app.accounts.createAccountClicked()
        #expect(app.dialogs.presented.last?.dialog.instruction == "Ungültiger Saldo")
        #expect(app.dialogs.presented.last?.dialog.content == "„<b>abc</b>“ ist keine gültige Zahl.")
        app.dialogs.presented.last?.answer(MessageChoice.close)
        #expect(app.accounts.addForm === form)
        #expect(app.store.budget.accounts.count == 4)
        app.accounts.addCancelled()
        app.accounts.editAccountRequested(fixture.giro)
        app.accounts.adjustBalanceClicked()
        try #require(app.accounts.balanceForm).amountText = "x<y"
        app.accounts.adjustClicked()
        #expect(app.dialogs.presented.last?.dialog.content == "„x&lt;y“ ist keine gültige Zahl.")
        #expect(app.accounts.balanceForm != nil)
    }

    @Test func adjustingJumpsToTheAdjustmentAndExplainsIt() throws {
        let fixture = RegisterFixture()
        let app = AppModel(
            store: BudgetStore(budget: fixture.budget), selection: .account(fixture.tagesgeld), defaults: nil)
        app.accounts.today = { editDay }
        app.accounts.editAccountRequested(fixture.giro)
        app.accounts.adjustBalanceClicked()
        try #require(app.accounts.balanceForm).amountText = "1200"
        app.accounts.adjustClicked()
        let adjustment = try #require(app.store.budget.transactions(inAccount: fixture.giro).last)
        #expect(app.navigation.selection == .account(fixture.giro))
        #expect(app.register.selectedTransactionIds == [adjustment.id])
        #expect(app.register.grid.scrollRequest?.target == .row(adjustment.id))
        let help = try #require(app.register.adjustmentHelp)
        #expect(help.transactionId == adjustment.id)
        #expect(help.message == "Die Saldoanpassung ist als „Zu verteilen“ gebucht.")
        #expect(app.register.isAppModalOpen())
        app.register.adjustmentHelpDismissed()
        #expect(app.register.adjustmentHelp == nil)
    }

    @Test func adjustingFromAllAccountsStaysThere() throws {
        let fixture = RegisterFixture()
        let app = AppModel(store: BudgetStore(budget: fixture.budget), selection: .allAccounts, defaults: nil)
        app.accounts.today = { editDay }
        app.accounts.editAccountRequested(fixture.depot)
        app.accounts.adjustBalanceClicked()
        try #require(app.accounts.balanceForm).amountText = "-50"
        app.accounts.adjustClicked()
        #expect(!app.dialogs.isPresenting)
        #expect(app.navigation.selection == .allAccounts)
        let help = try #require(app.register.adjustmentHelp)
        #expect(
            help.message == "Die Saldoanpassung ist ohne Kategorie gebucht, weil ein Trackingkonto keine braucht.")
    }

    @Test func aNewDayEntersDueSchedulesAndAJumpAsksFirst() throws {
        var fixture = RegisterFixture()
        let tomorrow = editDay.addingDays(1)
        let transaction = Transaction(id: "S1", accountId: fixture.giro, date: tomorrow, amount: -5)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, frequency: .daily, payeeName: "Bakery", isNew: true)))
        let app = app(fixture)
        app.dateChecked(today: tomorrow)
        #expect(!app.dialogs.isPresenting)
        let entered = app.store.budget.transactions.filter { $0.source == .scheduled }
        #expect(entered.count == 1)
        app.dateChecked(today: tomorrow.addingDays(4))
        #expect(app.dialogs.presented.last?.dialog.instruction == "Stimmt die Uhr deines Mac?")
        app.dialogs.presented.last?.answer(ClockChoice.enterDue)
        #expect(app.store.budget.transactions.filter { $0.source == .scheduled }.count == 5)
    }

    @Test func aClockJumpCanBeIgnoredAndEscapeTakesTheDate() throws {
        var fixture = RegisterFixture()
        let transaction = Transaction(id: "S1", accountId: fixture.giro, date: editDay.addingDays(1), amount: -5)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, frequency: .daily, payeeName: "Bakery", isNew: true)))
        let app = app(fixture)
        app.dateChecked(today: editDay.addingDays(3))
        let dialog = try #require(app.dialogs.presented.last)
        #expect(dialog.dialog.dismissal == AnyDialogChoice(ClockChoice.enterDue))
        dialog.answer(ClockChoice.ignore)
        #expect(!app.dialogs.isPresenting)
        #expect(!app.store.budget.transactions.contains { $0.source == .scheduled })
    }

    @Test func aSecondClockJumpReplacesTheOpenQuestionWithTheNewerDate() throws {
        var fixture = RegisterFixture()
        let transaction = Transaction(id: "S1", accountId: fixture.giro, date: editDay.addingDays(1), amount: -5)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, frequency: .daily, payeeName: "Bakery", isNew: true)))
        let app = app(fixture)
        app.dateChecked(today: editDay.addingDays(3))
        app.dateChecked(today: editDay.addingDays(6))
        #expect(app.dialogs.presented.count == 1)
        app.dialogs.presented.last?.answer(ClockChoice.enterDue)
        #expect(app.store.budget.transactions.filter { $0.source == .scheduled }.count == 6)
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
