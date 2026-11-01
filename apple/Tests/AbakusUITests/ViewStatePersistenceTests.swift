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
        register.toggleColumnVisibility(.runningBalance)
        register.grid.headerClicked(.payee)
        register.setShowingReconciled(false)
        register.scheduledToggleClicked()
        register.scheduler.setHeight(240)
        register.scheduler.grid.headerClicked(.payee)
        register.scheduler.toggleColumnVisibility(.memo)
        register.search.timeframePresetClicked(.thisYear)
        register.search.text = "Shop"
        register.search.commit()

        let restored = launch(storage).register
        #expect(restored.columnSettings[.runningBalance]?.visible == true)
        #expect(restored.sortOrder == RegisterSortOrder(column: .payee, ascending: true))
        #expect(!restored.isShowingReconciled)
        #expect(restored.isSchedulerVisible)
        #expect(restored.scheduler.savedHeight == 240)
        #expect(restored.scheduler.sortOrder == RegisterSortOrder(column: .payee, ascending: true))
        #expect(restored.scheduler.columnSettings[.memo]?.visible == false)
        #expect(restored.search.dateSelectorTitle == "Dieses Jahr")
        #expect(restored.search.text.isEmpty)
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
