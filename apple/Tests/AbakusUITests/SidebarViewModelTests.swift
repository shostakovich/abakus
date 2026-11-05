import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

private let today = DateWithoutTime(year: 2026, month: 10, day: 23)

private let sidebarBudget: Budget = {
    var budget = Budget(budgetName: "Sidebar")
    let accounts: [(String, AccountKind, Decimal)] = [
        ("Girokonto", .checking, 2450), ("Tagesgeld", .savings, 5000), ("Kreditkarte", .checking, -1240),
        ("Bargeld", .cash, 80), ("Depot", .tracking, 12500), ("Bausparvertrag", .tracking, 4200),
        ("Altes Sparbuch", .savings, 0),
    ]
    for (name, kind, balance) in accounts {
        try! budget.apply(
            .addAccount(NewAccount(name: name, kind: kind, startingBalance: balance, startDate: today)))
    }
    let giro = budget.account(named: "Girokonto")!.id
    let karte = budget.account(named: "Kreditkarte")!.id
    let groceries = budget.categoryGroups.first { !$0.isInternal }!.categories[0].id
    try! budget.apply(.addTransaction(Transaction(accountId: giro, date: today, amount: -12)))
    let scheduled = Transaction(
        accountId: karte, date: today, categoryId: groceries, amount: -11, approved: false, source: .scheduled)
    try! budget.apply(.addTransaction(scheduled))
    var closed = budget.account(named: "Altes Sparbuch")!
    closed.closed = true
    try! budget.apply(.editAccount(closed))
    return budget
}()

@MainActor
private func makeSidebar(
    selection: SidebarSelection? = nil, defaults: (any SettingsStorage)? = nil, budget: Budget = sidebarBudget
) -> SidebarViewModel {
    let navigation = NavigationState(selection: selection ?? AppModel.defaultSelection(in: budget))
    return SidebarViewModel(
        store: SpyBudgetStore(budget: budget, today: today), navigation: navigation, defaults: defaults,
        budgetSettings: nil)
}

@MainActor
private func makeApp(defaults: (any SettingsStorage)? = nil, budget: Budget = sidebarBudget)
    -> AppModel
{
    AppModel(store: BudgetStore(budget: budget), defaults: defaults)
}

@MainActor
private func makeOrderedSidebar() throws -> (sidebar: SidebarViewModel, store: SpyBudgetStore) {
    var budget = Budget(budgetName: "Sidebar")
    for (name, kind) in [("Girokonto", AccountKind.checking), ("Sparkonto", .savings), ("Bargeld", .cash)] {
        try budget.apply(.addAccount(NewAccount(name: name, kind: kind, startingBalance: 0, startDate: today)))
    }
    let store = SpyBudgetStore(budget: budget, today: today, appliesCommands: true)
    let sidebar = SidebarViewModel(
        store: store, navigation: NavigationState(selection: .budget), defaults: nil, budgetSettings: nil)
    return (sidebar, store)
}

@MainActor
@Suite struct SidebarViewModelTests {
    @Test func showsTheGroupsWithTheirAccounts() {
        let panels = makeSidebar().groupPanels
        #expect(panels.map(\.title) == ["Budgetkonten", "Trackingkonten"])
        #expect(panels[0].rows.map(\.name) == ["Girokonto", "Tagesgeld", "Kreditkarte", "Bargeld"])
        #expect(panels[1].rows.map(\.name) == ["Depot", "Bausparvertrag"])
        #expect(!panels[0].isCollapsed)
    }

    @Test func emptyOffBudgetGroupIsHidden() throws {
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
        #expect(kreditkarte.balance < 0)
        #expect(kreditkarte.balanceText.hasPrefix("−"))
        #expect(kreditkarte.balanceText.hasSuffix("€"))
        #expect(sidebar.groupPanels[0].totalText.hasSuffix("€"))
        #expect(kreditkarte.tooltip.hasPrefix("Kreditkarte    −"))
    }

    @Test func badgesCountTransactionsThatNeedAttention() {
        let rows = makeSidebar().groupPanels[0].rows
        #expect(rows[0].badge == SidebarBadge(count: 1, level: .needsCategory))
        #expect(rows[2].badge == SidebarBadge(count: 1, level: .forReview))
        #expect(rows[1].badge == nil)
    }

    @Test func voiceOverReadsTheBalanceAndWhatWaits() {
        let rows = makeSidebar().groupPanels[0].rows
        #expect(rows[0].accessibilityValue == rows[0].balanceText + ", 1 Buchung braucht deine Aufmerksamkeit.")
        #expect(rows[1].accessibilityValue == rows[1].balanceText)
    }

    @Test func rowsShowTheEmojiOfTheirNameElseTheMotifOfTheirKind() throws {
        var budget = Budget(budgetName: "Motifs")
        let accounts: [(String, AccountKind)] = [
            ("💶 Giro", .checking), ("Sparkonto", .savings), ("Bargeld", .cash), ("Giro", .checking),
            ("Depot", .tracking),
        ]
        for (name, kind) in accounts {
            try budget.apply(.addAccount(NewAccount(name: name, kind: kind, startingBalance: 0, startDate: today)))
        }
        let rows = makeSidebar(budget: budget).groupPanels.flatMap(\.rows)
        #expect(rows.map(\.emoji) == ["💶", nil, nil, nil, nil])
        #expect(rows.map(\.label) == ["Giro", "Sparkonto", "Bargeld", "Giro", "Depot"])
        #expect(rows.map(\.motif) == [.landmark, .piggyBank, .banknote, .landmark, .trendingUp])
    }

    @Test func theSharedExpensesAccountShowsTheReceipt() {
        let account = Account(name: "Gemeinsam", kind: .checking, sharedExpenses: true)
        #expect(AccountMotif(account) == .receipt)
    }

    @Test func collapsedGroupHeaderShowsTheAggregatedBadge() {
        let sidebar = makeSidebar()
        #expect(sidebar.groupPanels[0].headerBadge == nil)
        sidebar.setGroup(.budgetAccounts, expanded: false)
        #expect(sidebar.groupPanels[0].isCollapsed)
        #expect(sidebar.groupPanels[0].headerBadge == SidebarBadge(count: 2, level: .needsCategory))
    }

    @Test func closedAccountsStayOutOfTheSidebar() {
        let budget = sidebarBudget
        let closed = budget.account(named: "Altes Sparbuch")!
        let sidebar = makeSidebar(budget: budget)
        #expect(!sidebar.groupPanels.flatMap(\.rows).contains { $0.id == closed.id })
        let groups = sidebar.collapsedGroups
        sidebar.select(.account(closed.id))
        #expect(sidebar.navigation.selection == .account(closed.id))
        #expect(sidebar.collapsedGroups == groups)
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

    @Test func draggingAnAccountReordersItsGroup() throws {
        let (sidebar, store) = try makeOrderedSidebar()
        let bargeld = try #require(store.budget.account(named: "Bargeld"))
        sidebar.moveAccount(in: .budgetAccounts, from: IndexSet(integer: 2), to: 0)
        #expect(store.commands == [.moveAccount(accountId: bargeld.id, index: 0)])
        #expect(sidebar.groupPanels[0].rows.map(\.name) == ["Bargeld", "Girokonto", "Sparkonto"])
    }

    @Test func aChangedPositionReordersTheSidebar() throws {
        let (sidebar, store) = try makeOrderedSidebar()
        var girokonto = try #require(store.budget.account(named: "Girokonto"))
        girokonto.position = 5
        store.budget = try store.budget.applying(.editAccount(girokonto))
        #expect(sidebar.groupPanels[0].rows.map(\.name) == ["Sparkonto", "Bargeld", "Girokonto"])
    }

    @Test func everySelectionChangeExpandsTheAccountsGroup() {
        let budget = sidebarBudget
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
        let other = makeApp(defaults: defaults, budget: sidebarBudget.renamed("Other"))
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

    @Test(arguments: [
        (ErrorLevel.needsCategory, SidebarBadge.Kind.needsCategory), (.forReview, .forReview), (.error, .error),
    ])
    func theKindFollowsTheLevel(level: ErrorLevel, kind: SidebarBadge.Kind) {
        #expect(SidebarBadge(count: 2, level: level).kind == kind)
    }

    @Test func theSummaryNamesTheCountWithoutTheClickHint() {
        #expect(SidebarBadge(count: 1, level: .error).summary == "1 Buchung braucht deine Aufmerksamkeit.")
        #expect(SidebarBadge(count: 3, level: .forReview).summary == "3 Buchungen brauchen deine Aufmerksamkeit.")
    }

    @Test func onlyAnErrorOrARemoteSignOutNeedsAttention() {
        let attention: [SyncStatus] = [.signedOutRemotely, .error(.clockAhead("Die Uhr geht vor."))]
        let quiet: [SyncStatus] = [.notSignedIn, .inStep, .offline]
        for status in attention {
            #expect(CloudSyncStatus(status, pendingChanges: 0, lastSync: nil, on: .iPhone).needsAttention)
        }
        for status in quiet {
            #expect(!CloudSyncStatus(status, pendingChanges: 2, lastSync: nil, on: .iPhone).needsAttention)
        }
    }

    @Test func tooltipUsesSingularAndPlural() {
        #expect(SidebarBadge(count: 1, level: .error).tooltip.hasPrefix("1 Buchung braucht deine Aufmerksamkeit."))
        #expect(SidebarBadge(count: 4, level: .error).tooltip.hasPrefix("4 Buchungen brauchen deine Aufmerksamkeit."))
    }

    @Test func aBudgetNotSignedInShowsTheCrossedOutCloud() {
        let status = CloudSyncStatus(.notSignedIn, pendingChanges: 0, lastSync: nil, on: .mac)
        #expect(status.symbolName == "icloud.slash")
        #expect(status.tooltip == "Das Budget liegt nur auf diesem Mac und wird nicht synchronisiert.")
    }

    @Test func theCloudNamesTheDeviceItRunsOn() {
        let local = CloudSyncStatus(.notSignedIn, pendingChanges: 0, lastSync: nil, on: .iPhone)
        #expect(local.tooltip == "Das Budget liegt nur auf diesem iPhone und wird nicht synchronisiert.")
        let signedOut = CloudSyncStatus(.signedOutRemotely, pendingChanges: 0, lastSync: nil, on: .iPad)
        #expect(signedOut.tooltip == "Dieses iPad wurde in Abakus abgemeldet. Melde es in den Einstellungen wieder an.")
    }

    @Test func theCloudNamesTheLastSyncTheWaitingChangesOrTheError() {
        let last = Date(timeIntervalSince1970: 1_793_440_800)
        let inStep = CloudSyncStatus(.inStep, pendingChanges: 0, lastSync: last, on: .mac)
        #expect(inStep.symbolName == "checkmark.icloud")
        #expect(inStep.tooltip.hasPrefix("Das Budget ist mit Abakus abgeglichen. Zuletzt synchronisiert: "))
        let offline = CloudSyncStatus(.offline, pendingChanges: 3, lastSync: nil, on: .mac)
        #expect(offline.symbolName == "arrow.clockwise.icloud")
        #expect(
            offline.tooltip == "Abakus ist gerade nicht erreichbar. 3 Änderungen warten darauf, gesendet zu werden.")
        let clock = CloudSyncStatus(
            .error(.clockAhead("Die Uhr geht vor.")), pendingChanges: 1, lastSync: last, on: .mac)
        #expect(clock.symbolName == "exclamationmark.icloud")
        #expect(clock.tooltip == "Beim Synchronisieren ist ein Fehler aufgetreten: Die Uhr geht vor.")
    }
}

final class MemorySettingsStorage: SettingsStorage {
    private var values: [String: Any] = [:]

    func string(forKey defaultName: String) -> String? { values[defaultName] as? String }

    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}
