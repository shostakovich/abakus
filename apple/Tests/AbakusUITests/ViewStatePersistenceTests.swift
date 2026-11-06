import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct ViewStatePersistenceTests {
    private let fixture = RegisterFixture()

    private func launch(
        _ storage: MemorySettingsStorage, budget: Budget? = nil, selection: SidebarSelection? = nil
    ) -> AppModel {
        AppModel(
            store: BudgetStore(budget: budget ?? fixture.budget, today: { editDay }),
            selection: selection ?? .account(fixture.giro),
            defaults: storage)
    }

    @Test func registerViewStateSurvivesARelaunch() {
        let storage = MemorySettingsStorage()
        let register = launch(storage).register
        register.toggleColumnVisibility(.cleared)
        register.grid.headerClicked(.payee)
        register.viewMenuChosen(.filter(.uncleared))
        register.scheduledToggleClicked()
        register.scheduler.setHeight(240)
        register.scheduler.grid.headerClicked(.payee)
        register.scheduler.toggleColumnVisibility(.memo)
        register.search.boxChanged("Shop")

        let restored = launch(storage).register
        #expect(!restored.visibleColumns.contains(.cleared))
        #expect(restored.sortOrder == RegisterSortOrder(column: .payee, ascending: true))
        #expect(restored.filter == .all)
        #expect(restored.isSchedulerVisible)
        #expect(restored.scheduler.savedHeight == 240)
        #expect(restored.scheduler.sortOrder == RegisterSortOrder(column: .payee, ascending: true))
        #expect(restored.scheduler.columnSettings[.memo]?.visible == false)
        #expect(restored.search.text.isEmpty)
    }

    @Test func theColumnsShowOrHideInEveryAccountAndSurviveARelaunch() {
        let storage = MemorySettingsStorage()
        let register = launch(storage).register
        register.viewMenuChosen(.toggleColumn(.memo))
        register.navigation.selection = .account(fixture.tagesgeld)
        #expect(!register.visibleColumns.contains(.memo))
        register.navigation.selection = .allAccounts
        #expect(!register.visibleColumns.contains(.memo))
        #expect(register.viewMenu.first { $0.title == "Memo" }?.isChecked == false)
        #expect(!launch(storage, selection: .account(fixture.karte)).register.visibleColumns.contains(.memo))
    }

    @Test func aStateSavedWithTheReconciledSwitchAndADateRangeStillLoads() throws {
        let saved = try JSONDecoder().decode(
            SavedRegisterViewState.self,
            from: Data(
                """
                {"sortColumn": "date", "sortAscending": false, "sortVersion": 2, "isShowingReconciled": false,
                 "columns": {}, "isSchedulerVisible": false,
                 "dates": {"preset": "thisMonth", "start": "2014-05-01", "end": "2014-05-01"}}
                """.utf8))
        #expect(RegisterAccountViewState(saved: saved).filter == .all)
    }

    @Test func theOldDefaultSortGivesWayToNewestFirst() throws {
        let saved = { (version: String) in
            try JSONDecoder().decode(
                SavedRegisterViewState.self,
                from: Data(
                    """
                    {"sortColumn": "date", "sortAscending": true, \(version)
                     "isShowingReconciled": true, "columns": {}, "isSchedulerVisible": false}
                    """.utf8))
        }
        #expect(try saved("").restoredSort == nil)
        #expect(try saved(#""sortVersion": 2,"#).restoredSort == RegisterSortOrder(column: .date, ascending: true))
        #expect(RegisterSortOrder.default == RegisterSortOrder(column: .date, ascending: false))
    }

    @Test func savedAusgangAndEingangSettingsGiveWayToBetrag() throws {
        let saved = try JSONDecoder().decode(
            SavedRegisterViewState.self,
            from: Data(
                """
                {"sortColumn": "outflow", "sortAscending": true, "sortVersion": 2, "isShowingReconciled": true,
                 "columns": {"outflow": {"visible": false, "width": 300}, "inflow": {"visible": false, "width": 300}},
                 "isSchedulerVisible": false, "schedulerSort": {"column": "inflow", "ascending": false},
                 "schedulerColumns": {"outflow": {"visible": false, "width": 300}}}
                """.utf8))
        let state = RegisterAccountViewState(saved: saved)
        let defaults = RegisterAccountViewState()
        #expect(state.sort == defaults.sort)
        #expect(state.schedulerSort == defaults.schedulerSort)
        #expect(state.schedulerColumnSettings == defaults.schedulerColumnSettings)
    }

    @Test func theRegisterSavesNoColumnsPerAccountAndIgnoresOldOnes() throws {
        let data = try JSONEncoder().encode(SavedRegisterViewState(RegisterAccountViewState()))
        let saved = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(saved["columns"] == nil)
        #expect(saved["schedulerColumns"] != nil)

        let old = try JSONDecoder().decode(
            SavedRegisterViewState.self,
            from: Data(
                """
                {"sortColumn": "date", "sortAscending": false, "sortVersion": 2, "isSchedulerVisible": false,
                 "columns": {"memo": {"visible": false, "width": 300}}}
                """.utf8))
        #expect(RegisterAccountViewState(saved: old).sort == RegisterSortOrder.default)
    }

    @Test func reconciliationKeepsTheStateToReturnTo() throws {
        let storage = MemorySettingsStorage()
        let register = launch(storage).register
        register.grid.headerClicked(.payee)
        register.reconciliation.reconcileClicked()
        let form = try #require(register.reconciliation.statementForm)
        form.amountText = "1111"
        register.reconciliation.begin(form)
        #expect(launch(storage).register.sortOrder == RegisterSortOrder(column: .payee, ascending: true))
    }

    @Test func groupCollapseStatesSurviveARelaunchPerBudget() {
        let storage = MemorySettingsStorage()
        let sidebar = launch(storage, selection: .allAccounts).sidebar
        sidebar.setGroup(.budgetAccounts, expanded: false)
        sidebar.setGroup(.offBudgetAccounts, expanded: false)
        #expect(
            launch(storage, selection: .allAccounts).sidebar.collapsedGroups == [.budgetAccounts, .offBudgetAccounts])
        var other = fixture.budget
        other.budgetName = "Other"
        #expect(launch(storage, budget: other, selection: .allAccounts).sidebar.collapsedGroups.isEmpty)
    }
}
