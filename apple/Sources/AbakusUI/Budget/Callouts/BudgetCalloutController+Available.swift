import AbakusCore
import Foundation

/// An overspent category's cover list in one month, or the touch sheet's Verfügbar.
public struct BudgetAvailableForm: Hashable, Sendable {
    public let month: DateWithoutTime
    public let categoryId: String
    public let categoryName: String
    public let monthTitle: String
    public let available: Decimal
    /// Zu verteilen, only while it is above zero.
    public let readyToAssign: BudgetFundsSource?
    /// The categories with money, the most first.
    public let categories: [BudgetFundsSource]

    public var sources: [BudgetFundsSource] { (readyToAssign.map { [$0] } ?? []) + categories }

    public var isOverspent: Bool { available < 0 }
}

extension BudgetCalloutController {
    package static let noSources = "Kein Geld in „Zu verteilen“ oder anderen Kategorien."

    func availableForm(month date: DateWithoutTime, categoryId: String) -> BudgetAvailableForm? {
        let sheet = budget.sheet
        guard let month = sheet.month(date),
            let category = sheet.categoryGroups.flatMap(\.categories).first(where: { $0.id == categoryId })
        else { return nil }
        let sources = sheet.coverSources(for: categoryId, in: date)
        let readyToAssign = sources.first { $0.categoryId == sheet.readyToAssignCategoryId }
        return BudgetAvailableForm(
            month: date, categoryId: categoryId, categoryName: category.name,
            monthTitle: formatter.monthHeader(date), available: month.category(categoryId)?.balance ?? 0,
            readyToAssign: readyToAssign, categories: sources.filter { $0.categoryId != readyToAssign?.categoryId })
    }

    /// The touch sheet stays open while what is done in it changes Verfügbar.
    func refreshAvailableForm() {
        guard let form = availableForm else { return }
        availableForm = availableForm(month: form.month, categoryId: form.categoryId)
    }

    public var readyToAssignCategoryId: String { budget.sheet.readyToAssignCategoryId }

    public var coverTitle: String {
        "\(formatter.currency(-min(availableForm?.available ?? 0, 0))) decken aus"
    }

    /// Moves as much as the source holds, up to the overspending, both as they are after the edit being typed.
    public func cover(from sourceId: String) {
        guard let opened = availableForm else { return }
        budget.commitEdit()
        guard let form = availableForm(month: opened.month, categoryId: opened.categoryId),
            let source = form.sources.first(where: { $0.categoryId == sourceId }),
            case let amount = source.coverAmount(overspent: form.available), amount > 0
        else { return }
        close()
        let name =
            source.categoryId == readyToAssignCategoryId
            ? "„\(budget.plainName(of: source.categoryId))“" : budget.plainName(of: source.categoryId)
        budget.performUndoable(
            .moveAssigned(month: form.month, from: source.categoryId, to: form.categoryId, amount: amount),
            month: form.month, actionName: "Decken"
        ) { "\(self.formatter.currency($0)) aus \(name) gedeckt." }
    }
}
