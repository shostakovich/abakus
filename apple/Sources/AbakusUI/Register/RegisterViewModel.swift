import AbakusCore
import CoreGraphics
import Foundation
import Observation

struct RegisterAccountViewState {
    var sort = RegisterSortOrder.default
    var isShowingReconciled = true
    var columnSettings = RegisterColumnSettings()
    var expandedSplits: Set<String> = []
    var isSchedulerVisible = false
    var searchText = ""
    var searchFilter: RegisterSearchFilter?
    var dateFilter: DateFilterSelection?
    var expandedSplitsBeforeSearch: Set<String>?
    var scrollBeforeSearch: RegisterScrollRequest.Target?
    var reconciliation: RegisterReconciliation?
    var schedulerHeight: CGFloat?
    var schedulerSort = RegisterSortOrder.default
    var schedulerColumnSettings = RegisterScheduler.defaultColumnSettings
}

@MainActor
@Observable
public final class RegisterViewModel {
    public static let addTitle = "Neue Buchung"
    public static let transferTitle = "Neue Umbuchung"

    public let store: any BudgetStoring
    public let navigation: NavigationState
    @ObservationIgnored public var onEditPayees: @MainActor (String?) -> Void = { _ in }
    @ObservationIgnored public var autoFillSettings = AutoFillSettings()
    @ObservationIgnored private var scrollOffsets: [String: CGFloat] = [:]
    @ObservationIgnored private var cache: (inputs: DerivedInputs, value: Derived)?
    var viewStates: [String: RegisterAccountViewState] = [:] {
        didSet { viewStateStore?.save(viewStates) }
    }
    @ObservationIgnored var viewStateStore: RegisterViewStateStore?
    var adjustmentHelpSlot: (visit: Int, help: RegisterAdjustmentHelp)?
    private var storedIncomeCheck: (visit: Int, check: RegisterIncomeCheck)?
    private var overlays = (visit: -1, state: RegisterOverlayState())
    public internal(set) var renamePayeeForm: RenamePayeeForm?
    public internal(set) var gridFocusRequest = 0
    public internal(set) var lastScheduledTransactionId: String?
    @ObservationIgnored public private(set) lazy var scheduler = RegisterScheduler(register: self)
    @ObservationIgnored public private(set) lazy var search = RegisterSearchController(register: self)
    @ObservationIgnored public private(set) lazy var reconciliation = RegisterReconciliationController(register: self)
    @ObservationIgnored public private(set) lazy var notifiers = RegisterNotifierController(register: self)
    @ObservationIgnored private(set) lazy var grid = RegisterGridController(register: self)
    public let dialogs: DialogStack
    @ObservationIgnored var today: () -> DateWithoutTime = { .today() }
    @ObservationIgnored var now: () -> ContinuousClock.Instant = { .now }
    @ObservationIgnored var isAppModalOpen: () -> Bool = { false }

    public init(store: any BudgetStoring, navigation: NavigationState, dialogs: DialogStack = DialogStack()) {
        self.store = store
        self.navigation = navigation
        self.dialogs = dialogs
        today = store.today
        grid.owner = self
        grid.peer = scheduler.grid
        scheduler.grid.peer = grid
    }

    /// Menus, popups and the search drop-down belong to one visit of an account.
    var overlayState: RegisterOverlayState {
        get { overlays.visit == navigation.visit ? overlays.state : RegisterOverlayState() }
        set { overlays = (navigation.visit, newValue) }
    }

    func closeOverlays() {
        overlayState = RegisterOverlayState()
    }

    public internal(set) var incomeCheck: RegisterIncomeCheck? {
        get { storedIncomeCheck.flatMap { $0.visit == navigation.visit ? $0.check : nil } }
        set { storedIncomeCheck = newValue.map { (navigation.visit, $0) } }
    }

    public internal(set) var menuRequest: RegisterMenuRequest? {
        get { overlayState.menuRequest }
        set { overlayState.menuRequest = newValue }
    }

    public internal(set) var popup: RegisterPopup? {
        get { overlayState.popup }
        set { overlayState.popup = newValue }
    }

    public var accountKey: String? {
        switch navigation.selection {
        case .account(let id): id
        case .allAccounts: EntityID.allAccounts
        case .budget: nil
        }
    }

    public var isAllAccounts: Bool { accountKey == EntityID.allAccounts }

    public var account: Account? {
        guard let accountKey, !isAllAccounts else { return nil }
        return store.budget.account(withId: accountKey)
    }

    public var accountName: String { isAllAccounts ? Account.allAccountsName : account?.name ?? "" }

    var formatter: BudgetFormatter { BudgetFormatter(metaData: store.budget.budgetMetaData) }

    private var key: String { accountKey ?? "" }

    var viewState: RegisterAccountViewState {
        get { viewStates[key] ?? RegisterAccountViewState() }
        set {
            guard let accountKey else { return }
            viewStates[accountKey] = newValue
        }
    }

    public var rows: [RegisterRow] { derived.rows }

    public var transactions: [Transaction] { derived.transactions }

    public var transactionIds: [String] { derived.transactions.map(\.id) }

    public internal(set) var sortOrder: RegisterSortOrder {
        get { viewState.sort }
        set { viewState.sort = newValue }
    }

    public func toggleSplit(_ transactionId: String) {
        grid.toggleSplit(transactionId)
    }

    public var showsErrorColumn: Bool { derived.hasErrors }

    public var visibleColumns: [RegisterColumn] {
        let settings = viewState.columnSettings
        let onBudget = account?.onBudget ?? true
        return RegisterColumn.allCases.filter { column in
            switch column {
            case .account: isAllAccounts
            case .errorState: showsErrorColumn
            case .category: onBudget
            case .cleared: isReconciling || (settings[.cleared]?.visible ?? false)
            case .frequency: false
            default: column.canDisable ? settings[column]?.visible ?? false : true
            }
        }
    }

    public func columnLayout(gridWidth: CGFloat) -> RegisterColumnLayout {
        var settings = viewState.columnSettings
        guard isReconciling else {
            return RegisterColumnLayout(gridWidth: gridWidth, visibleColumns: visibleColumns, settings: settings)
        }
        settings[.cleared] = RegisterColumnSetting(visible: true, width: 90)
        return RegisterColumnLayout(
            gridWidth: gridWidth, visibleColumns: visibleColumns, settings: settings, minimumWidths: [.cleared: 90])
    }

    public var columnSettings: RegisterColumnSettings { viewState.columnSettings }

    public var columnMenuItems: [RegisterColumnMenuItem] {
        let order: [RegisterColumn] = [.cleared, .memo, .runningBalance]
        return order.filter { !(isAllAccounts && $0 == .runningBalance) }.map { column in
            RegisterColumnMenuItem(
                column: column, label: column.menuLabel,
                isChecked: viewState.columnSettings[column]?.visible ?? false)
        }
    }

    public func toggleColumnVisibility(_ column: RegisterColumn) {
        guard column.canDisable, var setting = viewState.columnSettings[column] else { return }
        setting.visible.toggle()
        viewState.columnSettings[column] = setting
        editor?.columns = visibleColumns
    }

    public func columnOptionsClicked() {
        showMenu(columnMenu, below: columnTab)
    }

    public var selection: RegisterSelection { grid.selection }

    public var selectedTransactionIds: [String] { grid.selectedIds }

    @discardableResult
    public func rowClicked(_ row: RegisterRow, column: RegisterColumn?, modifiers: RegisterClickModifiers) -> Bool {
        grid.rowClicked(row.transactionId, column: column, modifiers: modifiers)
    }

    public func selectAll() {
        let ids = transactionIds
        updateSelection { $0.selectAll(ids) }
    }

    /// The new transactions become the selection and the grid scrolls to the end.
    func selectEntered(_ ids: [String]) {
        let visible = Set(transactionIds)
        updateSelection { selection in
            selection.clear()
            for id in ids where visible.contains(id) { selection.toggle(id) }
        }
        requestScroll(.bottom)
    }

    public func clearSelection() {
        grid.clearSelection()
    }

    func updateSelection(_ update: (inout RegisterSelection) -> Void) {
        grid.updateSelection(update)
    }

    /// Mouse-down on an icon cell keeps a multi-selection that contains the row.
    private func selectForIconClick(_ row: RegisterRow) {
        guard !selection.contains(row.transactionId) else { return }
        updateSelection { $0.select(row.transactionId) }
    }

    public func clearedClicked(_ row: RegisterRow) {
        if row.transactionId == editingTransactionId, let editor {
            editor.toggleCleared()
            return
        }
        if grid.swallowsClick(on: row.transactionId) { return }
        selectForIconClick(row)
        perform(.toggleCleared(selectedTransactionIds))
    }

    public func errorIconClicked(_ row: RegisterRow) {
        if grid.swallowsClick(on: row.transactionId) { return }
        selectForIconClick(row)
        showStatusPopup(for: row)
    }

    public func transferIconClicked(_ row: RegisterRow) {
        if grid.swallowsClick(on: row.transactionId) { return }
        jumpToOtherSide(of: row)
    }

    public var actionButtonTitle: String {
        switch selection.count {
        case 0: "Buchungen bearbeiten"
        case 1: "1 Buchung bearbeiten"
        case let count: "\(count) Buchungen bearbeiten"
        }
    }

    public var isActionButtonEnabled: Bool { !selection.isEmpty }

    public func editTransactionsClicked() {
        if grid.clickedOutsideEditor() { return }
        showMenu(transactionActionsMenu(withTitle: false), below: .actionButton)
    }

    /// The menu bar's Edit Transactions items: an open edit glows or ends first, as after a click on the button.
    func editTransactionsCommandChosen(_ action: RegisterMenuAction) {
        guard acceptsRegisterKeys, !grid.clickedOutsideEditor() else { return }
        performMenuAction(action)
    }

    public var isShowingReconciled: Bool { viewState.isShowingReconciled }

    public func setShowingReconciled(_ showing: Bool) {
        guard showing != viewState.isShowingReconciled, !grid.clickedOutsideEditor() else { return }
        viewState.isShowingReconciled = showing
        clearSelection()
        endEditsOvertakenByChanges()
    }

    public var isReconciledFilterEnabled: Bool { !search.isFiltered }

    var expandedSplits: Set<String> {
        get { viewState.expandedSplits }
        set { viewState.expandedSplits = newValue }
    }

    public var canAddTransactions: Bool { !store.budget.accounts.isEmpty }

    public var showsTransferButton: Bool {
        let open = store.budget.accounts.filter { !$0.closed }
        return isAllAccounts ? open.count > 1 : open.contains { $0.id != key }
    }

    public func addTransactionClicked() {
        grid.beginNew()
    }

    public func makeTransferClicked() {
        guard showsTransferButton else { return }
        grid.beginNew(transfer: true)
    }

    public var summary: RegisterSummary {
        let balances = store.budget.balances(forAccount: key)
        let isSearching = viewState.searchFilter != nil
        let first =
            isSearching
            ? RegisterSummaryItem.blank
            : summaryItem(
                .cleared, "Gebucht", balances.cleared,
                "Summe der gebuchten und abgeglichenen Buchungen. Klicken, um sie zu zeigen.")
        let second: RegisterSummaryItem
        if isSearching {
            let matches = derived.searchMatches
            let total = Amount.sum(transactions.map { matches[$0.id]?.searchAmount(of: $0) ?? $0.amount })
            second = summaryItem(
                .search, "Suchsumme (\(transactions.count))", total,
                "Summe aller Buchungen, die die Suche findet.")
        } else {
            second = summaryItem(
                .uncleared, "Vorgemerkt", balances.uncleared,
                "Summe der vorgemerkten Buchungen, die die Bank noch nicht kennt. Klicken, um sie zu zeigen.")
        }
        let working = summaryItem(
            .working, "Arbeitssaldo", balances.working,
            "Das Geld, das auf diesem Konto tatsächlich da ist: gebuchte und vorgemerkte Buchungen zusammen.")
        return RegisterSummary(first: first, second: second, working: working)
    }

    /// The status bar's total, shown only for more than one selected transaction.
    public var selectedTotal: RegisterSummaryItem? {
        let selection = selection
        guard selection.count > 1 else { return nil }
        let selected = transactions.filter { selection.contains($0.id) }
        return summaryItem(
            .selected, "Auswahl (\(selection.count))", Amount.sum(selected.map(\.amount)),
            "Summe aller ausgewählten Buchungen")
    }

    private func summaryItem(_ kind: RegisterSummaryKind, _ title: String, _ amount: Decimal, _ tooltip: String)
        -> RegisterSummaryItem
    {
        RegisterSummaryItem(
            kind: kind, title: title, amountText: formatter.currency(amount), isNegative: amount < 0, tooltip: tooltip)
    }

    public func summaryClicked(_ kind: RegisterSummaryKind) {
        guard kind == .cleared || kind == .uncleared, !grid.clickedOutsideEditor() else { return }
        search.text = kind == .cleared ? "Ist: Gebucht oder abgeglichen" : "Ist: Vorgemerkt"
        search.commit()
    }

    public var isSchedulerVisible: Bool { viewState.isSchedulerVisible }

    public func scheduledToggleClicked() {
        if viewState.isSchedulerVisible, scheduler.grid.clickedOutsideEditor() { return }
        viewState.isSchedulerVisible.toggle()
        if !viewState.isSchedulerVisible { schedulerHidden() }
    }

    /// A hidden scheduler would still follow its pending scroll when it shows again.
    func schedulerHidden() {
        scheduler.grid.cancelEditing()
        scheduler.grid.scrollRequest = nil
    }

    func cancelEdits() {
        grid.cancelEditing()
        scheduler.grid.cancelEditing()
    }

    /// An edit with changes in either grid glows instead of letting a control drop it.
    func clickedOutsideEditors() -> Bool {
        grid.clickedOutsideEditor() || scheduler.grid.clickedOutsideEditor()
    }

    public var scheduledToggleTooltip: String {
        isSchedulerVisible ? "Geplante Buchungen ausblenden" : "Geplante Buchungen zeigen"
    }

    public var isReconciling: Bool { reconciliation.current != nil }

    /// nil means "scrolled to the end", the state of an account shown for the first time.
    public func savedScrollOffset() -> CGFloat? {
        scrollOffsets[key]
    }

    public func saveScrollOffset(_ offset: CGFloat?) {
        scrollOffsets[key] = offset
    }

    private struct DerivedInputs: Equatable {
        var budget: Budget
        var key: String
        var sort: RegisterSortOrder
        var isShowingReconciled: Bool
        var expandedSplits: Set<String>
        var searchFilter: RegisterSearchFilter?
        var dateFilter: DateFilterSelection?
        var needsRunningBalance: Bool
        var editingId: String?
        var today: DateWithoutTime
        var reconcileThrough: DateWithoutTime?

        /// Only a budget change adds rows to the same list; a new filter or account redraws it without a glow.
        func addsRows(to previous: DerivedInputs) -> Bool {
            budget != previous.budget && key == previous.key && searchFilter == previous.searchFilter
                && dateFilter == previous.dateFilter && isShowingReconciled == previous.isShowingReconciled
                && reconcileThrough == previous.reconcileThrough && today == previous.today
        }
    }

    struct AddedRows {
        var ids: Set<String> = []
        var start: ContinuousClock.Instant?
    }

    struct Derived {
        var transactions: [Transaction]
        var rows: [RegisterRow]
        var hasErrors: Bool
        var searchMatches: [String: RegisterSearchMatch] = [:]
        var notifierCounts = RegisterNotifierCounts()
        var added = AddedRows()
    }

    var derived: Derived {
        let state = viewState
        let inputs = DerivedInputs(
            budget: store.budget, key: key, sort: state.sort, isShowingReconciled: state.isShowingReconciled,
            expandedSplits: state.expandedSplits, searchFilter: state.searchFilter, dateFilter: state.dateFilter,
            needsRunningBalance: state.columnSettings[.runningBalance]?.visible ?? false,
            editingId: grid.editingId, today: today(),
            reconcileThrough: state.reconciliation?.statementDate
        )
        if let cache, cache.inputs == inputs { return cache.value }
        var value = derive(inputs, state: state)
        if let previous = cache, inputs.addsRows(to: previous.inputs) {
            let before = Set(previous.value.transactions.map(\.id))
            let added = Set(value.transactions.map(\.id).filter { !before.contains($0) })
            value.added = added.isEmpty ? previous.value.added : AddedRows(ids: added, start: now())
        }
        cache = (inputs, value)
        return value
    }

    public func addedRowGlowStart(_ transactionId: String) -> ContinuousClock.Instant? {
        let added = derived.added
        return added.ids.contains(transactionId) ? added.start : nil
    }

    private func derive(_ inputs: DerivedInputs, state: RegisterAccountViewState) -> Derived {
        let budget = inputs.budget
        guard !inputs.key.isEmpty else { return Derived(transactions: [], rows: [], hasErrors: false) }
        let all: [Transaction]
        if let through = inputs.reconcileThrough {
            all = budget.reconciliationList(accountId: inputs.key, through: through)
        } else {
            all = inputs.key == EntityID.allAccounts ? budget.transactions : budget.transactions(inAccount: inputs.key)
        }
        let unfiltered = state.searchFilter == nil && state.dateFilter == nil
        let query = state.searchFilter?.query
        let lookup = BudgetLookup(budget)
        let environment = query.map { _ in RegisterSearchEnvironment(lookup: lookup, today: inputs.today) }
        var searchMatches: [String: RegisterSearchMatch] = [:]
        let listed = all.filter { transaction in
            if inputs.reconcileThrough == nil, let dates = state.dateFilter, !dates.contains(transaction.date) {
                return false
            }
            if let query, let environment {
                let match = query.match(transaction, in: environment)
                guard match.isVisible else { return false }
                searchMatches[transaction.id] = match
            }
            return !(unfiltered && !state.isShowingReconciled && transaction.cleared == .reconciled)
        }
        let builder = RegisterRowBuilder(
            lookup: lookup,
            runningBalances: inputs.needsRunningBalance ? budget.runningBalances(forAccount: inputs.key) : [:])
        let sorted = RegisterSorter.sorted(listed, by: inputs.sort, lookup: lookup)
        let rows = builder.rows(
            for: sorted, expandedSplits: inputs.expandedSplits, editingId: inputs.editingId,
            row: builder.row(for:isExpanded:),
            subRows: { builder.subRows(for: $0, parentIndex: $1, match: searchMatches[$0.id]) })
        let counts = budget.notifierCounts(forAccount: inputs.key)
        return Derived(
            transactions: sorted, rows: rows, hasErrors: counts != RegisterNotifierCounts(),
            searchMatches: searchMatches, notifierCounts: counts)
    }
}
