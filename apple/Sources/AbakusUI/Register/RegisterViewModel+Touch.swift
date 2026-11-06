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

    /// Short labels with a symbol and the state as subtitle, as a checkmark's column would make them wrap.
    public func touchViewMenu(showsColumns: Bool) -> [RegisterMenuItem] {
        var items: [RegisterMenuItem] = []
        if !isReconciling {
            items += [
                .action("Zeitraum", .timeframe, systemImage: "calendar", subtitle: search.dateSelectorTitle),
                .action(
                    Self.touchReconciledTitle, .showReconciled, enabled: isReconciledFilterEnabled,
                    systemImage: "lock", subtitle: isShowingReconciled ? "Gezeigt" : "Ausgeblendet"),
                .separator(10),
            ]
        }
        items += [
            .action(isPicking ? "Auswählen beenden" : "Auswählen", .togglePicking, systemImage: "checkmark.circle"),
            .action(
                isAllSelected ? "Auswahl aufheben" : "Alle auswählen", .toggleSelectAll,
                enabled: !transactionIds.isEmpty, systemImage: "checklist"),
        ]
        if showsColumns {
            let columns = columnMenuItems.filter { $0.column != .cleared }.map {
                RegisterMenuItem.action($0.label, .toggleColumn($0.column), checked: $0.isChecked)
            }
            items.append(
                RegisterMenuItem(
                    id: "columns", title: "Spalten", kind: .submenu(columns), systemImage: "tablecells"))
        }
        return items
    }

    public static let touchReconciledTitle = "Abgeglichene"

    public func transactionActionsMenu(for ids: Set<String>) -> [RegisterMenuItem] {
        transactionActionsMenu(of: transactions.filter { ids.contains($0.id) }, withTitle: false)
    }

    /// The rows a context menu or a swipe named become the selection, as a right-click makes them on the Mac.
    public func performMenuAction(_ action: RegisterMenuAction, on ids: Set<String>) {
        setSelection(ids)
        performMenuAction(action)
    }

    public static let approvalSearch = "Ist: Erinnerung"

    /// The chip and the Konten tab both show Alle Konten filtered to what waits for approval.
    public func showApprovals() {
        showAllAccounts(searching: Self.approvalSearch)
    }

    public var isShowingApprovals: Bool { isAllAccounts && search.filter?.label == Self.approvalSearch }

    public var approvalCount: Int { store.budget.approvalCount }

    public nonisolated static func approvalsTitle(_ count: Int) -> String {
        transactionCount(count) + " bestätigen"
    }

    /// The header's line while the approvals show; it counts what "Alle bestätigen" approves.
    public var approvalsLine: String? {
        let count = transactions.filter(\.needsApproval).count
        return count == 0 ? nil : Self.transactionCount(count) + " zu bestätigen"
    }

    private nonisolated static func transactionCount(_ count: Int) -> String {
        count == 1 ? "1 Buchung" : "\(count) Buchungen"
    }

    public func approveAllClicked() {
        let ids = Set(transactions.filter(\.needsApproval).map(\.id))
        guard isShowingApprovals, !ids.isEmpty else { return }
        performMenuAction(.approve, on: ids)
    }

    public var pickingActions: RegisterPickingActions {
        let ids = Set(selectedTransactionIds)
        let menu = transactionActionsMenu(for: ids)
        let enabled = Set(
            menu.compactMap { item -> RegisterMenuAction? in
                guard item.isEnabled, case .action(let action) = item.kind else { return nil }
                return action
            })
        let status: RegisterMenuAction =
            if enabled.contains(.approve) {
                .approve
            } else if enabled.contains(.markUncleared) && !enabled.contains(.markCleared) {
                .markUncleared
            } else {
                .markCleared
            }
        return RegisterPickingActions(
            ids: ids, status: status, isStatusEnabled: enabled.contains(status),
            categories: ids.isEmpty || !canCategorize ? [] : categorizeItems, canDelete: enabled.contains(.delete),
            menu: menu)
    }

    /// What tapping a row's status does: approve it while it waits, else switch between vorgemerkt and gebucht.
    public func statusAction(for row: RegisterRow) -> RegisterMenuAction? {
        if row.errorLevel == .forReview { return .approve }
        switch row.cleared {
        case .uncleared: return .markCleared
        case .cleared: return .markUncleared
        case .reconciled: return nil
        }
    }
}

/// Touch screens show the approval search as a token, "Zu bestätigen", in front of what else is typed.
extension RegisterSearchController {
    public nonisolated static let approvalTokenTitle = "Zu bestätigen"

    private static var approvalHead: String { RegisterViewModel.approvalSearch + ", " }

    public var showsApprovalToken: Bool {
        text.hasPrefix(Self.approvalHead) || Self.committedText(text) == RegisterViewModel.approvalSearch
    }

    private static let transferMark = "⇄ "

    /// What the box shows beside the token, a transfer by its account.
    public var textBesideTokens: String {
        let rest = showsApprovalToken ? String(text.dropFirst(min(text.count, Self.approvalHead.count))) : text
        return rest.replacingOccurrences(of: Payee.transferPrefix, with: Self.transferMark)
    }

    public func tokenBoxChanged(_ typed: String) {
        let typed = typed.replacingOccurrences(of: Self.transferMark, with: Payee.transferPrefix)
        boxChanged(showsApprovalToken ? Self.approvalHead + typed : typed)
    }

    public func approvalTokenRemoved() {
        guard showsApprovalToken else { return }
        text = textBesideTokens
        commit(focusingGrid: false)
    }

    /// A search term as the touch screens write it: a transfer by its account, the approval search as its token.
    public static func touchText(_ text: String) -> String {
        text.replacingOccurrences(of: RegisterViewModel.approvalSearch, with: approvalTokenTitle)
            .replacingOccurrences(of: Payee.transferPrefix, with: transferMark)
    }

    /// What the typed text matches, then where else to look for it; hints and duplicates stay away.
    public var touchSuggestionGroups: [RegisterTouchSuggestionGroup] {
        var seen = Set<String>()
        let rows = (dropDown?.items ?? []).enumerated().compactMap { index, item -> RegisterTouchSuggestion? in
            guard !item.searchText.isEmpty, !item.isBlank, seen.insert(item.searchText).inserted else { return nil }
            return RegisterTouchSuggestion(index: index, item: item)
        }
        return [
            RegisterTouchSuggestionGroup(title: "Vorschläge", rows: rows.filter { !$0.isScope }),
            RegisterTouchSuggestionGroup(title: "„\(currentTerm)“ suchen in", rows: rows.filter(\.isScope)),
        ]
        .filter { !$0.rows.isEmpty }
    }
}

extension Budget {
    var approvalCount: Int { notifierCounts(forAccount: EntityID.allAccounts).forReview }
}

public struct RegisterPickingActions: Hashable, Sendable {
    public let ids: Set<String>
    public let status: RegisterMenuAction
    public let isStatusEnabled: Bool
    /// Empty while nothing is picked or the account is outside the budget.
    public let categories: [RegisterMenuItem]
    public let canDelete: Bool
    public let menu: [RegisterMenuItem]

    public var deleteQuestion: String {
        ids.count == 1 ? "Buchung löschen?" : "\(ids.count) Buchungen löschen?"
    }
}

extension RegisterMenuAction {
    public var statusTitle: String {
        switch self {
        case .approve: "Bestätigen"
        case .markCleared: "Gebucht"
        case .markUncleared: "Vorgemerkt"
        default: ""
        }
    }
}

public struct RegisterTouchSuggestionGroup: Hashable, Sendable {
    public let title: String
    public let rows: [RegisterTouchSuggestion]
}

public struct RegisterTouchSuggestion: Hashable, Sendable, Identifiable {
    public let index: Int
    public let id: String
    public let field: String
    public let value: String
    public let isTransfer: Bool
    public let isScope: Bool

    init(index: Int, item: RegisterSearchSuggestion) {
        self.index = index
        id = item.id
        isScope = item.isScope
        let field = item.prefix.trimmingCharacters(in: .whitespaces)
        let plain = TextMarkup.plain(item.description)
        isTransfer = Payee.isTransferPayeeName(plain)
        if isScope {
            self.field = field.isEmpty ? "Allen Feldern" : String(field.dropLast())
        } else {
            self.field = field
        }
        if item.isReminder {
            value = RegisterSearchController.approvalTokenTitle
        } else {
            value = isTransfer ? (Payee.transferTargetAccountName(plain) ?? plain) : plain
        }
    }
}
