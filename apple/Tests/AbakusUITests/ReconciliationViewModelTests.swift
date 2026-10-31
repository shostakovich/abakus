import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct ReconciliationViewModelTests {
    /// Giro: starting balance 1111 (Cleared, 29/04), a cleared −100 on 10/05, an uncleared −40 on 12/05, a cleared −7
    /// on 25/05 after the statement date.
    private func fixture() -> (RegisterFixture, [String]) {
        var fixture = RegisterFixture()
        let ids = [
            fixture.add(fixture.giro, -100, on: "2014-05-10", cleared: .cleared),
            fixture.add(fixture.giro, -40, on: "2014-05-12"),
            fixture.add(fixture.giro, -7, on: "2014-05-25", cleared: .cleared),
        ]
        return (fixture, ids)
    }

    private func reconciling(
        _ fixture: RegisterFixture, amount: String = "1,011.00", date: String = "2014-05-20"
    ) throws -> (model: RegisterViewModel, store: SpyBudgetStore) {
        let (model, store) = fixture.spied()
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.date = day(date)
        form.amountText = amount
        model.reconciliation.begin(form)
        return (model, store)
    }

    private func finish(
        _ fixture: RegisterFixture, _ ids: [String], balance: Decimal, createsAdjustment: Bool
    ) -> BudgetCommand {
        .finishReconciliation(
            ReconciliationFinish(
                accountId: fixture.giro, statementDate: day("2014-05-20"), statementBalance: balance,
                transactionIds: [fixture.startingBalanceId(of: fixture.giro)] + ids,
                createsAdjustment: createsAdjustment, today: editDay))
    }

    @Test func reconcileOpensTheStatementDialogForTodayWithoutAmount() throws {
        let (model, _) = RegisterFixture().spied()
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        #expect(form.date == editDay)
        #expect(form.amountText.isEmpty)
        #expect(!form.canBegin)
        #expect(form.beginTitle == "Weiter")
        #expect(model.reconciliation.statementHint(form) == "Gebuchter Saldo bis dahin: $1,111.00.")
        model.reconciliation.statementCancelled()
        #expect(model.reconciliation.statementForm == nil)
        #expect(!model.isReconciling)
    }

    @Test func allAccountsCannotReconcile() {
        let (model, _) = RegisterFixture().spied(selection: .allAccounts)
        #expect(!model.reconciliation.isReconcileEnabled)
        model.reconciliation.reconcileClicked()
        #expect(model.reconciliation.statementForm == nil)
        model.reconciliation.reconcileDisabledClicked()
        #expect(model.reconciliation.showsReconcileHelp)
        model.reconciliation.reconcileHelpDismissed()
        #expect(!model.reconciliation.showsReconcileHelp)
    }

    @Test func registerKeysWaitForTheReconcileHelp() {
        let (model, _) = RegisterFixture().spied(selection: .allAccounts)
        model.reconciliation.reconcileDisabledClicked()
        #expect(!model.selectAllKeyPressed())
        model.search.focus()
        #expect(model.search.focusRequest == 0)
        model.reconciliation.reconcileHelpDismissed()
        #expect(model.selectAllKeyPressed())
        model.search.focus()
        #expect(model.search.focusRequest == 1)
    }

    @Test func theStatementBalanceIsTakenAsTyped() throws {
        let fixture = RegisterFixture()
        let (model, _) = fixture.spied(selection: .account(fixture.karte))
        for (typed, shown) in [("50", "$50.00"), ("-50", "-$50.00")] {
            model.reconciliation.reconcileClicked()
            let form = try #require(model.reconciliation.statementForm)
            form.amountText = typed
            model.reconciliation.begin(form)
            #expect(model.reconciliation.footer?.rows[3].value == shown)
        }
    }

    @Test func beginningClosesTheSearchDropDownAndMenus() throws {
        let (model, _) = RegisterFixture().spied()
        model.search.boxChanged("x")
        #expect(model.search.dropDown != nil)
        model.columnOptionsClicked()
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "1111"
        model.reconciliation.begin(form)
        #expect(model.isReconciling)
        #expect(model.search.dropDown == nil)
        #expect(model.menuRequest == nil)
    }

    @Test func reconcilingListsUnreconciledRowsUpToTheStatementDateByDate() throws {
        let (fixture, ids) = fixture()
        let (model, _) = fixture.spied()
        model.search.text = "shop"
        model.search.commit()
        model.grid.headerClicked(.payee)
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.date = day("2014-05-20")
        form.amountText = "1011"
        model.reconciliation.begin(form)
        #expect(model.isReconciling)
        #expect(model.reconciliation.statementForm == nil)
        #expect(model.transactionIds == [fixture.startingBalanceId(of: fixture.giro), ids[0], ids[1]])
        #expect(model.search.text.isEmpty)
        #expect(model.sortOrder == .default)
        #expect(model.visibleColumns.contains(.cleared))
        #expect(model.columnLayout(gridWidth: 700).frame(of: .cleared)?.width == 90)
        #expect(model.search.info?.message == "3 Buchungen bis 20/05/14 (Datum des Banksaldos)")
    }

    @Test func aTypedDateCountsWithoutLeavingTheField() throws {
        let (fixture, _) = fixture()
        let (model, _) = fixture.spied()
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "1011"
        form.typedDate = "20/05/14"
        model.reconciliation.begin(form)
        #expect(model.reconciliation.current?.statementDate == day("2014-05-20"))
    }

    @Test func aStatementBalanceWithoutANumberIsRefused() throws {
        let (model, _) = RegisterFixture().spied()
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "abc"
        model.reconciliation.begin(form)
        #expect(!model.isReconciling)
        let dialog = try #require(model.dialogs.presented.last)
        #expect(dialog.dialog.instruction == "Ungültiger Saldo")
        #expect(dialog.dialog.content == "„abc“ ist keine gültige Zahl.")
        dialog.answer(MessageChoice.close)
        #expect(!model.dialogs.isPresenting)
        #expect(model.reconciliation.statementForm === form)
    }

    @Test func useThisAmountTakesTheTypedDate() throws {
        let (fixture, _) = fixture()
        let (model, _) = fixture.spied()
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.typedDate = "20/05/14"
        model.reconciliation.useClearedBalance(form)
        #expect(model.reconciliation.current?.statementDate == day("2014-05-20"))
        #expect(model.reconciliation.footer?.isBalanced == true)
    }

    @Test func footerSummarisesTheReconciliation() throws {
        let (fixture, _) = fixture()
        let (model, _) = try reconciling(fixture, amount: "1,000.00")
        let footer = try #require(model.reconciliation.footer)
        #expect(
            footer.rows.map(\.label) == [
                "Noch nie abgeglichen", "Oben als gebucht markiert", "Gebuchter Saldo am 20/05/14",
                "Banksaldo am 20/05/14",
            ])
        #expect(footer.rows.map(\.value) == ["$0.00", "$1,011.00", "$1,011.00", "$1,000.00"])
        #expect(footer.rows.map(\.operation) == [nil, .plus, .equals, .minus])
        #expect(footer.rows.compactMap(\.operation?.rawValue) == ["+", "=", "\u{2212}"])
        #expect(footer.difference == "$11.00")
        #expect(!footer.isBalanced)
        #expect(footer.message == "Markiere Buchungen oben als gebucht,\nbis die Salden übereinstimmen")
    }

    @Test func theActionsReadStopAdjustFinish() throws {
        let (fixture, ids) = fixture()
        let (model, store) = try reconciling(fixture)
        #expect(
            ReconciliationAction.allCases.map(\.title)
                == ["Abgleich abbrechen", "Banksaldo ändern", "Abgleichen"])
        model.reconciliation.perform(.adjust)
        #expect(model.reconciliation.statementForm?.isContinuing == true)
        model.reconciliation.statementCancelled()
        model.reconciliation.perform(.finish)
        #expect(store.commands == [finish(fixture, [ids[0], ids[1]], balance: 1011, createsAdjustment: false)])
    }

    @Test func stopActionLeavesTheReconciliation() throws {
        let (fixture, _) = fixture()
        let (model, _) = try reconciling(fixture)
        model.reconciliation.perform(.stop)
        #expect(!model.isReconciling)
    }

    @Test func useThisAmountStartsWithTheClearedBalanceThroughTheDate() throws {
        let (fixture, _) = fixture()
        let (model, _) = fixture.spied()
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.date = day("2014-05-20")
        model.reconciliation.useClearedBalance(form)
        #expect(model.isReconciling)
        #expect(model.reconciliation.footer?.isBalanced == true)
        #expect(model.reconciliation.footer?.message == "Die Salden stimmen überein.\nDas Konto ist jetzt abgeglichen")
    }

    @Test func balancedFinishReconcilesWithoutAsking() throws {
        let (fixture, ids) = fixture()
        let (model, store) = try reconciling(fixture)
        model.reconciliation.finishReconciliationClicked()
        #expect(!model.dialogs.isPresenting)
        #expect(!model.isReconciling)
        #expect(store.commands == [finish(fixture, [ids[0], ids[1]], balance: 1011, createsAdjustment: false)])
    }

    @Test func unbalancedFinishOffersAnAdjustment() throws {
        let (fixture, ids) = fixture()
        let (model, store) = try reconciling(fixture, amount: "1,000.00")
        model.reconciliation.finishReconciliationClicked()
        let dialog = try #require(model.dialogs.presented.last?.dialog)
        #expect(dialog.instruction == "Die Salden stimmen nicht überein.")
        #expect(dialog.buttons.map(\.title) == ["Ausgleichen und abgleichen", "Weiter abgleichen"])
        #expect(dialog.dismissal == AnyDialogChoice(UnbalancedChoice.continueReconciling))
        model.dialogs.presented.last?.answer(UnbalancedChoice.continueReconciling)
        #expect(model.isReconciling)
        #expect(store.commands.isEmpty)
        model.reconciliation.finishReconciliationClicked()
        model.dialogs.presented.last?.answer(UnbalancedChoice.createAdjustment)
        #expect(!model.isReconciling)
        #expect(store.commands == [finish(fixture, [ids[0], ids[1]], balance: 1000, createsAdjustment: true)])
    }

    @Test func adjustStatementReopensTheDialogToContinue() throws {
        let (fixture, _) = fixture()
        let (model, _) = try reconciling(fixture, amount: "1,000.00")
        model.reconciliation.adjustStatementClicked()
        let form = try #require(model.reconciliation.statementForm)
        #expect(form.isContinuing)
        #expect(form.beginTitle == "Übernehmen")
        #expect(form.amountText == "1000.00")
        #expect(form.date == day("2014-05-20"))
        form.amountText = "1011"
        model.reconciliation.begin(form)
        #expect(model.reconciliation.footer?.isBalanced == true)
    }

    @Test func stopReconcilingRestoresTheRegisterWithoutChanges() throws {
        let (fixture, _) = fixture()
        let (model, store) = fixture.spied()
        model.scheduledToggleClicked()
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "5"
        model.reconciliation.begin(form)
        #expect(!model.isSchedulerVisible)
        model.reconciliation.stopReconcilingClicked()
        #expect(!model.isReconciling)
        #expect(model.isSchedulerVisible)
        #expect(store.commands.isEmpty)
        #expect(model.transactionIds.count == 4)
    }

    @Test func clearedPillTogglesThroughTheClearedColumn() throws {
        let (fixture, ids) = fixture()
        var cleared = fixture.budget
        cleared.transactions[cleared.transactions.firstIndex { $0.id == ids[1] }!].cleared = .cleared
        let (model, store) = try reconciling(fixture, amount: "1,000.00")
        let row = try #require(model.rows.first { $0.transactionId == ids[1] })
        store.budgetAfterNextCommand = cleared
        model.clearedClicked(row)
        #expect(store.commands == [.toggleCleared([ids[1]])])
        #expect(model.reconciliation.footer?.rows[1].value == "$971.00")
        #expect(model.transactionIds.contains(ids[1]))
        store.budgetAfterNextCommand = fixture.budget
        model.clearedClicked(try #require(model.rows.first { $0.transactionId == ids[1] }))
        #expect(store.commands == [.toggleCleared([ids[1]]), .toggleCleared([ids[1]])])
        #expect(model.reconciliation.footer?.rows[1].value == "$1,011.00")
    }

    @Test func searchFiltersInsideTheReconciliationList() throws {
        let (fixture, ids) = fixture()
        let (model, _) = try reconciling(fixture)
        #expect(model.search.info?.clearButtonTitle == nil)
        model.search.boxChanged("Shop")
        model.search.submitted()
        #expect(model.transactionIds == [ids[0], ids[1]])
        #expect(
            model.search.info?.message == "2 Buchungen für „Shop“ bis 20/05/14 (Datum des Banksaldos)")
        #expect(model.search.info?.clearButtonTitle == "Suche zurücksetzen")
        model.search.clearClicked()
        #expect(model.isReconciling)
        #expect(model.transactionIds.count == 3)
        #expect(model.search.info?.clearButtonTitle == nil)
    }

    @Test func leavingRestoresTheSearchFromBeforeTheReconciliation() throws {
        let (fixture, ids) = fixture()
        let (model, _) = fixture.spied()
        model.search.run("Empfänger: Shop")
        model.search.dateSelectorClicked()
        #expect(model.popup == .timeframe)
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "1011"
        model.reconciliation.begin(form)
        #expect(model.popup == nil)
        #expect(model.search.filter == nil)
        model.search.run("Memo: x")
        #expect(model.transactionIds.isEmpty)
        model.reconciliation.stopReconcilingClicked()
        #expect(model.search.filter?.label == "Empfänger: Shop")
        #expect(model.transactionIds == ids)
    }

    @Test func leavingKeepsTheScrollPositionFromBeforeTheFirstSearch() throws {
        let (fixture, _) = fixture()
        let (model, _) = fixture.spied()
        model.saveScrollOffset(120)
        model.search.run("Empfänger: Shop")
        model.reconciliation.reconcileClicked()
        let form = try #require(model.reconciliation.statementForm)
        form.amountText = "1011"
        model.reconciliation.begin(form)
        model.saveScrollOffset(48)
        model.search.run("Memo: x")
        model.reconciliation.stopReconcilingClicked()
        #expect(model.search.filter?.label == "Empfänger: Shop")
        model.search.clearClicked()
        #expect(model.grid.scrollRequest?.target == .offset(120))
    }

    @Test func notifierLinksSearchWithinTheReconciliation() throws {
        var fixture = fixture().0
        let imported = fixture.add(
            fixture.giro, -3, on: "2014-05-15", category: fixture.groceries, approved: false, source: .bank)
        fixture.add(fixture.giro, -4, on: "2014-05-28", category: fixture.groceries, approved: false, source: .bank)
        let (model, _) = try reconciling(fixture)
        #expect(model.notifiers.list.first { $0.kind == .reminder }?.text.hasPrefix("2 ") == true)
        model.notifiers.clicked(.reminder)
        #expect(model.isReconciling)
        #expect(model.transactionIds == [imported])
    }

    @Test func registerKeysWaitForTheStatementDialog() throws {
        let (fixture, _) = fixture()
        let (model, _) = fixture.spied()
        model.reconciliation.reconcileClicked()
        #expect(!model.selectAllKeyPressed())
        let row = try #require(model.rows.first)
        #expect(model.contextMenu(for: row) == nil)
        model.reconciliation.statementCancelled()
        #expect(model.selectAllKeyPressed())
    }

    @Test func reconciliationLastsWhileSwitchingAccounts() throws {
        let (fixture, _) = fixture()
        let (model, _) = try reconciling(fixture)
        model.navigation.selection = .account(fixture.tagesgeld)
        #expect(!model.isReconciling)
        model.navigation.selection = .account(fixture.giro)
        #expect(model.isReconciling)
    }
}
