import AbakusCore
import CoreGraphics
import Foundation

public struct RegisterIncomeCheck: Hashable, Sendable {
    public var transactionId: String

    public static let title = "Kurz nachgefragt"
    public static let message =
        "Diese Buchung geht an <b>Zu verteilen</b>,<br/>ist aber ein <b>Ausgang</b> statt ein <b>Eingang</b>."
    public static let swapTitle = "Ja, das ist ein Eingang"
    public static let keepTitle = "Nein, Ausgang lassen"
}

extension RegisterViewModel: RegisterGridOwner {
    var mainGrid: RegisterViewModel? { self }
    var gridIds: [String] { transactionIds }
    var columnTab: RegisterAnchorID { .columnTab }
    var startsAtTop: Bool { false }
    var snapsToRows: Bool { true }

    func editorRecord(_ id: String) -> (transaction: Transaction, frequency: ScheduledTransactionFrequency?)? {
        store.budget.transaction(withId: id).map { ($0, nil) }
    }

    func followUpEdit(_ outcome: EditorOutcome) {
        switch outcome {
        case .cancelled:
            break
        case .deleteRequested(let id):
            deleteTransactions([id])
        case .saved(let id, let addAnother, let findNext, let incomeCheck):
            if incomeCheck { self.incomeCheck = RegisterIncomeCheck(transactionId: id) }
            if findNext && !addAnother { editNextUnapproved(after: id) }
        }
    }
}

extension RegisterViewModel {
    public var editor: TransactionEditor? { grid.editor }

    public var editingTransactionId: String? { grid.editingId }

    public func beginEditing(_ id: String, column: RegisterColumn? = nil) {
        grid.beginEditing(id, column: column)
    }

    /// The next transaction needing approval, wrapping around.
    private func editNextUnapproved(after id: String) {
        let order = transactions
        guard let start = order.firstIndex(where: { $0.id == id }) else { return }
        let budget = store.budget
        for offset in 1..<max(order.count, 1) {
            let candidate = order[(start + offset) % order.count]
            if budget.errorState(of: candidate).level == .forReview {
                beginEditing(candidate.id)
                return
            }
        }
    }

    /// An edit whose record a filter or a command took away ends silently.
    func endEditsOvertakenByChanges() {
        if let id = editingTransactionId, !transactionIds.contains(id) { editor?.cancel() }
        scheduler.endEditIfOvertaken()
    }

    func requestScroll(_ target: RegisterScrollRequest.Target) {
        grid.requestScroll(target)
    }

    public func incomeCheckAnswered(swap: Bool) {
        guard let check = incomeCheck else { return }
        incomeCheck = nil
        guard swap, var transaction = store.budget.transaction(withId: check.transactionId) else { return }
        transaction.amount = -transaction.amount
        perform(.updateTransaction(transaction))
    }
}
