import AbakusCore
import Foundation

extension BudgetCalloutController {
    public func summaryRowClicked(_ row: TransactionSummaryRow) {
        close()
        onShowTransaction(row.transactionId)
    }

    public func showInAccountViewClicked() {
        guard let filter = summary?.accountView else { return }
        close()
        onShowInAccountView(filter)
    }

    public func summaryClosed() {
        close()
    }
}
