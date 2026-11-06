import AbakusCore
import Foundation

public struct StatusPopupOption: Identifiable, Hashable, Sendable {
    public enum Command: Hashable, Sendable { case removeCategory }

    public var command: Command
    public var title: String

    public var id: Command { command }
}

extension RegisterViewModel {
    func showStatusPopup(for row: RegisterRow) {
        guard row.transactionId != editingTransactionId else { return }
        switch row.errorLevel {
        case .forReview:
            popup = nil
            perform(.approveTransactions([row.transactionId]))
        case .needsCategory: popup = .needsCategory(rowId: row.id)
        case .error: popup = .removeCategory(rowId: row.id)
        case .none: popup = nil
        }
    }

    /// The selected rows at the clicked row's level; the popups act on these.
    var statusPopupTransactions: [Transaction] {
        let level: ErrorLevel
        switch popup {
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
        let single = statusPopupTransactions.count == 1
        switch popup {
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
        let ids = statusPopupTransactions.map(\.id)
        popup = nil
        switch command {
        case .removeCategory: perform(.removeTransferCategories(ids))
        }
    }

    public func needsCategoryChosen(_ categoryId: String) {
        let ids = statusPopupTransactions.map(\.id)
        popup = nil
        perform(.fillMissingCategory(ids, categoryId: categoryId))
    }
}
