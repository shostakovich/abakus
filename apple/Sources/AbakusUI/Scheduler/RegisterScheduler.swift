import AbakusCore
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class RegisterScheduler {
    public static let title = "Geplante Buchungen"
    public static let minimumHeight: CGFloat = 185
    public static let addTitle = "Geplante Buchung hinzufügen"
    public static let emptyTitle = "Keine geplanten Buchungen"
    public static let emptyMessage = "Wiederkehrende und künftige Buchungen erscheinen hier."
    public static let enterTitle = "Jetzt buchen"
    public static let skipTitle = "Überspringen"
    public static let deleteTitle = "Löschen …"
    public static let moveTitle = "In Konto verschieben"

    unowned let register: RegisterViewModel
    public let store: any BudgetStoring
    public let navigation: NavigationState
    package let grid: RegisterGridController
    package var expandedSplits: Set<String> = []

    init(register: RegisterViewModel) {
        self.register = register
        store = register.store
        navigation = register.navigation
        grid = RegisterGridController(register: register, newRepeat: .monthly, editsInSheet: true)
        grid.owner = self
    }

    public var isVisible: Bool { register.isSchedulerVisible }

    public var savedHeight: CGFloat {
        max(register.viewState.schedulerHeight ?? Self.minimumHeight, Self.minimumHeight)
    }

    public func setHeight(_ height: CGFloat) {
        register.viewState.schedulerHeight = max(Self.minimumHeight, height)
    }

    public var count: Int { shown.count }

    private var shown: [ScheduledTransaction] {
        guard let accountKey = register.accountKey else { return [] }
        let budget = store.budget
        return register.isAllAccounts
            ? budget.scheduledTransactions : budget.scheduledTransactions(inAccount: accountKey)
    }

    public var scheduledTransactions: [ScheduledTransaction] {
        let lookup = BudgetLookup(store.budget)
        let order = sortOrder
        return shown.map { scheduled in
            (
                scheduled,
                RegisterSortKeys(
                    accountName: lookup.account(withId: scheduled.accountId)?.name ?? "",
                    keys: lookup.defaultOrderKeys(of: scheduled.editableTransaction),
                    repeatDays: Self.days(scheduled.repeats))
            )
        }
        .sorted { $0.1.precedes($1.1, order: order) }
        .map(\.0)
    }

    public package(set) var sortOrder: RegisterSortOrder {
        get { register.viewState.schedulerSort }
        set { register.viewState.schedulerSort = newValue }
    }

    public var scheduledIds: [String] { scheduledTransactions.map(\.id) }

    public var visibleColumns: [RegisterColumn] {
        let settings = columnSettings
        var columns: [RegisterColumn] = register.isAllAccounts ? [.account] : []
        columns += [.date, .repeats, .payee]
        if register.account?.onBudget ?? true { columns.append(.category) }
        columns += [.memo, .amount]
        return columns.filter { !$0.canDisable || settings[$0]?.visible == true }
    }

    /// The next one due first, unlike the register's newest first.
    nonisolated public static let defaultSort = RegisterSortOrder(column: .date, ascending: true)

    nonisolated public static var defaultColumnSettings: RegisterColumnSettings {
        var settings = RegisterColumnSettings()
        settings[.cleared] = nil
        settings[.memo]?.visible = true
        settings[.repeats] = RegisterColumnSetting(visible: true, width: 70)
        return settings
    }

    var columnSettings: RegisterColumnSettings { register.viewState.schedulerColumnSettings }

    public func columnLayout(gridWidth: CGFloat) -> RegisterColumnLayout {
        RegisterColumnLayout(
            gridWidth: gridWidth, visibleColumns: visibleColumns, settings: columnSettings,
            contentWidths: contentWidths)
    }

    /// Date, Wiederholen and Betrag fit what they show; payee, category and memo share the rest.
    var contentWidths: [RegisterColumn: CGFloat] {
        let rows = rows
        return [
            .date: RegisterColumn.date.contentWidth(fitting: rows.map(\.date)),
            .repeats: RegisterColumn.repeats.contentWidth(fitting: rows.map(\.repeatLabel)),
            .amount: RegisterColumn.amount.contentWidth(
                fitting: rows.map(\.amountText), accessory: EditCellStyle.accessoryWidth),
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
        var builder = RegisterRowBuilder(lookup: BudgetLookup(store.budget))
        builder.omitsYear = register.isTouch ? register.today().year : nil
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
        return [
            RegisterMenuItem(id: "title", title: menuTitle, kind: .title, isEnabled: false),
            .separator(0),
        ] + actionItems
    }

    var actionItems: [RegisterMenuItem] {
        let targets = moveTargets.map {
            RegisterMenuItem.action($0.name, .moveScheduled(accountId: $0.id))
        }
        return [
            .action(Self.enterTitle, .enterScheduledNow, enabled: canEnter(selectedIds)),
            .action(Self.skipTitle, .skipScheduled),
            .separator(1),
            .action(Self.deleteTitle, .deleteScheduled),
            .separator(2),
            RegisterMenuItem(id: "move", title: Self.moveTitle, kind: .submenu(targets), isEnabled: !targets.isEmpty),
        ]
    }

    public func canEnter(_ ids: some Sequence<String>) -> Bool {
        let budget = store.budget
        return ids.contains { budget.scheduledTransaction(withId: $0).map(budget.canEnter) ?? false }
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
        askToDelete(count: ids.count) { [weak self] in self?.perform(.deleteScheduledTransactions(ids)) }
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

    public func deleteEditedClicked() {
        guard let editor, editor.mode == .existing else { return }
        let id = editor.transactionId
        askToDelete(count: 1) { [weak self] in
            guard let editor = self?.editor, editor.transactionId == id else { return }
            editor.deleteClicked()
        }
    }

    /// Deleted schedules have no undo, so every way to delete one asks once.
    private func askToDelete(count: Int, then delete: @escaping @MainActor () -> Void) {
        dialogs.ask(
            TaskDialog<DeleteChoice>(
                instruction: count == 1 ? "Geplante Buchung löschen?" : "\(count) geplante Buchungen löschen?",
                content: count == 1 ? "Sie wird nicht mehr eingetragen." : "Sie werden nicht mehr eingetragen.",
                buttons: [.init(.cancel, title: "Abbrechen"), .init(.delete, title: "Löschen", isDefault: true)],
                dismissal: .cancel)
        ) { answer in
            if answer.choice == .delete { delete() }
        }
    }

    private var dialogs: DialogStack { register.dialogs }

    @discardableResult
    private func perform(_ command: BudgetCommand) -> Bool {
        register.perform(command)
    }
}

extension RegisterScheduler: RegisterGridOwner {
    package var mainGrid: RegisterViewModel? { nil }
    package var gridIds: [String] { scheduledIds }
    package var gridRows: [RegisterRow] { rows }
    package var columnTab: RegisterAnchorID { .schedulerColumnTab }
    /// Snapped, the reveal of its edit row would stop a point short of the row's end.
    package var snapsToRows: Bool { false }

    package func headerContextMenu() -> [RegisterMenuItem]? { nil }

    package func editorRecord(_ id: String) -> (transaction: Transaction, repeats: Repeat?)? {
        store.budget.scheduledTransaction(withId: id).map { ($0.editableTransaction, $0.repeats) }
    }

    /// Sorts by how far apart the occurrences lie, once first.
    private static func days(_ repeats: Repeat) -> Int {
        switch repeats {
        case .once: 0
        case .every(let count, .week): 7 * count
        case .every(let count, .month): 30 * count + 1
        }
    }

    package func followUpEdit(_ outcome: EditorOutcome) {
        if case .deleteRequested(let id) = outcome { perform(.deleteScheduledTransactions([id])) }
    }
}
