import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct KasseAccountTests {
    private func fixture() -> RegisterFixture {
        var fixture = RegisterFixture()
        try! fixture.budget.apply(
            .addAccount(
                NewAccount(id: "KASSE", name: "Spliit", kind: .checking, startingBalance: 0, startDate: editDay)))
        var kasse = fixture.budget.account(withId: "KASSE")!
        kasse.sharedExpenses = true
        try! fixture.budget.apply(.editAccount(kasse))
        fixture.add("KASSE", -14.03, payee: "Aldi", id: "ALDI")
        return fixture
    }

    @Test func itsRegisterTakesNoNewTransactionAndNoReconciling() {
        let model = fixture().model(selection: .account("KASSE"))
        #expect(!model.canAddTransactions)
        #expect(!model.scheduler.canAddTransactions)
        #expect(!model.reconciliation.isReconcileEnabled)
        model.reconciliation.reconcileClicked()
        #expect(model.reconciliation.statementForm == nil)
        #expect(model.banner == .sharedExpenses)
        #expect(model.banner?.message == "Buchungen kommen aus der Kasse, keine Buchungen von Hand.")
    }

    @Test func aNewTransactionNeverOffersItButTransfersIntoItStay() throws {
        let model = fixture().model(selection: .allAccounts)
        #expect(model.canAddTransactions)
        model.grid.beginNew()
        let editor = try #require(model.editor)
        #expect(editor.clone.accountId == "GIRO")
        let accounts = editor.choices(for: .main(.account), matching: "").map(\.label)
        #expect(accounts.contains("Giro"))
        #expect(!accounts.contains("Spliit"))
        let payees = editor.choices(for: .main(.payee), matching: "").map(\.kind)
        #expect(payees.contains(.transfer(accountName: "Spliit")))
    }

    @Test func aNewScheduledTransactionNeverStartsInIt() throws {
        var fixture = fixture()
        let index = fixture.budget.accounts.firstIndex { $0.id == "KASSE" }!
        fixture.budget.accounts[index].position = -1
        let model = fixture.model(selection: .allAccounts)
        model.scheduler.addClicked()
        let editor = try #require(model.scheduler.editor)
        #expect(editor.clone.accountId != "KASSE")
    }

    @Test func itsTransactionsKeepTheirAccountAndStayEditable() throws {
        let model = fixture().model(selection: .account("KASSE"))
        model.beginEditing("ALDI")
        let editor = try #require(model.editor)
        #expect(editor.text(.main(.account)) == "Spliit")
        #expect(!editor.isLocked(.main(.category)))
        #expect(!editor.isLocked(.main(.memo)))
    }
}

@MainActor
@Suite struct ClosedAccountTests {
    private func fixture() -> RegisterFixture {
        var fixture = RegisterFixture()
        var karte = fixture.budget.account(withId: fixture.karte)!
        karte.closed = true
        try! fixture.budget.apply(.editAccount(karte))
        return fixture
    }

    @Test func onlyAlleKontenOffersTheClosedAccounts() throws {
        let fixture = fixture()
        let all = fixture.model(selection: .allAccounts)
        #expect(all.viewMenu.last?.title == "Geschlossene Konten (1) …")
        let touch = try #require(all.touchViewMenu(showsColumns: false).first { $0.kind == .action(.closedAccounts) })
        #expect(touch.title == "Geschlossene Konten (1)")
        #expect(touch.systemImage == "archivebox")
        let giro = fixture.model()
        #expect(!giro.viewMenu.contains { $0.kind == .action(.closedAccounts) })
        let none = RegisterFixture().model(selection: .allAccounts)
        #expect(!none.viewMenu.contains { $0.kind == .action(.closedAccounts) })
    }

    @Test func theListOpensTheChosenAccountWithItsBanner() throws {
        let fixture = fixture()
        let model = fixture.model(selection: .allAccounts)
        model.performMenuAction(.closedAccounts)
        #expect(model.isClosedAccountsListShown)
        #expect(model.closedAccounts == [ClosedAccountRow(id: "KARTE", name: "Karte", detail: "Girokonto · $0.00")])
        model.closedAccountChosen(fixture.karte)
        #expect(!model.isClosedAccountsListShown)
        #expect(model.navigation.selection == .account(fixture.karte))
        #expect(model.banner == .closed)
        #expect(model.banner?.message == "Dieses Konto ist geschlossen.")
        #expect(!model.canAddTransactions)
        #expect(!model.scheduler.canAddTransactions)
        #expect(!model.reconciliation.isReconcileEnabled)
    }

    @Test func reopeningPutsTheAccountBackAndEndsTheList() throws {
        let fixture = fixture()
        let (model, _) = fixture.spied(selection: .account(fixture.karte), appliesCommands: true)
        model.reopenClicked()
        #expect(model.store.budget.account(withId: fixture.karte)?.closed == false)
        #expect(model.banner == nil)
        #expect(model.canAddTransactions)
        model.navigation.selection = .allAccounts
        #expect(!model.viewMenu.contains { $0.kind == .action(.closedAccounts) })
    }
}
