import AbakusCore
import CoreGraphics
import Foundation
import Observation

public struct RegisterScrollRequest: Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        case row(String)
        case top
        case bottom
        case offset(CGFloat)
    }

    public var target: Target
    public var token: Int
}

@MainActor
protocol RegisterGridOwner: AnyObject {
    var grid: RegisterGridController { get }
    /// The main grid's own parts: its cell actions (the layout decides which cells draw), popups, glow, focus.
    var mainGrid: RegisterViewModel? { get }
    var gridIds: [String] { get }
    var rows: [RegisterRow] { get }
    var visibleColumns: [RegisterColumn] { get }
    var expandedSplits: Set<String> { get set }
    var sortOrder: RegisterSortOrder { get set }
    var columnTab: RegisterAnchorID { get }
    var startsAtTop: Bool { get }
    var snapsToRows: Bool { get }
    /// The secondary-click menu of a row other than the edited one, nil when an edit or a modal swallows the click.
    func contextMenu(for row: RegisterRow) -> [RegisterMenuItem]?
    func headerContextMenu() -> [RegisterMenuItem]?
    func columnLayout(gridWidth: CGFloat) -> RegisterColumnLayout
    func columnOptionsClicked()
    func deleteKeyPressed()
    func editorRecord(_ id: String) -> (transaction: Transaction, frequency: ScheduledTransactionFrequency?)?
    func followUpEdit(_ outcome: EditorOutcome)
}

@MainActor
@Observable
final class RegisterGridController {
    unowned let register: RegisterViewModel
    let store: any BudgetStoring
    let navigation: NavigationState
    let newFrequency: ScheduledTransactionFrequency?
    @ObservationIgnored weak var owner: (any RegisterGridOwner)?
    @ObservationIgnored weak var peer: RegisterGridController?
    private var storedSelection = (visit: -1, selection: RegisterSelection())
    private var storedEditor: (visit: Int, editor: TransactionEditor)?
    private var storedScrollRequest: (visit: Int, request: RegisterScrollRequest)?
    /// The date of the last new record saved in this grid.
    var lastUsedDate: DateWithoutTime?

    init(register: RegisterViewModel, newFrequency: ScheduledTransactionFrequency? = nil) {
        self.register = register
        store = register.store
        navigation = register.navigation
        self.newFrequency = newFrequency
    }

    private var ids: [String] { owner?.gridIds ?? [] }
    var acceptsKeys: Bool { register.acceptsRegisterKeys }

    var selection: RegisterSelection {
        guard storedSelection.visit == navigation.visit else { return RegisterSelection() }
        var selection = storedSelection.selection
        selection.retain(Set(ids))
        return selection
    }

    var selectedIds: [String] { selection.ordered(by: ids) }

    /// Only one grid holds a selection.
    func updateSelection(_ update: (inout RegisterSelection) -> Void) {
        var selection = self.selection
        update(&selection)
        selection.rememberCaretIndex(in: ids)
        storedSelection = (navigation.visit, selection)
        if !selection.isEmpty { peer?.clearSelection() }
    }

    func clearSelection() {
        updateSelection { $0.clear() }
    }

    /// Returns whether the grid takes keyboard focus; an edit that swallowed the click keeps it.
    @discardableResult
    func rowClicked(_ id: String, column: RegisterColumn?, modifiers: RegisterClickModifiers) -> Bool {
        if swallowsClick(on: id) { return false }
        var result = RegisterSelection.ClickResult.selectionChanged
        let order = ids
        updateSelection { result = $0.click(id, modifiers: modifiers, order: order) }
        if result == .beginEdit { beginEditing(id, column: column) }
        return !hasOpenEdit
    }

    func headerClicked(_ column: RegisterColumn) {
        guard !swallowsClick(), let owner, column.isSortable else { return }
        owner.sortOrder = owner.sortOrder.clicked(column)
        if let first = selectedIds.first { requestScroll(.row(first)) }
    }

    func toggleSplit(_ id: String) {
        guard !swallowsClick(), let owner else { return }
        if owner.expandedSplits.contains(id) {
            owner.expandedSplits.remove(id)
        } else {
            owner.expandedSplits.insert(id)
        }
    }

    private func moveSelection(by offset: Int, extending: Bool, caretOnly: Bool = false) -> String? {
        guard acceptsKeys, editor == nil else { return nil }
        let ids = ids
        var target: String?
        updateSelection { target = $0.moveCaret(by: offset, extending: extending, caretOnly: caretOnly, order: ids) }
        return target
    }

    @discardableResult
    func navigationKeyPressed(_ key: RegisterNavigationKey, extending: Bool, caretOnly: Bool, pageRows: Int)
        -> String?
    {
        let count = ids.count
        let offset =
            switch key {
            case .up: -1
            case .down: 1
            case .pageUp: -max(1, pageRows)
            case .pageDown: max(1, pageRows)
            case .home: -count
            case .end: count
            }
        return moveSelection(by: offset, extending: extending, caretOnly: caretOnly)
    }

    /// The open editor; switching the account or budget drops it silently.
    var editor: TransactionEditor? {
        guard let storedEditor, storedEditor.visit == navigation.visit else { return nil }
        return storedEditor.editor
    }

    /// Only the frequency field has no AppKit input to take the arrows; other fields' arrows wait for theirs.
    func editorArrowPressed(_ key: EditorKey) -> Bool {
        guard let editor, editor.focus == .field(.main(.frequency)) else { return false }
        return editor.handleKey(key)
    }

    var editingId: String? {
        editor.flatMap { $0.mode == .existing ? $0.transactionId : nil }
    }

    var isAdding: Bool { editor?.mode == .new }

    /// An edit in this grid or in its peer keeps the keyboard focus.
    var hasOpenEdit: Bool { editor != nil || peer?.editor != nil }

    var editRowExtraHeight: CGFloat {
        guard let editor, editor.mode == .existing else { return 0 }
        return editor.rowHeight - RegisterMetrics.rowHeight
    }

    /// The list's secondary-click menu at `y` in the viewport: nil hands the click on (to the edited row's fields,
    /// or below the rows), an empty menu takes it.
    func contextMenu(atY y: CGFloat, scrollOffset: CGFloat) -> [RegisterMenuItem]? {
        guard let owner,
            let row = Self.row(
                atY: y, in: owner.rows, scrollOffset: scrollOffset, editingId: editingId,
                editRowExtraHeight: editRowExtraHeight),
            row.transactionId != editingId
        else { return nil }
        return owner.contextMenu(for: row) ?? []
    }

    static func row(
        atY y: CGFloat, in rows: [RegisterRow], scrollOffset: CGFloat, editingId: String?, editRowExtraHeight: CGFloat
    ) -> RegisterRow? {
        var top = -scrollOffset
        for row in rows {
            let height = RegisterMetrics.rowHeight + (row.id == editingId ? editRowExtraHeight : 0)
            if y >= top && y < top + height { return row }
            top += height
        }
        return nil
    }

    func clickedOutsideEditor() -> Bool {
        editor?.clickedOutside() ?? false
    }

    /// An edit in either grid glows or ends first, then the click takes the selection.
    func swallowsClick(on id: String? = nil) -> Bool {
        if let editor, id == nil || id != editingId, editor.clickedOutside() { return true }
        if peer?.clickedOutsideEditor() == true { return true }
        peer?.clearSelection()
        return false
    }

    func beginEditing(_ id: String, column: RegisterColumn? = nil) {
        if let editor {
            guard editor.mode == .new, !editor.clickedOutside() else { return }
        }
        guard let record = owner?.editorRecord(id) else { return }
        updateSelection { $0.select(id) }
        if record.transaction.isSplit { owner?.expandedSplits.remove(id) }
        let editor = makeEditor(record.transaction, frequency: record.frequency, mode: .existing)
        let target = column.flatMap(EditorColumn.init) ?? .date
        let field = EditorFieldID.main(editor.mainColumns().contains(target) ? target : .date)
        editor.setFocus(.field(field), commitCurrent: false)
        requestScroll(.row(id))
    }

    func editSelected() {
        guard acceptsKeys, !hasOpenEdit, selection.count == 1, let id = selectedIds.first else { return }
        beginEditing(id)
    }

    func beginNew(transfer: Bool = false, accountId: String? = nil, date: DateWithoutTime? = nil) {
        if peer?.clickedOutsideEditor() == true { return }
        if let editor, editor.mode == .new || editor.clickedOutside() { return }
        let budget = store.budget
        guard
            let account = register.account ?? accountId.flatMap(budget.account(withId:))
                ?? budget.accounts(in: .budgetAccounts).first ?? budget.accounts(in: .offBudgetAccounts).first
        else { return }
        clearSelection()
        let transaction = Transaction(
            accountId: account.id, date: date ?? lastUsedDate ?? register.today(), amount: 0)
        let editor = makeEditor(transaction, frequency: newFrequency, mode: .new)
        if transfer {
            editor.startTransfer()
        } else {
            editor.setFocus(.field(.main(.date)), commitCurrent: false)
        }
        requestScroll(.bottom)
    }

    func cancelEditing() {
        storedEditor?.editor.cancel()
        storedEditor = nil
    }

    private func makeEditor(_ transaction: Transaction, frequency: ScheduledTransactionFrequency?, mode: EditorMode)
        -> TransactionEditor
    {
        let editor = TransactionEditor(
            store: store, transaction: transaction, mode: mode, columns: owner?.visibleColumns ?? [],
            isAllAccounts: register.isAllAccounts, today: register.today(), frequency: frequency,
            dialogs: register.dialogs)
        editor.onFinish = { [weak self, weak editor] outcome in
            guard let self, let editor else { return }
            self.editorFinished(editor, outcome)
        }
        editor.onEditPayees = { [weak register] name in register?.onEditPayees(name) }
        editor.autoFillSettings = register.autoFillSettings
        storedEditor = (navigation.visit, editor)
        return editor
    }

    private func editorFinished(_ editor: TransactionEditor, _ outcome: EditorOutcome) {
        guard storedEditor?.editor === editor else { return }
        storedEditor = nil
        if case .saved(let id, let addAnother, _, _) = outcome {
            updateSelection { $0.select(id) }
            let saved = owner?.editorRecord(id)?.transaction
            if editor.mode == .new {
                lastUsedDate = saved?.date
                requestScroll(.bottom)
            } else {
                requestScroll(.row(id))
            }
            if addAnother, let saved { beginNew(accountId: saved.accountId, date: saved.date) }
        }
        owner?.followUpEdit(outcome)
    }

    /// A request the grid of this visit still has to follow, also when it appears after the request.
    var scrollRequest: RegisterScrollRequest? {
        get { storedScrollRequest.flatMap { $0.visit == navigation.visit ? $0.request : nil } }
        set { storedScrollRequest = newValue.map { (navigation.visit, $0) } }
    }

    func requestScroll(_ target: RegisterScrollRequest.Target) {
        scrollRequest = RegisterScrollRequest(target: target, token: (storedScrollRequest?.request.token ?? 0) + 1)
    }

    /// The offset that shows `target`, nil while its row is in view; without `current` the list starts at its edge.
    /// An edit row taller than the viewport fills it and keeps its focused part in view.
    func scrollOffset(for target: RegisterScrollRequest.Target, viewport: CGFloat, current: CGFloat?) -> CGFloat? {
        let rows = owner?.rows ?? []
        let extra = editRowExtraHeight
        let maxOffset = max(0, listContentHeight(viewport: viewport) - viewport)
        switch target {
        case .top:
            return 0
        case .bottom:
            return maxOffset
        case .offset(let offset):
            return min(maxOffset, offset)
        case .row(let id):
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
            let current = current ?? (owner?.startsAtTop == true ? 0 : maxOffset)
            let top = CGFloat(index) * RegisterMetrics.rowHeight
            if id == editingId, let editor, editor.rowHeight > viewport {
                var offset = min(max(current, top), top + editor.rowHeight - viewport)
                if let focused = editor.focusedRange {
                    offset = min(max(offset, top + focused.upperBound - viewport), top + focused.lowerBound)
                }
                let revealed = revealOffset(offset, from: current, maxOffset: maxOffset)
                return revealed == current ? nil : revealed
            }
            let height = RegisterMetrics.rowHeight + (id == editingId ? extra : 0)
            if top < current { return top }
            if top + height > current + viewport {
                return revealOffset(top + height - viewport, from: current, maxOffset: maxOffset)
            }
            return nil
        }
    }

    /// Row snapping rounds to the nearest row, which could cut the revealed row; rounding away from it keeps it whole.
    private func revealOffset(_ offset: CGFloat, from current: CGFloat, maxOffset: CGFloat) -> CGFloat {
        guard owner?.snapsToRows == true else { return min(maxOffset, offset) }
        let rows = (offset / RegisterMetrics.rowHeight).rounded(offset > current ? .up : .down)
        return min(maxOffset, rows * RegisterMetrics.rowHeight)
    }

    func listContentHeight(viewport: CGFloat) -> CGFloat {
        registerListContentHeight(
            rowCount: owner?.rows.count ?? 0, viewportHeight: viewport, extraHeight: editRowExtraHeight)
    }

    /// A list that fits keeps the edge its grid starts at.
    func keepsEnd(_ list: ScrollMetrics) -> Bool {
        list.isAtEnd && (list.canScroll || owner?.startsAtTop != true)
    }

    func scrollMetrics(at offset: CGFloat, viewport: CGFloat) -> ScrollMetrics {
        let content = listContentHeight(viewport: viewport)
        let maxOffset = max(0, content - viewport)
        let offset =
            owner?.snapsToRows == true
            ? Self.snappedOffset(offset, maxOffset: maxOffset) : min(maxOffset, max(0, offset))
        return ScrollMetrics(offset: offset, contentHeight: content, viewportHeight: viewport)
    }

    func scrollMetrics(revealing target: RegisterScrollRequest.Target, from list: ScrollMetrics, viewport: CGFloat)
        -> ScrollMetrics?
    {
        scrollOffset(for: target, viewport: viewport, current: list.offset).map {
            scrollMetrics(at: $0, viewport: viewport)
        }
    }

    /// An open edit then keeps its row in view.
    func scrollMetrics(afterResizing list: ScrollMetrics, to viewport: CGFloat) -> ScrollMetrics {
        let maxOffset = max(0, listContentHeight(viewport: viewport) - viewport)
        var offset = keepsEnd(list) ? maxOffset : min(maxOffset, list.offset)
        if editor != nil, let request = scrollRequest,
            let revealed = scrollOffset(for: request.target, viewport: viewport, current: offset)
        {
            offset = revealed
        }
        return scrollMetrics(at: offset, viewport: viewport)
    }

    /// Within a row of the end lands on the end: a list resizing at its end passes through such offsets.
    nonisolated static func snappedOffset(_ offset: CGFloat, maxOffset: CGFloat) -> CGFloat {
        let row = RegisterMetrics.rowHeight
        guard offset <= maxOffset - row else { return maxOffset }
        return min(maxOffset, max(0, (offset / row).rounded() * row))
    }

    func addRowPlacement(gridHeight: CGFloat) -> RegisterAddRowPlacement {
        RegisterAddRowPlacement.compute(
            gridHeight: gridHeight, rowCount: owner?.rows.count ?? 0, extraHeight: editRowExtraHeight,
            editorHeight: isAdding ? editor?.rowHeight ?? 0 : 0)
    }
}
