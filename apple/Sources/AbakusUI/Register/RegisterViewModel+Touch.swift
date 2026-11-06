import AbakusCore
import Foundation

/// Touch screens select with "Auswählen" in "Ansicht" instead of ⌘-click and act on rows they name.
extension RegisterViewModel {
    public var isPicking: Bool { pickingVisit == navigation.visit }

    func togglePicking() {
        if isPicking {
            pickingVisit = nil
            clearSelection()
        } else {
            pickingVisit = navigation.visit
        }
    }

    public var isAllSelected: Bool { !transactionIds.isEmpty && selection.count == transactionIds.count }

    func toggleSelectAll() {
        if isAllSelected { clearSelection() } else { selectAll() }
    }

    /// A list's selection replaces the register's.
    public func setSelection(_ ids: Set<String>) {
        let order = transactionIds
        updateSelection { selection in
            selection.clear()
            for id in order where ids.contains(id) { selection.toggle(id) }
        }
    }

    /// Every item has a symbol, so the shown view's check mark and the icons share one leading edge.
    public func touchViewMenu(showsColumns: Bool) -> [RegisterMenuItem] {
        var items: [RegisterMenuItem] = []
        if !isReconciling {
            items = RegisterFilter.allCases.map {
                .action($0.title, .filter($0), checked: $0 == filter, systemImage: $0.touchSymbol)
            }
            items.append(.separator(10))
            items += schedulerMenu(systemImage: "calendar.badge.clock")
        }
        items.append(
            .action(isPicking ? "Auswählen beenden" : "Auswählen", .togglePicking, systemImage: "checkmark.circle"))
        if showsColumns {
            let isMemoShown = !hiddenColumns.contains(.memo)
            items.append(
                .action(
                    isMemoShown ? "Memo ausblenden" : "Memo zeigen", .toggleColumn(.memo), systemImage: "text.alignleft"
                ))
        }
        let closed = closedAccountsMenu.touchLabels.map { item in
            var item = item
            item.systemImage = "archivebox"
            return item
        }
        if !closed.isEmpty { items += [.separator(11)] + closed }
        if account != nil {
            items.append(.separator(11))
            items.append(.action("Konto bearbeiten", .editAccount, systemImage: "pencil"))
        }
        return items
    }

    public func transactionActionsMenu(for ids: Set<String>) -> [RegisterMenuItem] {
        transactionActionsMenu(of: transactions.filter { ids.contains($0.id) }).touchLabels
    }

    /// The rows a context menu or a swipe named become the selection, as a right-click makes them on the Mac.
    public func performMenuAction(_ action: RegisterMenuAction, on ids: Set<String>) {
        setSelection(ids)
        performMenuAction(action)
    }

    /// The Konten list shows Alle Konten in the view Zu bestätigen.
    public func showApprovals() {
        showAllAccounts(in: .unapproved)
    }

    public var approvalCount: Int { store.budget.approvalCount }

    public nonisolated static func approvalsTitle(_ count: Int) -> String {
        transactionCount(count) + " bestätigen"
    }

    /// The view Zu bestätigen's line above the list; it counts what „Alle bestätigen“ approves.
    public var approvalsLine: String? {
        guard filter == .unapproved, !transactions.isEmpty else { return nil }
        let count = transactions.count
        return count == 1 ? "1 Buchung wartet auf Bestätigung." : "\(count) Buchungen warten auf Bestätigung."
    }

    private nonisolated static func transactionCount(_ count: Int) -> String {
        count == 1 ? "1 Buchung" : "\(count) Buchungen"
    }

    public static let approveAllTitle = "Alle bestätigen"

    public func approveAllClicked() {
        guard approvalsLine != nil, !grid.clickedOutsideEditor() else { return }
        perform(.approveTransactions(transactionIds))
    }

    public var pickingActions: RegisterPickingActions {
        let ids = Set(selectedTransactionIds)
        let menu = transactionActionsMenu(for: ids)
        let canDelete = menu.contains { $0.isEnabled && $0.kind == .action(.delete) }
        return RegisterPickingActions(
            ids: ids, categories: ids.isEmpty || !canCategorize ? [] : categorizeItems, canDelete: canDelete,
            menu: menu)
    }

    /// What tapping a row's status does: approve it while it waits, else switch between vorgemerkt and gebucht.
    public func statusAction(for row: RegisterRow) -> RegisterStatusAction {
        if row.errorLevel == .forReview { return .approve }
        switch row.cleared {
        case .uncleared: return .markCleared
        case .cleared: return .markUncleared
        case .reconciled: return .unlock
        }
    }

    public func statusTapped(_ row: RegisterRow) {
        setSelection([row.transactionId])
        guard statusAction(for: row) != .approve else {
            perform(.approveTransactions([row.transactionId]))
            return
        }
        clearedClicked(row)
    }
}

extension RegisterFilter {
    fileprivate var touchSymbol: String {
        switch self {
        case .all: "list.bullet"
        case .unapproved: "checkmark.seal"
        case .uncleared: "clock"
        case .needsCategory: "tag.slash"
        }
    }
}

extension Budget {
    var approvalCount: Int { notifierCounts(forAccount: EntityID.allAccounts).unapproved }
}

public struct RegisterPickingActions: Hashable, Sendable {
    public let ids: Set<String>
    /// Empty while nothing is picked or the account is outside the budget.
    public let categories: [RegisterMenuItem]
    public let canDelete: Bool
    public let menu: [RegisterMenuItem]
}

public enum RegisterStatusAction: Hashable, Sendable {
    case approve, markCleared, markUncleared, unlock

    public var title: String {
        switch self {
        case .approve: "Bestätigen"
        case .markCleared: "Gebucht"
        case .markUncleared: "Vorgemerkt"
        case .unlock: "Entsperren"
        }
    }
}
