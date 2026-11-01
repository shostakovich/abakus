import AbakusCore
import Foundation
import Observation

public enum SidebarSelection: Hashable, Sendable {
    case budget
    case allAccounts
    case account(String)

    var showsRegister: Bool {
        switch self {
        case .allAccounts, .account: true
        case .budget: false
        }
    }
}

public struct SidebarRevealRequest: Equatable, Sendable {
    let selection: SidebarSelection
    let token: Int
}

@MainActor
@Observable
public final class NavigationState {
    public var selection: SidebarSelection {
        didSet {
            guard selection != oldValue else { return }
            visit += 1
            for observer in observers { observer(oldValue, selection) }
        }
    }
    /// Counts switches between sidebar entries; state that lasts for one visit (the selection) keys on it.
    public private(set) var visit = 0
    @ObservationIgnored private var observers: [(SidebarSelection, SidebarSelection) -> Void] = []

    func onSelectionChange(_ observer: @escaping (SidebarSelection, SidebarSelection) -> Void) {
        observers.append(observer)
    }

    public init(selection: SidebarSelection = .allAccounts) {
        self.selection = selection
    }
}

public struct SidebarBadge: Hashable, Sendable {
    public var count: Int
    public var level: ErrorLevel

    public init(count: Int, level: ErrorLevel) {
        self.count = count
        self.level = level
    }

    public var text: String {
        switch count {
        case 0: ""
        case 1...99: String(count)
        default: "99+"
        }
    }

    public var isWarning: Bool { level == .error || level == .needsCategory }

    public var tooltip: String {
        let detail = "\nKlicke auf das Konto für Details."
        return count == 1
            ? "1 Buchung braucht deine Aufmerksamkeit." + detail
            : "\(count) Buchungen brauchen deine Aufmerksamkeit." + detail
    }
}

public struct SidebarAccountRow: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var balance: Decimal
    public var balanceText: String
    public var tooltip: String
    public var badge: SidebarBadge?
}

public struct SidebarGroupPanel: Identifiable, Hashable, Sendable {
    public var group: SidebarGroup
    public var title: String
    public var total: Decimal
    public var totalText: String
    public var rows: [SidebarAccountRow]
    public var isCollapsed: Bool
    public var headerBadge: SidebarBadge?

    public var id: SidebarGroup { group }
}

@MainActor
@Observable
public final class SidebarViewModel {
    public static let tabStateKey = "TabState"

    public let store: any BudgetStoring
    public let navigation: NavigationState
    public private(set) var isFullView: Bool
    public private(set) var collapsedGroups: Set<SidebarGroup> {
        didSet { saveGroupStates(changedFrom: oldValue) }
    }
    public var sync: BudgetSync?
    public private(set) var revealRequest: SidebarRevealRequest?
    @ObservationIgnored private let defaults: (any SettingsStorage)?
    @ObservationIgnored private let budgetSettings: BudgetSettings?

    /// Closed accounts stay out of the sidebar, as on the web.
    static let shownGroups: [SidebarGroup] = [.budgetAccounts, .offBudgetAccounts]

    static let savedGroupStates: [SidebarGroup: String] = [
        .budgetAccounts: "onBudgetAccountContainerState", .offBudgetAccounts: "offBudgetAccountContainerState",
    ]

    /// nil keeps the sidebar state in memory only.
    init(
        store: any BudgetStoring, navigation: NavigationState, defaults: (any SettingsStorage)?,
        budgetSettings settings: BudgetSettings?
    ) {
        self.store = store
        self.navigation = navigation
        self.defaults = defaults
        budgetSettings = settings
        isFullView = defaults?.string(forKey: Self.tabStateKey) != "tabStateCollapse"
        var collapsed: Set<SidebarGroup> = []
        for (group, key) in Self.savedGroupStates where settings?.string(forKey: key) == "collapsed" {
            collapsed.insert(group)
        }
        if store.budget.accounts(in: .budgetAccounts).isEmpty { collapsed.insert(.budgetAccounts) }
        collapsedGroups = collapsed
        expandGroup(containing: navigation.selection)
        navigation.onSelectionChange { [weak self] in self?.expandGroup(containing: $1) }
    }

    private var formatter: BudgetFormatter { BudgetFormatter(metaData: store.budget.budgetMetaData) }

    public var cloudStatus: CloudSyncStatus {
        sync.map { CloudSyncStatus($0.status, pendingChanges: $0.pendingChanges, lastSync: $0.lastSync) } ?? .local
    }

    public var sectionTitles: (budget: String, allAccounts: String) {
        ("Budget", isFullView ? Account.allAccountsName : "Konten")
    }

    public var addAccountTitle: String { isFullView ? "Konto hinzufügen" : "Hinzufügen" }
    public var toggleTooltip: String {
        isFullView ? "Klicken, um die Seitenleiste einzuklappen" : "Klicken, um die Seitenleiste auszuklappen"
    }
    public var toggleCommandTitle: String { isFullView ? "Seitenleiste einklappen" : "Seitenleiste ausklappen" }

    public var groupPanels: [SidebarGroupPanel] {
        let budget = store.budget
        let balances = budget.workingBalances()
        let formatter = formatter
        return Self.shownGroups.compactMap { group in
            let accounts = budget.accounts(in: group)
            if group != .budgetAccounts && accounts.isEmpty { return nil }
            let rows = accounts.map { account in
                let balance = balances[account.id] ?? 0
                let summary = budget.errorSummary(forAccount: account.id)
                let tooltip = account.name + "    " + formatter.currency(balance)
                return SidebarAccountRow(
                    id: account.id, name: account.name, balance: balance,
                    balanceText: formatter.currency(balance), tooltip: tooltip,
                    badge: summary.count > 0 ? SidebarBadge(count: summary.count, level: summary.maxLevel) : nil)
            }
            let total = Amount.sum(rows.map(\.balance))
            let isCollapsed = collapsedGroups.contains(group)
            let summary = budget.errorSummary(for: group)
            let showsHeaderBadge = isCollapsed && isFullView && !rows.isEmpty && summary.count > 0
            return SidebarGroupPanel(
                group: group, title: title(of: group), total: total, totalText: formatter.currency(total),
                rows: rows, isCollapsed: isCollapsed,
                headerBadge: showsHeaderBadge ? SidebarBadge(count: summary.count, level: summary.maxLevel) : nil)
        }
    }

    public func title(of group: SidebarGroup) -> String {
        switch (group, isFullView) {
        case (_, true): group.title
        case (.budgetAccounts, false): "Budget"
        case (.offBudgetAccounts, false): "Tracking"
        case (.closedAccounts, false): "Geschlossen"
        }
    }

    public func isSelected(_ selection: SidebarSelection) -> Bool {
        navigation.selection == selection
    }

    public func select(_ selection: SidebarSelection) {
        navigation.selection = selection
    }

    public func setGroup(_ group: SidebarGroup, expanded: Bool) {
        if expanded {
            collapsedGroups.remove(group)
        } else {
            collapsedGroups.insert(group)
        }
    }

    public func moveAccount(in group: SidebarGroup, from source: IndexSet, to destination: Int) {
        let accounts = store.budget.accounts(in: group)
        guard source.count == 1, let index = source.first, accounts.indices.contains(index) else { return }
        try? store.perform(.moveAccount(accountId: accounts[index].id, index: destination))
    }

    public func toggleSidebar() {
        isFullView.toggle()
        defaults?.set(isFullView ? "tabStateExpand" : "tabStateCollapse", forKey: Self.tabStateKey)
    }

    private func saveGroupStates(changedFrom old: Set<SidebarGroup>) {
        guard let budgetSettings else { return }
        for (group, key) in Self.savedGroupStates where old.contains(group) != collapsedGroups.contains(group) {
            budgetSettings.set(collapsedGroups.contains(group) ? "collapsed" : "normal", forKey: key)
        }
    }

    /// Expands the row's group and asks the list to scroll the row into view, so a popover can point at it.
    func reveal(_ selection: SidebarSelection) {
        expandGroup(containing: selection)
        revealRequest = SidebarRevealRequest(selection: selection, token: (revealRequest?.token ?? 0) + 1)
    }

    private func expandGroup(containing selection: SidebarSelection) {
        guard case .account(let id) = selection, let account = store.budget.account(withId: id) else { return }
        for group in Self.shownGroups where group.contains(account) {
            collapsedGroups.remove(group)
        }
    }
}
