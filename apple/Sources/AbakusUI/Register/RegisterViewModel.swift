import AbakusCore
import CoreGraphics
import Foundation
import Observation

struct RegisterAccountViewState {
    var sort = RegisterSortOrder.default
    var expandedSplits: Set<String> = []
    /// nil leaves the Mac's scheduled area to whether anything is planned; touch screens open their sheet by hand.
    var schedulerShown: Bool?
    var filter = RegisterFilter.all
    var searchText = ""
    var expandedSplitsBeforeSearch: Set<String>?
    var scrollBeforeSearch: RegisterScrollRequest.Target?
    var reconciliation: RegisterReconciliation?
    var schedulerHeight: CGFloat?
    var schedulerSort = RegisterScheduler.defaultSort
    var schedulerColumnSettings = RegisterScheduler.defaultColumnSettings
}

@MainActor
@Observable
public final class RegisterViewModel {
    public static let addTitle = "Neue Buchung"

    public let store: any BudgetStoring
    public let navigation: NavigationState
    @ObservationIgnored public var onEditPayees: @MainActor (String?) -> Void = { _ in }
    @ObservationIgnored public var onEditAccount: @MainActor () -> Void = {}
    @ObservationIgnored public var autoFillSettings = AutoFillSettings()
    @ObservationIgnored private var scrollOffsets: [String: CGFloat] = [:]
    @ObservationIgnored private var cache: (inputs: DerivedInputs, value: Derived)?
    var viewStates: [String: RegisterAccountViewState] = [:] {
        didSet { viewStateStore?.save(viewStates) }
    }
    @ObservationIgnored var viewStateStore: RegisterViewStateStore?
    var hiddenColumns: Set<RegisterColumn> = [] {
        didSet { viewStateStore?.saveHiddenColumns(hiddenColumns) }
    }
    private var storedIncomeCheck: (visit: Int, check: RegisterIncomeCheck)?
    private var overlays = (visit: -1, state: RegisterOverlayState())
    var pickingVisit: Int?
    public internal(set) var isClosedAccountsListShown = false
    public internal(set) var gridFocusRequest = 0
    @ObservationIgnored public private(set) lazy var scheduler = RegisterScheduler(register: self)
    @ObservationIgnored public private(set) lazy var search = RegisterSearchController(register: self)
    @ObservationIgnored public private(set) lazy var reconciliation = RegisterReconciliationController(register: self)
    @ObservationIgnored public private(set) lazy var notifiers = RegisterNotifierController(register: self)
    @ObservationIgnored package private(set) lazy var grid = RegisterGridController(register: self)
    public let dialogs: DialogStack
    @ObservationIgnored package var today: () -> DateWithoutTime = { .today() }
    @ObservationIgnored var now: () -> ContinuousClock.Instant = { .now }
    @ObservationIgnored var isAppModalOpen: () -> Bool = { false }
    /// iPhone and iPad: dates without a two-digit year and Saldo as a fixed column of single accounts.
    @ObservationIgnored public var isTouch = false

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

    /// "Abgeglichen am 27.09.", with the year only for an earlier year.
    public var reconciledLabel: String? {
        account?.lastReconciledOn.map { "Abgeglichen am \(headerDate($0))" }
    }

    /// The register's sentences write a date as its rows do: "27.09.", with the year only for another year.
    func headerDate(_ date: DateWithoutTime) -> String {
        date.year == today().year ? formatter.dayMonth(date) : formatter.dateLong(date)
    }

    package var formatter: BudgetFormatter { BudgetFormatter(metaData: store.budget.budgetMetaData) }

    private var key: String { accountKey ?? "" }

    var viewState: RegisterAccountViewState {
        get { viewStates[key] ?? RegisterAccountViewState() }
        set {
            guard let accountKey else { return }
            viewStates[accountKey] = newValue
        }
    }

    /// The transactions' rows and their split lines.
    public var rows: [RegisterRow] { derived.rows }

    /// The rows with a heading above each month while the list is sorted by date.
    public var gridRows: [RegisterRow] { derived.gridRows }

    public var transactions: [Transaction] { derived.transactions }

    public var transactionIds: [String] { derived.transactions.map(\.id) }

    public package(set) var sortOrder: RegisterSortOrder {
        get { viewState.sort }
        set { viewState.sort = newValue }
    }

    public func toggleSplit(_ transactionId: String) {
        grid.toggleSplit(transactionId)
    }

    public var visibleColumns: [RegisterColumn] {
        let onBudget = account?.onBudget ?? true
        return RegisterColumn.allCases.filter { column in
            switch column {
            case .account: isAllAccounts
            case .category: onBudget
            case .cleared: isReconciling || !hiddenColumns.contains(.cleared)
            case .repeats: false
            default: !column.canDisable || !hiddenColumns.contains(column)
            }
        }
    }

    public func columnLayout(gridWidth: CGFloat) -> RegisterColumnLayout {
        var settings = RegisterColumnSettings()
        guard isReconciling else {
            return RegisterColumnLayout(gridWidth: gridWidth, visibleColumns: visibleColumns, settings: settings)
        }
        settings[.cleared] = RegisterColumnSetting(visible: true, width: 90)
        return RegisterColumnLayout(
            gridWidth: gridWidth, visibleColumns: visibleColumns, settings: settings, minimumWidths: [.cleared: 90])
    }

    public var columnMenuItems: [RegisterColumnMenuItem] {
        let order: [RegisterColumn] = [.cleared, .memo]
        return order.map { column in
            RegisterColumnMenuItem(column: column, label: column.menuLabel, isChecked: !hiddenColumns.contains(column))
        }
    }

    public func toggleColumnVisibility(_ column: RegisterColumn) {
        guard column.canDisable else { return }
        if hiddenColumns.contains(column) {
            hiddenColumns.remove(column)
        } else {
            hiddenColumns.insert(column)
        }
        editor?.columns = visibleColumns
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

    /// The new transactions become the selection and the grid scrolls to the first of them.
    func selectEntered(_ ids: [String]) {
        let visible = Set(transactionIds)
        updateSelection { selection in
            selection.clear()
            for id in ids where visible.contains(id) { selection.toggle(id) }
        }
        requestScroll(selectedTransactionIds.first.map { .row($0) } ?? .top)
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
        if grid.swallowsClick(on: row.transactionId) { return }
        selectForIconClick(row)
        guard row.cleared == .reconciled else {
            perform(.toggleCleared([row.transactionId]))
            return
        }
        let id = row.transactionId
        dialogs.ask(
            TaskDialog<UnlockChoice>(
                instruction: "Diese Buchung ist abgeglichen. Entsperren?",
                content: "Sie ist danach gebucht, aber nicht mehr gesperrt.",
                buttons: [
                    .init(.cancel, title: "Abbrechen"),
                    .init(.unlock, title: "Entsperren", isDefault: true),
                ],
                dismissal: .cancel)
        ) { [weak self] answer in
            if answer.choice == .unlock { self?.perform(.setCleared([id], .cleared)) }
        }
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

    /// An open edit glows or ends first, as for the menu bar's items.
    package func viewMenuChosen(_ action: RegisterMenuAction) {
        guard !grid.clickedOutsideEditor() else { return }
        performMenuAction(action)
    }

    public var filter: RegisterFilter { viewState.filter }

    func setFilter(_ filter: RegisterFilter) {
        guard filter != viewState.filter, !isReconciling else { return }
        viewState.filter = filter
        clearSelection()
        endEditsOvertakenByChanges()
        requestScroll(sortOrder.ascending ? .bottom : .top)
    }

    package var expandedSplits: Set<String> {
        get { viewState.expandedSplits }
        set { viewState.expandedSplits = newValue }
    }

    public var canAddTransactions: Bool {
        if let account { return account.takesEntries }
        return store.budget.accounts.contains(where: \.takesEntries)
    }

    public var showsTransferButton: Bool {
        let open = store.budget.accounts.filter { !$0.closed }
        return isAllAccounts ? open.count > 1 : open.contains { $0.id != key }
    }

    public func addTransactionClicked() {
        grid.beginNew()
    }

    public var summary: RegisterSummary {
        let balances = store.budget.balances(forAccount: key)
        let isSearching = search.isSearching
        let first =
            isSearching
            ? RegisterSummaryItem.blank
            : summaryItem(
                .cleared, "Gebucht", balances.cleared, "Summe der gebuchten und abgeglichenen Buchungen.")
        let second: RegisterSummaryItem
        if isSearching {
            let total = Amount.sum(transactions.map(\.amount))
            second = summaryItem(
                .search, "Suchsumme (\(transactions.count))", total,
                "Summe aller Buchungen, die die Suche findet.")
        } else {
            second = summaryItem(
                .uncleared, "Vorgemerkt", balances.uncleared,
                "Summe der vorgemerkten Buchungen, die die Bank noch nicht kennt.")
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

    public var isSchedulerVisible: Bool { viewState.schedulerShown ?? false }

    /// What is planned shows collapsed with its count; with nothing planned only Ansicht shows the list.
    public var scheduledSummary: String? {
        let count = scheduler.count
        guard count > 0, !isReconciling else { return nil }
        return "Geplant · \(count)"
    }

    public func scheduledToggleClicked() {
        let shown = isSchedulerVisible
        if shown, scheduler.grid.clickedOutsideEditor() { return }
        viewState.schedulerShown = !shown
        if shown { schedulerHidden() }
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

    /// nil for an account not scrolled yet, which starts at the top.
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
        var expandedSplits: Set<String>
        var filter: RegisterFilter
        var search: RegisterSearch
        var editingId: String?
        var today: DateWithoutTime
        var reconcileThrough: DateWithoutTime?

        /// Only a budget change adds rows to the same list; a new filter or account redraws it without a glow.
        func addsRows(to previous: DerivedInputs) -> Bool {
            budget != previous.budget && key == previous.key && filter == previous.filter && search == previous.search
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
        var gridRows: [RegisterRow]
        var searchHits: [String: RegisterSearch.Hit] = [:]
        var notifierCounts = RegisterNotifierCounts()
        var added = AddedRows()
    }

    var derived: Derived {
        let state = viewState
        let inputs = DerivedInputs(
            budget: store.budget, key: key, sort: state.sort, expandedSplits: state.expandedSplits,
            filter: state.filter, search: RegisterSearch(state.searchText), editingId: grid.editingId, today: today(),
            reconcileThrough: state.reconciliation?.statementDate
        )
        if let cache, cache.inputs == inputs { return cache.value }
        var value = derive(inputs)
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

    private func derive(_ inputs: DerivedInputs) -> Derived {
        let budget = inputs.budget
        guard !inputs.key.isEmpty else { return Derived(transactions: [], rows: [], gridRows: []) }
        let all: [Transaction]
        if let through = inputs.reconcileThrough {
            all = budget.reconciliationList(accountId: inputs.key, through: through)
        } else {
            all = inputs.key == EntityID.allAccounts ? budget.transactions : budget.transactions(inAccount: inputs.key)
        }
        let lookup = BudgetLookup(budget)
        let formatter = BudgetFormatter(metaData: budget.budgetMetaData)
        var searchHits: [String: RegisterSearch.Hit] = [:]
        let listed = all.filter { transaction in
            guard inputs.filter.includes(transaction, in: lookup) else { return false }
            guard !inputs.search.isEmpty else { return true }
            guard let hit = inputs.search.hit(transaction, lookup: lookup, formatter: formatter) else { return false }
            searchHits[transaction.id] = hit
            return true
        }
        let showsMonths = inputs.sort.column == .date
        var builder = RegisterRowBuilder(lookup: lookup)
        builder.showsYear = !showsMonths
        builder.omitsYear = isTouch ? inputs.today.year : nil
        let rowFormatter = builder.formatter
        let sorted = RegisterSorter.sorted(listed, by: inputs.sort, lookup: lookup)
        let gridRows = builder.rows(
            for: sorted, expandedSplits: inputs.expandedSplits, editingId: inputs.editingId,
            heading: { showsMonths ? rowFormatter.monthHeader($0.date) : nil },
            row: builder.row(for:isExpanded:),
            subRows: { builder.subRows(for: $0) })
        return Derived(
            transactions: sorted, rows: showsMonths ? gridRows.filter { !$0.isMonthHeading } : gridRows,
            gridRows: gridRows, searchHits: searchHits,
            notifierCounts: budget.notifierCounts(forAccount: inputs.key))
    }
}
