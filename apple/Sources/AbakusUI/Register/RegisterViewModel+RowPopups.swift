import AbakusCore
import Foundation

public struct RunningBalanceInfo: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        public var amount: String
        public var caption: String
    }

    public var title: String
    public var lines: [Line]
}

public struct StatusPopupOption: Identifiable, Hashable, Sendable {
    public enum Command: Hashable, Sendable { case approve, delete, removeCategory }

    public var command: Command
    public var title: String
    public var systemImage: String?

    public var id: Command { command }
}

extension RegisterViewModel {
    func showStatusPopup(for row: RegisterRow) {
        guard row.transactionId != editingTransactionId else { return }
        switch row.errorLevel {
        case .forReview: popup = .approveReject(rowId: row.id)
        case .needsCategory: popup = .needsCategory(rowId: row.id)
        case .error: popup = .removeCategory(rowId: row.id)
        case .none: popup = nil
        }
    }

    /// The selected rows at the clicked row's level; the popups act on these.
    var statusPopupTransactions: [Transaction] {
        let level: ErrorLevel
        switch popup {
        case .approveReject: level = .forReview
        case .needsCategory: level = .needsCategory
        case .removeCategory: level = .error
        default: return []
        }
        let budget = store.budget
        return selectedTransactions.filter { budget.errorState(of: $0).level == level }
    }

    public var statusPopupTitle: String {
        let count = statusPopupTransactions.count
        switch popup {
        case .approveReject:
            return count == 1 ? "1 ausgewählte unbestätigte Buchung" : "\(count) ausgewählte unbestätigte Buchungen"
        case .needsCategory:
            return count == 1
                ? "Kategorie für die ausgewählte Buchung wählen"
                : "Kategorie für \(count) ausgewählte Buchungen wählen"
        case .removeCategory:
            return count == 1 ? "1 ausgewählte Umbuchung" : "\(count) ausgewählte Umbuchungen"
        default:
            return ""
        }
    }

    public var statusPopupOptions: [StatusPopupOption] {
        let transactions = statusPopupTransactions
        let single = transactions.count == 1
        switch popup {
        case .approveReject:
            let approve = StatusPopupOption(
                command: .approve, title: single ? "Buchung bestätigen" : "Buchungen bestätigen",
                systemImage: EditorButton.approve.systemImage)
            let led = store.budget.ledTransactionIds
            guard transactions.contains(where: { !led.contains($0.id) }) else { return [approve] }
            return [
                approve,
                StatusPopupOption(
                    command: .delete, title: single ? "Buchung löschen" : "Buchungen löschen",
                    systemImage: EditorButton.delete.systemImage),
            ]
        case .removeCategory:
            return [
                StatusPopupOption(
                    command: .removeCategory, title: single ? "Kategorie entfernen" : "Kategorien entfernen")
            ]
        default:
            return []
        }
    }

    public func statusPopupChosen(_ command: StatusPopupOption.Command) {
        let transactions = statusPopupTransactions
        let ids = transactions.map(\.id)
        popup = nil
        switch command {
        case .approve: perform(.approveTransactions(ids))
        case .delete: deleteTransactions(ids)
        case .removeCategory: perform(.removeTransferCategories(ids))
        }
    }

    public func needsCategoryChosen(_ categoryId: String) {
        let ids = statusPopupTransactions.map(\.id)
        popup = nil
        perform(.fillMissingCategory(ids, categoryId: categoryId))
    }

    public func runningBalanceHovered(_ row: RegisterRow, inside: Bool) {
        if inside {
            guard popup == nil, row.transactionId != editingTransactionId, !row.isSubtransaction else { return }
            popup = .runningBalance(rowId: row.id)
        } else if popup == .runningBalance(rowId: row.id) {
            popup = nil
        }
    }

    public func runningBalanceInfo(for rowId: String) -> RunningBalanceInfo? {
        guard let transaction = store.budget.transaction(withId: rowId) else { return nil }
        let balances = store.budget.balances(forAccount: accountKey ?? "", through: transaction.date)
        let date = formatter.dateShort(transaction.date)
        let uncleared = balances.uncleared
        let working = balances.working
        return RunningBalanceInfo(
            title: "Saldo bis \(date):",
            lines: [
                .init(
                    amount: formatter.currency(Amount.round(working - uncleared)),
                    caption: "Gebucht (der Saldo der Bank am \(date))"),
                .init(
                    amount: formatter.currency(uncleared),
                    caption: "Vorgemerkt (Buchungen, die die Bank noch nicht kennt)"),
                .init(
                    amount: formatter.currency(working), caption: "Arbeitssaldo (das Geld, das am \(date) da war)"),
            ])
    }
}
