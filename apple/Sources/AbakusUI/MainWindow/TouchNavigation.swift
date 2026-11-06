import AbakusCore
import Foundation
import Observation

public enum AppTab: String, Hashable, Sendable {
    case budget, accounts, settings
}

public enum PayeeRoute: Hashable, Sendable {
    case payees, payee, category
}

/// The iPhone's and the iPad's tabs: the budget, the account list with a register pushed onto it, and the settings.
@MainActor
@Observable
public final class TouchNavigation {
    static let lastTabKey = "lastTouchTab"
    static let lastRegisterKey = "lastTouchRegister"

    public private(set) var tab: AppTab {
        didSet {
            settings?.set(tab.rawValue, forKey: Self.lastTabKey)
            if oldValue == .settings && tab != .settings { showSettings([]) }
        }
    }
    public private(set) var accountPath: [SidebarSelection] {
        didSet { settings?.set(accountPath.last.map(Self.key) ?? "", forKey: Self.lastRegisterKey) }
    }
    private var payeePages: [PayeeRoute] = []
    /// The payees closed elsewhere take their pages with them; payees opened later are a sheet again.
    private var pagedPayees: PayeeSettingsModel?
    private var picksPayees = false
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let settings: BudgetSettings?

    public init(app: AppModel) {
        self.app = app
        settings = app.settings
        let register = settings?.string(forKey: Self.lastRegisterKey).flatMap { Self.selection($0, in: app.store) }
        let tab = settings?.string(forKey: Self.lastTabKey).flatMap(AppTab.init) ?? .budget
        self.tab = tab
        accountPath = register.map { [$0] } ?? []
        if tab == .budget {
            app.navigation.selection = .budget
        } else if let register {
            app.navigation.selection = register
        }
        app.navigation.onSelectionRequest { [weak self] in self?.show($0) }
    }

    public func select(_ tab: AppTab) {
        let leavesBudget = self.tab == .budget && tab != .budget
        switch tab {
        case .budget: app.goToBudget()
        case .accounts: if let register = accountPath.last { app.navigation.selection = register }
        case .settings: break
        }
        // Selecting a register has left the budget already.
        if leavesBudget && app.navigation.selection == .budget { app.budget.leave() }
        self.tab = tab
    }

    public func showAccounts(_ path: [SidebarSelection]) {
        let leavesRegister = path.isEmpty && !accountPath.isEmpty
        accountPath = path
        if let register = path.last {
            app.navigation.selection = register
        } else if leavesRegister {
            app.navigation.endVisit()
        }
    }

    public var settingsPath: [PayeeRoute] {
        guard let payees = app.payeeSettings, payees === pagedPayees else { return [] }
        return payeePages
    }

    public var isPickingPayees: Bool {
        get { picksPayees && !settingsPath.isEmpty }
        set { picksPayees = newValue }
    }

    /// The payees open and close with their page in one step, or they would show as a sheet in between.
    public func showSettings(_ path: [PayeeRoute]) {
        let wasShown = settingsPath.contains(.payees)
        let shows = path.contains(.payees)
        if wasShown && !shows {
            picksPayees = false
            app.payeeSettings?.close()
        }
        payeePages = path
        guard shows && !wasShown else { return }
        app.openPayeeSettings(payeeName: nil)
        pagedPayees = app.payeeSettings
        app.payeeSettings?.selectionChanged(to: [])
    }

    public var showsPayeeSheet: Bool { app.payeeSettings != nil && settingsPath.isEmpty }

    /// A sheet is up: the dock fades back, dialogs show over the sheet, and ⌘B, ⌘T, ⌘, and ⌘N wait.
    public var showsSheet: Bool { app.showsScreenSheet || app.accounts.isPresenting || showsPayeeSheet }

    /// "Auswählen" and the reconciliation put their bars in the dock's place.
    public var barTakesDocksPlace: Bool {
        switch tab {
        case .accounts:
            !accountPath.isEmpty && app.showsRegister && (app.register.isPicking || app.register.isReconciling)
        case .settings: isPickingPayees
        case .budget: false
        }
    }

    /// Only a register on screen holds its own account back; elsewhere any account that takes entries will do.
    public var canAddTransaction: Bool {
        let showsRegister = tab == .accounts && !accountPath.isEmpty
        return showsRegister
            ? app.register.canAddTransactions : app.store.budget.accounts.contains(where: \.takesEntries)
    }

    /// The payees as a page block the register like their sheet, so a new transaction closes them first.
    public func addTransactionClicked() {
        showSettings([])
        app.payeeSettings?.close()
        app.register.addTransactionClicked()
    }

    public func goToBudget() {
        select(.budget)
    }

    public func goToSettings() {
        select(.settings)
    }

    public func goToAccounts() {
        app.goToAccounts()
        show(app.navigation.selection)
    }

    private func show(_ selection: SidebarSelection) {
        guard selection.showsRegister else {
            tab = .budget
            return
        }
        tab = .accounts
        if accountPath != [selection] { accountPath = [selection] }
    }

    private static func key(_ selection: SidebarSelection) -> String {
        switch selection {
        case .account(let id): id
        case .allAccounts: EntityID.allAccounts
        case .budget: ""
        }
    }

    private static func selection(_ key: String, in store: BudgetStore) -> SidebarSelection? {
        if key == EntityID.allAccounts { return .allAccounts }
        return store.budget.account(withId: key) == nil ? nil : .account(key)
    }
}
