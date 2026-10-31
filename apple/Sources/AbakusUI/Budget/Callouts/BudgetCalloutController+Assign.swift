import AbakusCore
import Foundation

/// "In eine Kategorie …": assigns an amount of the month's Zu verteilen to one category.
public struct BudgetAssignForm: Hashable, Sendable {
    public let month: DateWithoutTime
    public let monthTitle: String
    public let freeText: String
    public let categories: [BudgetCategoryChoiceGroup]
    public var categoryId: String
    public var amount: String
    public internal(set) var error: String?
}

extension BudgetCalloutController {
    static let fillUnderfundedTitle = "Unterfinanzierte füllen"
    static let assignToCategoryTitle = "In eine Kategorie …"

    func assignMenu(month date: DateWithoutTime) -> [RegisterMenuItem] {
        let sheet = budget.sheet
        let underfunded = sheet.underfunded(in: date)
        let hasFree = (sheet.month(date)?.free ?? 0) > 0
        let fillTitle =
            underfunded > 0
            ? "\(Self.fillUnderfundedTitle) (\(formatter.currency(underfunded)))" : Self.fillUnderfundedTitle
        return [
            .action(fillTitle, .fillUnderfunded, enabled: hasFree && underfunded > 0),
            .action(Self.assignToCategoryTitle, .assignToCategory, enabled: hasFree),
        ]
    }

    func assignForm(month date: DateWithoutTime) -> BudgetAssignForm? {
        let sheet = budget.sheet
        guard let month = sheet.month(date),
            let categoryId = sheet.firstUnderfunded(in: date)
                ?? sheet.categoryGroups.lazy.flatMap(\.categories).first?.id
        else { return nil }
        return BudgetAssignForm(
            month: date, monthTitle: formatter.monthHeader(date),
            freeText: "Frei zu verteilen: \(formatter.currency(month.free))", categories: categoryChoices(),
            categoryId: categoryId, amount: suggestedAmount(categoryId, in: date))
    }

    private func suggestedAmount(_ categoryId: String, in month: DateWithoutTime) -> String {
        formatter.currencyNoSymbol(budget.sheet.assignSuggestion(categoryId: categoryId, in: month))
    }

    public var assignCategoryId: String {
        get { assignForm?.categoryId ?? "" }
        set {
            changeAssignForm {
                $0.categoryId = newValue
                $0.amount = suggestedAmount(newValue, in: $0.month)
            }
        }
    }

    public var assignAmount: String {
        get { assignForm?.amount ?? "" }
        set { changeAssignForm { $0.amount = newValue } }
    }

    private func changeAssignForm(_ change: (inout BudgetAssignForm) -> Void) {
        guard var form = assignForm else { return }
        change(&form)
        form.error = nil
        assignForm = form
    }

    public func assignClicked() {
        guard let form = assignForm else { return }
        guard let amount = typedAmount(form.amount), amount > 0 else {
            assignForm?.error = amountError(form.amount)
            return
        }
        move(amount, in: form.month, from: readyToAssignCategoryId, to: form.categoryId)
    }

    public func assignCancelled() {
        close()
    }
}
