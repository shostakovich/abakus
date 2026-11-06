import Foundation

package struct AddCategoryRequest: Identifiable {
    package let form: AddCategoryForm
    package let masterNames: [String]
    package let onCreate: (String, String) -> Void
    package let onCancel: () -> Void

    package var id: UUID { form.id }
}

/// The form the window shows as its sheet; a new category asked for by an editor covers everything else.
package enum AppSheet: Identifiable {
    case addCategory(AddCategoryRequest)
    case payeeSettings(PayeeSettingsModel)
    case statement(ReconciliationStatementForm)
    case addAccount(AddAccountForm)
    case adjustBalance(AdjustBalanceForm)

    package var id: UUID {
        switch self {
        case .addCategory(let request): request.id
        case .payeeSettings(let model): model.id
        case .statement(let form): form.id
        case .addAccount(let form): form.id
        case .adjustBalance(let form): form.id
        }
    }
}

extension AppModel {
    package var sheet: AppSheet? {
        if let editor = register.editor ?? register.scheduler.editor, let form = editor.addCategoryForm {
            return .addCategory(
                AddCategoryRequest(
                    form: form, masterNames: editor.store.budget.budgetCategoryGroups.map(\.name),
                    onCreate: editor.addCategoryConfirmed, onCancel: editor.addCategoryCancelled))
        }
        if let payeeSettings { return .payeeSettings(payeeSettings) }
        if let form = register.reconciliation.statementForm { return .statement(form) }
        if let form = accounts.addForm { return .addAccount(form) }
        if let form = accounts.balanceForm { return .adjustBalance(form) }
        return nil
    }
}
