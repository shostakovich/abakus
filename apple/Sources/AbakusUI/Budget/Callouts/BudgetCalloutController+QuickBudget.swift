import AbakusCore
import Foundation

enum QuickBudgetChoice: Hashable, Sendable {
    case cancel, fill
}

extension BudgetCalloutController {
    public func quickBudgetMenu(month: DateWithoutTime) -> [RegisterMenuItem] {
        let fills = budget.sheet.quickBudgetMenu(month: month, formatter: formatter).enumerated().map {
            index, item in
            guard let fill = item.fill else {
                return RegisterMenuItem(id: "heading\(index)", title: item.label, kind: .title, isEnabled: false)
            }
            return .action(item.label, .quickBudget(fill))
        }
        return assignMenu(month: month) + [.separator(0)] + fills
    }

    public func quickBudgetMenuChosen(_ action: RegisterMenuAction, month: DateWithoutTime) {
        switch action {
        case .quickBudget(let fill): quickBudgetChosen(fill, month: month)
        case .fillUnderfunded: budget.perform(.fillUnderfunded(month: month, today: budget.today))
        case .assignToCategory: budget.present(.assignToCategory(month: month))
        default: break
        }
    }

    public func quickBudgetChosen(_ fill: QuickBudgetFill, month: DateWithoutTime) {
        guard let confirmation = budget.sheet.quickBudgetConfirmation(fill, month: month, formatter: formatter) else {
            return
        }
        let dialog = TaskDialog<QuickBudgetChoice>(
            instruction: confirmation.instruction, content: confirmation.content,
            buttons: [.init(.cancel, title: "Abbrechen"), .init(.fill, title: confirmation.button, isDefault: true)],
            dismissal: .cancel)
        dialogs.ask(dialog) { [weak self] answer in
            guard let self, answer.choice == .fill else { return }
            budget.perform(.quickBudget(month: month, fill: fill, today: budget.today))
        }
    }

    public func quickBudgetMenuClosed() {
        guard case .monthQuickBudget = budget.presentedPopup else { return }
        budget.dismissPopup()
    }
}
