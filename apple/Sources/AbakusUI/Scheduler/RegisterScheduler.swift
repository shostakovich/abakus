import AbakusCore
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class RegisterScheduler {
    public static let title = "Geplante Buchungen"
    public static let minimumHeight: CGFloat = 185
    public static let addTitle = "Neue geplante Buchung"
    public static let transferTitle = "Neue geplante Umbuchung"
    public static let enterTitle = "Jetzt buchen"
    public static let skipTitle = "Diesmal überspringen"
    public static let deleteTitle = "Löschen"
    public static let moveTitle = "In Konto verschieben"

    unowned let register: RegisterViewModel
    public let store: any BudgetStoring
    public let navigation: NavigationState
    let grid: RegisterGridController
    var expandedSplits: Set<String> = []

    init(register: RegisterViewModel) {
        self.register = register
        store = register.store
        navigation = register.navigation
        grid = RegisterGridController(register: register, newFrequency: .monthly)
        grid.owner = self
    }

    public var isVisible: Bool { register.isSchedulerVisible }

    public var savedHeight: CGFloat {
        max(register.viewState.schedulerHeight ?? Self.minimumHeight, Self.minimumHeight)
    }

    public func setHeight(_ height: CGFloat) {
        register.viewState.schedulerHeight = max(Self.minimumHeight, height)
    }

    public var scheduledTransactions: [ScheduledTransaction] {
        guard let accountKey = register.accountKey else { return [] }
        let budget = store.budget
        let all =
            register.isAllAccounts ? budget.scheduledTransactions : budget.scheduledTransactions(inAccount: accountKey)
        let lookup = BudgetLookup(budget)
        let order = sortOrder
        let frequencies = ScheduledTransactionFrequency.allCases
        return all.map { scheduled in
            (
                scheduled,
                RegisterSortKeys(
                    accountName: lookup.account(withId: scheduled.accountId)?.name ?? "",
                    keys: lookup.defaultOrderKeys(of: scheduled.editableTransaction),
                    frequency: frequencies.firstIndex(of: scheduled.frequency) ?? 0)
            )
        }
        .sorted { $0.1.precedes($1.1, order: order) }
        .map(\.0)
    }

    public internal(set) var sortOrder: RegisterSortOrder {
        get { register.viewState.schedulerSort }
        set { register.viewState.schedulerSort = newValue }
    }

    public var scheduledIds: [String] { scheduledTransactions.map(\.id) }

    public var visibleColumns: [RegisterColumn] {
        let settings = columnSettings
        var columns: [RegisterColumn] = register.isAllAccounts ? [.account] : []
        columns += [.date, .frequency, .payee]
        if register.account?.onBudget ?? true { columns.append(.category) }
        columns += [.memo, .outflow, .inflow]
        return columns.filter { !$0.canDisable || settings[$0]?.visible == true }
    }

    /// The next one due first, unlike the register's newest first.
    nonisolated public static let defaultSort = RegisterSortOrder(column: .date, ascending: true)

    nonisolated public static var defaultColumnSettings: RegisterColumnSettings {
        var settings = RegisterColumnSettings()
        for column in [RegisterColumn.runningBalance, .cleared] { settings[column] = nil }
        settings[.memo]?.visible = true
        settings[.frequency] = RegisterColumnSetting(visible: true, width: 70)
        return settings
    }

    var columnSettings: RegisterColumnSettings { register.viewState.schedulerColumnSettings }

    public func columnLayout(gridWidth: CGFloat) -> RegisterColumnLayout {
        RegisterColumnLayout(
            gridWidth: gridWidth, visibleColumns: visibleColumns, settings: columnSettings,
            contentWidths: contentWidths)
    }

    /// Date, frequency and amounts fit what they show; payee, category and memo share the rest.
    var contentWidths: [RegisterColumn: CGFloat] {
        let rows = rows
        let frequencies = rows.map(\.frequency) + [editor?.frequency?.readableName].compactMap { $0 }
        return [
            .date: RegisterColumn.date.contentWidth(fitting: rows.map(\.date)),
            .frequency: RegisterColumn.frequency.contentWidth(
                fitting: frequencies, accessory: SchedulerMetrics.popUpAccessory),
            .outflow: RegisterColumn.outflow.contentWidth(fitting: rows.map(\.outflow)),
            .inflow: RegisterColumn.inflow.contentWidth(fitting: rows.map(\.inflow)),
        ]
    }

    public var columnMenu: [RegisterMenuItem] {
        let settings = columnSettings
        let columns = [RegisterColumn.memo].map {
            RegisterMenuItem.action($0.menuLabel, .toggleScheduledColumn($0), checked: settings[$0]?.visible ?? false)
        }
        return columns + [
            .separator(0),
            .action("Für alle Konten übernehmen", .applyScheduledColumnsToAllAccounts),
        ]
    }

    public func columnOptionsClicked() {
        register.showMenu(columnMenu, below: columnTab)
    }

    func toggleColumnVisibility(_ column: RegisterColumn) {
        guard column.canDisable, var setting = columnSettings[column] else { return }
        setting.visible.toggle()
        register.viewState.schedulerColumnSettings[column] = setting
        editor?.columns = visibleColumns
    }

    func applyColumnSettingsToAllAccounts() {
        let settings = columnSettings
        for account in store.budget.accounts {
            var state = register.viewStates[account.id] ?? RegisterAccountViewState()
            state.schedulerColumnSettings = settings
            register.viewStates[account.id] = state
        }
    }

    public var rows: [RegisterRow] {
        let builder = RegisterRowBuilder(lookup: BudgetLookup(store.budget))
        return builder.rows(
            for: scheduledTransactions, expandedSplits: expandedSplits, editingId: grid.editingId,
            row: builder.row(for:isExpanded:), subRows: builder.subRows(for:))
    }

    public var selection: RegisterSelection { grid.selection }

    public var selectedIds: [String] { grid.selectedIds }

    public func clearSelection() {
        grid.clearSelection()
    }

    func reveal(_ id: String) {
        grid.updateSelection { $0.select(id) }
        grid.requestScroll(.row(id))
    }

    /// Mouse-down of the secondary button: false when an edit swallows it, else the row joins the selection.
    @discardableResult
    public func contextClicked(_ row: RegisterRow) -> Bool {
        if grid.swallowsClick(on: row.transactionId) { return false }
        guard !selection.contains(row.transactionId) else { return true }
        grid.updateSelection { $0.select(row.transactionId) }
        return true
    }

    public var menuTitle: String {
        let count = selection.count
        return count == 1 ? "1 ausgewählte geplante Buchung" : "\(count) ausgewählte geplante Buchungen"
    }

    public var moveTargets: [Account] { store.budget.moveTargets(excluding: register.accountKey) }

    /// The scheduled action menu as the grid's context menu, with the selection count as its title.
    public func contextMenu(for row: RegisterRow) -> [RegisterMenuItem]? {
        guard contextClicked(row) else { return nil }
        let targets = moveTargets.map {
            RegisterMenuItem.action($0.name, .moveScheduled(accountId: $0.id))
        }
        return [
            RegisterMenuItem(id: "title", title: menuTitle, kind: .title, isEnabled: false),
            .separator(0),
            .action(Self.enterTitle, .enterScheduledNow),
            .action(Self.skipTitle, .skipScheduled),
            .separator(1),
            .action(Self.deleteTitle, .deleteScheduled),
            .separator(2),
            RegisterMenuItem(id: "move", title: Self.moveTitle, kind: .submenu(targets), isEnabled: !targets.isEmpty),
        ]
    }

    public func enterNowClicked() {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        let entry = ScheduledEntry(scheduledIds: ids, approved: true)
        let entered = store.budget.transactionIdsEntered(by: entry)
        guard perform(.enterScheduledTransactions(entry)) else { return }
        clearSelection()
        register.selectEntered(entered)
    }

    public func skipClicked() {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        perform(.skipScheduledTransactions(ids))
    }

    public func deleteClicked() {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        perform(.deleteScheduledTransactions(ids))
    }

    public func deleteKeyPressed() {
        guard grid.acceptsKeys, editor == nil else { return }
        deleteClicked()
    }

    public func moveClicked(to accountId: String) {
        let ids = selectedIds
        guard !ids.isEmpty, let target = store.budget.account(withId: accountId) else { return }
        let before = store.budget
        guard perform(.moveScheduledTransactions(ids, toAccount: accountId)) else { return }
        let wanted = Set(ids)
        let moved = before.scheduledTransactions.filter { wanted.contains($0.id) }.map {
            MovedTransaction(transactionId: $0.id, accountId: $0.accountId, cleared: $0.cleared)
        }
        let message =
            ids.count == 1
            ? "Buchung nach „\(target.name)“ verschoben"
            : "\(ids.count) Buchungen nach „\(target.name)“ verschoben"
        register.notifiers.offerUndo(message: message, restore: .movedSchedules(moved), reselect: ids)
    }

    func reselect(_ ids: [String]) {
        let visible = Set(scheduledIds)
        grid.updateSelection { selection in
            for id in ids where visible.contains(id) && !selection.contains(id) { selection.toggle(id) }
        }
    }

    public func addClicked() {
        grid.beginNew()
    }

    public func transferClicked() {
        guard showsTransferButton else { return }
        grid.beginNew(transfer: true)
    }

    public var showsTransferButton: Bool { register.showsTransferButton }
    public var canAddTransactions: Bool { register.canAddTransactions }

    public var editor: TransactionEditor? { grid.editor }

    func endEditIfOvertaken() {
        guard let editor, editor.mode == .existing,
            store.budget.scheduledTransaction(withId: editor.transactionId)?.editableTransaction != editor.original
        else { return }
        grid.cancelEditing()
    }

    public func beginEditing(_ id: String, column: RegisterColumn? = nil) {
        grid.beginEditing(id, column: column)
    }

    @discardableResult
    private func perform(_ command: BudgetCommand) -> Bool {
        register.perform(command)
    }
}

extension RegisterScheduler: RegisterGridOwner {
    var mainGrid: RegisterViewModel? { nil }
    var gridIds: [String] { scheduledIds }
    var gridRows: [RegisterRow] { rows }
    var columnTab: RegisterAnchorID { .schedulerColumnTab }
    /// Snapped, the reveal of its edit row would stop a point short of the row's end.
    var snapsToRows: Bool { false }

    func headerContextMenu() -> [RegisterMenuItem]? { nil }

    func editorRecord(_ id: String) -> (transaction: Transaction, frequency: ScheduledTransactionFrequency?)? {
        store.budget.scheduledTransaction(withId: id).map { ($0.editableTransaction, $0.frequency) }
    }

    func followUpEdit(_ outcome: EditorOutcome) {}
}
