import AbakusCore
import Foundation
import Observation

@MainActor
@Observable
public final class BudgetCalloutController {
    unowned let budget: BudgetViewModel
    public internal(set) var category: BudgetCategoryForm?
    public internal(set) var summary: TransactionSummary?
    public internal(set) var outflowHelp: BudgetOutflowHelp?
    public internal(set) var availableForm: BudgetAvailableForm?
    public internal(set) var assignForm: BudgetAssignForm?
    @ObservationIgnored public var onShowTransaction: @MainActor (String) -> Void = { _ in }
    @ObservationIgnored public var onShowInAccountView: @MainActor (AccountViewFilter) -> Void = { _ in }

    init(budget: BudgetViewModel) {
        self.budget = budget
    }

    var store: any BudgetStoring { budget.store }
    var dialogs: DialogStack { budget.dialogs }
    var formatter: BudgetFormatter { budget.formatter }

    func open(_ popup: BudgetPopup) -> BudgetPopup? {
        reset()
        switch popup {
        case .editCategory(let id, let month):
            guard let form = categoryForm(id, isNew: false, month: month) else { return nil }
            category = form
        case .outflowSummary(let month, let source):
            summary = store.budget.outflowSummary(source, month: month, today: budget.today, formatter: formatter)
        case .incomeSummary(let month):
            summary = store.budget.incomeSummary(month: month, today: budget.today, formatter: formatter)
        case .outflowHelp(let month, let id):
            guard let help = outflowHelp(month: month, categoryId: id) else { return nil }
            outflowHelp = help
        case .available(let month, let id):
            guard let form = availableForm(month: month, categoryId: id) else { return nil }
            availableForm = form
        case .assignToCategory(let month):
            guard let form = assignForm(month: month) else { return nil }
            assignForm = form
        case .monthQuickBudget: break
        }
        return popup
    }

    func reset() {
        category = nil
        summary = nil
        outflowHelp = nil
        availableForm = nil
        assignForm = nil
    }

    func isShowing(_ popup: BudgetPopup) -> Bool {
        budget.presentedPopup == popup
    }

    func close() {
        budget.dismissPopup()
        budget.panelFocusRequest += 1
    }

    public func escapePressed() -> Bool {
        guard let popup = budget.presentedPopup, !budget.isCoveredByModal else { return false }
        switch popup {
        case .monthQuickBudget: return false
        case .editCategory: if !targetEscaped() && !deletionEscaped() { categoryCancelled() }
        default: close()
        }
        return true
    }

    /// A category callout stays open after a refused name until Done succeeds, and while its target editor is open.
    public func mouseDownOutside() {
        guard let popup = budget.presentedPopup, !budget.isCoveredByModal else { return }
        switch popup {
        case .monthQuickBudget: break
        case .editCategory: if category?.closesOnClickOutside != false && category?.target == nil { close() }
        default: close()
        }
    }
}
