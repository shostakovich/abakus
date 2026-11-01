import AbakusCore
import Foundation
import Observation

enum ClockChoice: Hashable, Sendable {
    case ignore, enterDue
}

enum SaveErrorChoice: Hashable, Sendable {
    case retry, close
}

@MainActor
@Observable
public final class AppModel {
    public let store: BudgetStore
    public let navigation: NavigationState
    public let sidebar: SidebarViewModel
    public let register: RegisterViewModel
    public let budget: BudgetViewModel
    public let accounts: AccountsController
    public let dialogs = DialogStack()
    public internal(set) var payeeSettings: PayeeSettingsModel?
    public let sync: BudgetSync?
    public let syncSettings: SyncSettingsModel?
    @ObservationIgnored var lastUsedPayeeId: String?
    @ObservationIgnored let preferences: (any SettingsStorage)?
    private var acknowledgedSaveFailures = 0
    @ObservationIgnored private let saveErrorId = UUID()
    @ObservationIgnored private var lastDate: DateWithoutTime
    @ObservationIgnored var lastRegisterSelection: SidebarSelection?

    public init(
        store: BudgetStore, selection: SidebarSelection? = nil,
        defaults: (any SettingsStorage)? = UserDefaults.standard, sync: BudgetSync? = nil
    ) {
        self.store = store
        self.sync = sync
        syncSettings = sync.map { SyncSettingsModel(sync: $0) }
        let settings = defaults.map { BudgetSettings(storage: $0, store: store) }
        let budgetSettings = BudgetViewSettings(budget: settings, app: defaults)
        let initial = selection ?? (budgetSettings.opensOnBudget ? .budget : Self.defaultSelection(in: store.budget))
        navigation = NavigationState(selection: initial)
        if initial.showsRegister { lastRegisterSelection = initial }
        sidebar = SidebarViewModel(store: store, navigation: navigation, defaults: defaults, budgetSettings: settings)
        register = RegisterViewModel(store: store, navigation: navigation, dialogs: dialogs)
        budget = BudgetViewModel(store: store, navigation: navigation, dialogs: dialogs, settings: budgetSettings)
        if let settings { register.restoreViewStates(from: RegisterViewStateStore(settings: settings)) }
        sidebar.sync = sync
        accounts = AccountsController(store: store, navigation: navigation, dialogs: dialogs)
        accounts.register = register
        accounts.sidebar = sidebar
        lastDate = store.today()
        preferences = defaults
        register.autoFillSettings = AutoFillPreferences.load(from: defaults)
        register.isAppModalOpen = { [weak self] in self?.isAppModalOpen ?? false }
        budget.isAppModalOpen = { [weak self] in self?.isAppModalOpen ?? false }
        register.onEditPayees = { [weak self] name in self?.openPayeeSettings(payeeName: name) }
        register.onEditAccount = { [weak self] id in self?.accounts.editAccountRequested(id) }
        store.onReceive = { [weak self] in self?.register.endEditsOvertakenByChanges() }
        budget.callouts.onShowTransaction = { [weak self] id in self?.register.showTransaction(id) }
        budget.callouts.onShowInAccountView = { [weak self] filter in self?.register.showFilteredView(filter) }
        navigation.onSelectionChange { [weak self] old, new in
            guard let self else { return }
            if old == .budget { budget.leave() }
            if new.showsRegister { lastRegisterSelection = new }
            budgetSettings.opensOnBudget = new == .budget
        }
    }

    var isAppModalOpen: Bool {
        accounts.isPresenting || saveErrorDialog != nil || register.adjustmentHelp != nil || payeeSettings != nil
    }

    public var windowTitle: String {
        "Abakus - \(store.budget.displayName)" + (store.hasUnsavedChanges ? "*" : "")
    }

    public var selectionTitle: String {
        switch navigation.selection {
        case .budget: "Budget"
        case .allAccounts: Account.allAccountsName
        case .account(let id): store.budget.account(withId: id)?.name ?? ""
        }
    }

    /// Quitting waits while an open edit or the budget cannot be saved.
    public func commitBeforeQuit() -> Bool {
        budget.commitEdit()
        register.editor?.commitForQuit()
        register.scheduler.editor?.commitForQuit()
        guard register.editor == nil && register.scheduler.editor == nil else { return false }
        if store.hasUnsavedChanges { store.retrySave() }
        return !store.hasUnsavedChanges
    }

    /// Every failed write shows an error dialog, here with a retry.
    public var saveErrorDialog: PresentedDialog? {
        guard store.saveFailures > acknowledgedSaveFailures, let error = store.lastSaveError else { return nil }
        let dialog = TaskDialog<SaveErrorChoice>(
            title: "Fehler", instruction: "Das Budget ließ sich nicht sichern.",
            content: "Etwas hindert Abakus am Sichern.<br/><br/>" + error,
            buttons: [.init(.retry, title: "Erneut versuchen", isDefault: true), .init(.close, title: "Schließen")],
            dismissal: .close)
        return PresentedDialog(dialog, id: saveErrorId) { [weak self] answer in
            guard let self else { return }
            acknowledgedSaveFailures = store.saveFailures
            if answer.choice == .retry { store.retrySave() }
        }
    }

    /// The save error covers every other dialog.
    var presentedDialogs: [PresentedDialog] {
        dialogs.presented + [saveErrorDialog].compactMap(\.self)
    }

    /// A new day enters due schedules; a jump of several days asks first.
    public func dateChecked(today: DateWithoutTime) {
        let days = lastDate.days(until: today)
        lastDate = today
        if days == 1 {
            store.enterDueScheduledTransactions(today: today)
            register.endEditsOvertakenByChanges()
        } else if days > 1 {
            dialogs.dismiss(ownedBy: self)
            dialogs.ask(
                TaskDialog<ClockChoice>(
                    instruction: "Stimmt die Uhr deines Mac?",
                    content: "Das Datum hat sich gerade um mehr als einen Tag geändert. Sollen fällige geplante "
                        + "Buchungen für das neue Datum angelegt werden?",
                    buttons: [
                        .init(.ignore, title: "Nein, Datum ignorieren"),
                        .init(.enterDue, title: "Ja, das Datum stimmt", isDefault: true),
                    ],
                    dismissal: .enterDue), owner: self
            ) { [weak self] answer in
                guard let self, answer.choice == .enterDue else { return }
                store.enterDueScheduledTransactions(today: today)
                register.endEditsOvertakenByChanges()
            }
        }
    }

    public func runDateTimer() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            dateChecked(today: store.today())
        }
    }

    public static func defaultSelection(in budget: Budget) -> SidebarSelection {
        budget.accounts(in: .budgetAccounts).first.map { .account($0.id) } ?? .allAccounts
    }
}
