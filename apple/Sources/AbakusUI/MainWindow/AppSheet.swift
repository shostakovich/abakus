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
    private static let closedAccountsId = UUID()

    case addCategory(AddCategoryRequest)
    case payeeSettings(PayeeSettingsModel)
    case statement(ReconciliationStatementForm)
    case addAccount(AddAccountForm)
    case closedAccounts
    case scheduled(TransactionEditor)

    package var id: UUID {
        switch self {
        case .addCategory(let request): request.id
        case .payeeSettings(let model): model.id
        case .statement(let form): form.id
        case .addAccount(let form): form.id
        case .closedAccounts: Self.closedAccountsId
        case .scheduled(let editor): editor.id
        }
    }
}

extension AppModel {
    package var sheet: AppSheet? {
        if let editor = register.scheduler.editor { return .scheduled(editor) }
        if let request = register.editor?.addCategoryRequest { return .addCategory(request) }
        if let payeeSettings { return .payeeSettings(payeeSettings) }
        if let form = register.reconciliation.statementForm { return .statement(form) }
        if let form = accounts.addForm { return .addAccount(form) }
        if register.isClosedAccountsListShown { return .closedAccounts }
        return nil
    }
}

extension TransactionEditor {
    package var addCategoryRequest: AddCategoryRequest? {
        addCategoryForm.map { form in
            AddCategoryRequest(
                form: form, masterNames: store.budget.budgetCategoryGroups.map(\.name),
                onCreate: addCategoryConfirmed, onCancel: addCategoryCancelled)
        }
    }
}
