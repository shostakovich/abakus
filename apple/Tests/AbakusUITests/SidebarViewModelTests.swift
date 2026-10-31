import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

private let today = DateWithoutTime(year: 2026, month: 10, day: 23)

@MainActor
private func makeSidebar(
    selection: SidebarSelection? = nil, defaults: (any SettingsStorage)? = nil,
    budget: Budget = DemoBudget.make(today: today)
) -> SidebarViewModel {
    let navigation = NavigationState(selection: selection ?? AppModel.defaultSelection(in: budget))
    return SidebarViewModel(
        store: SpyBudgetStore(budget: budget, today: today), navigation: navigation, defaults: defaults,
        budgetSettings: nil)
}

@MainActor
private func makeApp(defaults: (any SettingsStorage)? = nil, budget: Budget = DemoBudget.make(today: today))
    -> AppModel
{
    AppModel(store: BudgetStore(budget: budget), defaults: defaults)
}

@MainActor
@Suite struct SidebarViewModelTests {
    @Test func showsTheGroupsWithTheirAccounts() {
        let panels = makeSidebar().groupPanels
        #expect(panels.map(\.title) == ["Budgetkonten", "Trackingkonten", "Geschlossene Konten"])
        #expect(panels[0].rows.map(\.name) == ["Girokonto", "Tagesgeld", "Kreditkarte", "Bargeld"])
        #expect(panels[1].rows.map(\.name) == ["Depot", "Bausparvertrag"])
        #expect(!panels[0].isCollapsed)
        #expect(panels[2].isCollapsed)
    }

    @Test func emptyOffBudgetAndClosedGroupsAreHidden() throws {
        var budget = Budget(budgetName: "Empty")
        try budget.apply(
            .addAccount(NewAccount(name: "Giro", kind: .checking, startingBalance: 5, startDate: today)))
        let panels = makeSidebar(budget: budget).groupPanels
        #expect(panels.map(\.group) == [.budgetAccounts])
    }

    @Test func emptyBudgetAccountsGroupStartsCollapsed() {
        let sidebar = makeSidebar(budget: Budget(budgetName: "Empty"))
        #expect(sidebar.groupPanels.map(\.isCollapsed) == [true])
    }

    @Test func balancesUseTheBudgetLocale() {
        let sidebar = makeSidebar()
        let kreditkarte = sidebar.groupPanels[0].rows[2]
        #expect(kreditkarte.isNegative)
        #expect(kreditkarte.balanceText.hasPrefix("-"))
        #expect(!kreditkarte.balanceText.hasSuffix("€"))
        #expect(sidebar.groupPanels[0].totalText.hasSuffix("€"))
        #expect(sidebar.allAccountsBalanceText.hasSuffix("€"))
        #expect(kreditkarte.tooltip.hasPrefix("Kreditkarte    -"))
    }

    @Test func badgesCountTransactionsThatNeedAttention() {
        let rows = makeSidebar().groupPanels[0].rows
        #expect(rows[0].badge == SidebarBadge(count: 1, level: .needsCategory))
        #expect(rows[2].badge == SidebarBadge(count: 1, level: .forReview))
        #expect(rows[1].badge == nil)
    }

    @Test func collapsedGroupHeaderShowsTheAggregatedBadge() {
        let sidebar = makeSidebar()
        #expect(sidebar.groupPanels[0].headerBadge == nil)
        sidebar.setGroup(.budgetAccounts, expanded: false)
        #expect(sidebar.groupPanels[0].isCollapsed)
        #expect(sidebar.groupPanels[0].headerBadge == SidebarBadge(count: 2, level: .needsCategory))
    }

    @Test func selectingAClosedAccountExpandsItsGroup() {
        let budget = DemoBudget.make(today: today)
        let closed = budget.account(named: "Altes Sparbuch")!
        let sidebar = makeSidebar(budget: budget)
        sidebar.select(.account(closed.id))
        #expect(sidebar.navigation.selection == .account(closed.id))
        #expect(sidebar.isSelected(.account(closed.id)))
        #expect(!sidebar.groupPanels[2].isCollapsed)
    }

    @Test func sectionsSelectWithoutTouchingGroups() {
        let sidebar = makeSidebar()
        let groups = sidebar.collapsedGroups
        sidebar.select(.budget)
        #expect(sidebar.navigation.selection == .budget)
        #expect(sidebar.collapsedGroups == groups)
    }

    @Test func theNarrowSidebarShortensItsTitles() {
        let sidebar = makeSidebar()
        #expect(sidebar.isFullView)
        #expect(sidebar.toggleCommandTitle == "Seitenleiste einklappen")
        sidebar.toggleSidebar()
        #expect(!sidebar.isFullView)
        #expect(sidebar.sectionTitles.allAccounts == "Konten")
        #expect(sidebar.title(of: .offBudgetAccounts) == "Tracking")
        #expect(sidebar.addAccountTitle == "Hinzufügen")
        #expect(sidebar.toggleTooltip == "Klicken, um die Seitenleiste auszuklappen")
        #expect(sidebar.toggleCommandTitle == "Seitenleiste ausklappen")
        sidebar.toggleSidebar()
        #expect(sidebar.addAccountTitle == "Konto hinzufügen")
    }

    @Test func expandingAGroupThatIsAlreadyOpenChangesNothing() {
        let sidebar = makeSidebar()
        sidebar.setGroup(.budgetAccounts, expanded: true)
        #expect(!sidebar.collapsedGroups.contains(.budgetAccounts))
        sidebar.setGroup(.budgetAccounts, expanded: false)
        #expect(sidebar.collapsedGroups.contains(.budgetAccounts))
        sidebar.setGroup(.budgetAccounts, expanded: false)
        #expect(sidebar.collapsedGroups.contains(.budgetAccounts))
    }

    @Test func sidebarStatePersistsAsTabState() {
        let defaults = MemorySettingsStorage()
        makeSidebar(defaults: defaults).toggleSidebar()
        #expect(defaults.string(forKey: SidebarViewModel.tabStateKey) == "tabStateCollapse")
        let restored = makeSidebar(defaults: defaults)
        #expect(!restored.isFullView)
    }

    @Test func everySelectionChangeExpandsTheAccountsGroup() {
        let budget = DemoBudget.make(today: today)
        let depot = budget.account(named: "Depot")!
        let sidebar = makeSidebar(budget: budget)
        sidebar.setGroup(.offBudgetAccounts, expanded: false)
        sidebar.navigation.selection = .account(depot.id)
        #expect(!sidebar.collapsedGroups.contains(.offBudgetAccounts))
    }
}

@MainActor
@Suite struct AppModelTests {
    @Test func startsWithTheFirstBudgetAccountSelected() {
        let app = makeApp()
        let girokonto = app.store.budget.account(named: "Girokonto")!
        #expect(app.navigation.selection == .account(girokonto.id))
        #expect(app.sidebar.isSelected(.account(girokonto.id)))
        #expect(makeApp(budget: Budget(budgetName: "Empty")).navigation.selection == .allAccounts)
    }

    @Test func windowTitleNamesAppAndBudget() {
        #expect(makeApp().windowTitle == "Abakus - Demo-Budget")
        #expect(makeApp(budget: Budget(budgetName: "")).windowTitle == "Abakus - Unbenanntes Budget")
    }

    @Test func selectionTitleNamesTheAccount() {
        let app = makeApp()
        #expect(app.selectionTitle == "Girokonto")
        app.sidebar.select(.allAccounts)
        #expect(app.selectionTitle == "Alle Konten")
        app.sidebar.select(.budget)
        #expect(app.selectionTitle == "Budget")
    }

    @Test func collapsedGroupsAreKeptPerBudget() {
        let defaults = MemorySettingsStorage()
        makeApp(defaults: defaults).sidebar.setGroup(.offBudgetAccounts, expanded: false)
        #expect(makeApp(defaults: defaults).sidebar.collapsedGroups.contains(.offBudgetAccounts))
        let other = makeApp(defaults: defaults, budget: DemoBudget.make(today: today).renamed("Other"))
        #expect(!other.sidebar.collapsedGroups.contains(.offBudgetAccounts))
    }
}

extension Budget {
    fileprivate func renamed(_ name: String) -> Budget {
        var budget = self
        budget.budgetName = name
        return budget
    }
}

@Suite struct SidebarBadgeTests {
    @Test(arguments: [(0, ""), (7, "7"), (42, "42"), (100, "99+")])
    func text(count: Int, expected: String) {
        #expect(SidebarBadge(count: count, level: .error).text == expected)
    }

    @Test(arguments: [(ErrorLevel.error, true), (.needsCategory, true), (.forReview, false), (.none, false)])
    func onlyWarningsAreColoured(level: ErrorLevel, isWarning: Bool) {
        #expect(SidebarBadge(count: 1, level: level).isWarning == isWarning)
    }

    @Test func tooltipUsesSingularAndPlural() {
        #expect(SidebarBadge(count: 1, level: .error).tooltip.hasPrefix("1 Buchung braucht deine Aufmerksamkeit."))
        #expect(SidebarBadge(count: 4, level: .error).tooltip.hasPrefix("4 Buchungen brauchen deine Aufmerksamkeit."))
    }

    @Test func aBudgetNotSignedInShowsTheCrossedOutCloud() {
        let status = CloudSyncStatus(.notSignedIn, pendingChanges: 0, lastSync: nil)
        #expect(status.symbolName == "icloud.slash")
        #expect(status.tooltip == "Das Budget liegt nur auf diesem Mac und wird nicht synchronisiert.")
    }

    @Test func theCloudNamesTheLastSyncTheWaitingChangesOrTheError() {
        let last = Date(timeIntervalSince1970: 1_793_440_800)
        let inStep = CloudSyncStatus(.inStep, pendingChanges: 0, lastSync: last)
        #expect(inStep.symbolName == "checkmark.icloud")
        #expect(inStep.tooltip.hasPrefix("Das Budget ist mit Abakus abgeglichen. Zuletzt synchronisiert: "))
        let offline = CloudSyncStatus(.offline, pendingChanges: 3, lastSync: nil)
        #expect(offline.symbolName == "arrow.clockwise.icloud")
        #expect(
            offline.tooltip == "Abakus ist gerade nicht erreichbar. 3 Änderungen warten darauf, gesendet zu werden.")
        let clock = CloudSyncStatus(.error(.clockAhead("Die Uhr geht vor.")), pendingChanges: 1, lastSync: last)
        #expect(clock.symbolName == "exclamationmark.icloud")
        #expect(clock.tooltip == "Beim Synchronisieren ist ein Fehler aufgetreten: Die Uhr geht vor.")
    }
}

final class MemorySettingsStorage: SettingsStorage {
    private var values: [String: Any] = [:]

    func string(forKey defaultName: String) -> String? { values[defaultName] as? String }

    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}
