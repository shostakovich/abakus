import AbakusCore
import Foundation

public struct BudgetOutflowHelp: Hashable, Sendable {
    public static let title = "So trägst du eine Ausgabe ein"
    public static let checkbox = "Nicht mehr zeigen"

    public let message: String
}

extension BudgetCalloutController {
    func outflowHelp(month: DateWithoutTime, categoryId: String) -> BudgetOutflowHelp? {
        let isMaster = budget.groups.contains { $0.id == categoryId }
        let source: OutflowSummarySource = isMaster ? .masterCategory(categoryId) : .category(categoryId)
        let summary = store.budget.outflowSummary(source, month: month, today: budget.today, formatter: formatter)
        return summary.emptyOutflowHelp.map(BudgetOutflowHelp.init)
    }

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

    public func dontShowOutflowHelpAgainClicked() {
        budget.showsEmptyOutflowHelp = false
        close()
    }
}
