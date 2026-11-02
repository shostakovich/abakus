import AbakusCore
import Foundation

public struct RegisterAdjustmentHelp: Hashable, Sendable {
    public var transactionId: String
    public var message: String
}

extension RegisterViewModel {
    public var adjustmentHelp: RegisterAdjustmentHelp? {
        guard let slot = adjustmentHelpSlot, slot.visit == navigation.visit else { return nil }
        return slot.help
    }

    /// Alle Konten stays, every other view switches to the transaction's account.
    func showAdjustment(_ help: RegisterAdjustmentHelp) {
        guard let transaction = store.budget.transaction(withId: help.transactionId) else { return }
        if !isAllAccounts { navigation.selection = .account(transaction.accountId) }
        reveal(transaction.id)
        adjustmentHelpSlot = (navigation.visit, help)
    }

    public func adjustmentHelpDismissed() {
        adjustmentHelpSlot = nil
    }
}
