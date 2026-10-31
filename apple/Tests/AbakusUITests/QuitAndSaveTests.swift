import Foundation
import Testing

@testable import AbakusCore
@testable import AbakusUI

@MainActor
@Suite struct QuitAndSaveTests {
    private func app(
        _ fixture: RegisterFixture, store: BudgetStore? = nil, selection: SidebarSelection? = nil
    ) -> AppModel {
        let app = AppModel(
            store: store ?? BudgetStore(budget: fixture.budget), selection: selection ?? .account(fixture.giro),
            defaults: nil)
        app.register.today = { editDay }
        return app
    }

    enum OtherDialog: CaseIterable {
        case message, clockQuestion

        @MainActor func show(in app: AppModel) {
            switch self {
            case .message: app.register.showMessage("Message", "")
            case .clockQuestion: app.dateChecked(today: app.store.today().addingDays(3))
            }
        }
    }

    @Test(arguments: OtherDialog.allCases)
    func quittingSavesAnOpenEditUnderAnotherDialog(_ dialog: OtherDialog) throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10, category: fixture.groceries, memo: "Box")
        let app = app(fixture, selection: .allAccounts)
        app.register.beginEditing(id, column: .memo)
        try #require(app.register.editor).retype("Kiste")
        dialog.show(in: app)
        #expect(app.dialogs.isPresenting)
        #expect(app.commitBeforeQuit())
        #expect(app.store.budget.transaction(withId: id)?.memo == "Kiste")
        #expect(app.register.editor == nil)
    }

    @Test func quittingSavesAnOpenScheduledEdit() throws {
        var fixture = RegisterFixture()
        let transaction = Transaction(
            id: "S1", accountId: fixture.giro, date: day("2014-06-02"), categoryId: fixture.groceries,
            memo: "Box", amount: -25)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, frequency: .monthly, payeeName: "Farm", isNew: true)))
        let app = app(fixture)
        app.register.scheduler.beginEditing("S1", column: .memo)
        try #require(app.register.scheduler.editor).retype("Kiste")
        #expect(app.commitBeforeQuit())
        #expect(app.store.budget.scheduledTransaction(withId: "S1")?.memo == "Kiste")
        #expect(app.register.scheduler.editor == nil)
    }

    @Test func quittingSavesAnOpenBudgetCellEdit() {
        let store = BudgetStore(budget: BudgetScreenFixture().budget, today: { BudgetScreenFixture.today })
        let app = AppModel(store: store, selection: .budget, defaults: nil)
        app.budget.panelSize = BudgetScreenFixture.panel
        app.budget.beginEdit(app.budget.cell(BudgetScreenFixture.kino))
        app.budget.cellTextChanged("40")
        #expect(app.commitBeforeQuit())
        #expect(app.budget.editor == nil)
        #expect(store.budget.assigned(in: day("2026-10-01"), categoryId: BudgetScreenFixture.kino) == 40)
    }

    @Test func aFailedSaveShowsTheErrorAndRetries() throws {
        let fixture = RegisterFixture()
        let database = try refusingDatabase()
        let store = BudgetStore(budget: fixture.budget, database: database)
        let app = app(fixture, store: store)
        try store.perform(.setCleared([fixture.startingBalanceId(of: fixture.giro)], .uncleared))
        let saveError = try #require(app.saveErrorDialog)
        #expect(saveError.dialog.instruction == "Das Budget ließ sich nicht sichern.")
        #expect(saveError.dialog.content.hasSuffix(try #require(store.lastSaveError)))
        #expect(saveError.dialog.buttons.map(\.title) == ["Erneut versuchen", "Schließen"])
        #expect(saveError.dialog.dismissal == AnyDialogChoice(SaveErrorChoice.close))
        #expect(app.register.isAppModalOpen())
        try database.execute("DROP TRIGGER refuse")
        saveError.answer(SaveErrorChoice.retry)
        #expect(!store.hasUnsavedChanges)
        #expect(app.saveErrorDialog == nil)
    }

    @Test func theSaveErrorKeepsOneSheetAboveTheOtherDialogs() throws {
        let fixture = RegisterFixture()
        let store = BudgetStore(budget: fixture.budget, database: try refusingDatabase())
        let app = app(fixture, store: store)
        try store.perform(.setCleared([fixture.startingBalanceId(of: fixture.giro)], .uncleared))
        app.dialogs.show(.message("below", ""))
        let saveError = try #require(app.saveErrorDialog)
        #expect(app.presentedDialogs.map(\.dialog.instruction) == ["below", "Das Budget ließ sich nicht sichern."])
        #expect(app.presentedDialogs.last?.id == saveError.id)
    }

    @Test func quittingIsRefusedWhileChangesCannotBeWritten() throws {
        let fixture = RegisterFixture()
        let store = BudgetStore(budget: fixture.budget, database: try refusingDatabase())
        let app = app(fixture, store: store)
        try store.perform(.setCleared([fixture.startingBalanceId(of: fixture.giro)], .uncleared))
        app.saveErrorDialog?.answer(SaveErrorChoice.close)
        #expect(app.saveErrorDialog == nil)
        #expect(!app.commitBeforeQuit())
        #expect(app.saveErrorDialog != nil)
    }

    private func refusingDatabase() throws -> BudgetDatabase {
        let database = try BudgetDatabase()
        try database.execute(
            "CREATE TRIGGER refuse BEFORE INSERT ON local_settings BEGIN SELECT RAISE(ABORT, 'Die Platte ist voll'); END"
        )
        return database
    }
}
