import Foundation

struct AddCategoryRequest: Identifiable {
    let form: AddCategoryForm
    let masterNames: [String]
    let onCreate: (String, String) -> Void
    let onCancel: () -> Void

    var id: UUID { form.id }
}

/// The form the window shows as its sheet; a new category asked for by an editor covers everything else.
enum AppSheet: Identifiable {
    case addCategory(AddCategoryRequest)
    case payeeSettings(PayeeSettingsModel)
    case renamePayee(RenamePayeeForm)
    case statement(ReconciliationStatementForm)
    case addAccount(AddAccountForm)
    case adjustBalance(AdjustBalanceForm)

    var id: UUID {
        switch self {
        case .addCategory(let request): request.id
        case .payeeSettings(let model): model.id
        case .renamePayee(let form): form.id
        case .statement(let form): form.id
        case .addAccount(let form): form.id
        case .adjustBalance(let form): form.id
        }
    }
}

extension AppModel {
    var sheet: AppSheet? {
        if let editor = register.editor ?? register.scheduler.editor, let form = editor.addCategoryForm {
            return .addCategory(
                AddCategoryRequest(
                    form: form, masterNames: editor.store.budget.budgetCategoryGroups.map(\.name),
                    onCreate: editor.addCategoryConfirmed, onCancel: editor.addCategoryCancelled))
        }
        if let payeeSettings { return .payeeSettings(payeeSettings) }
        if let form = register.renamePayeeForm { return .renamePayee(form) }
        if let form = register.reconciliation.statementForm { return .statement(form) }
        if let form = accounts.addForm { return .addAccount(form) }
        if let form = accounts.balanceForm { return .adjustBalance(form) }
        return nil
    }
}
