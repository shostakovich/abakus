#if os(iOS)
    import AbakusCore
    import AbakusUI
    import SwiftUI

    /// The sheets the whole app shows, one at a time; the budget's and the register's own sheets stay with them.
    @MainActor
    enum TouchSheet: @MainActor Identifiable {
        case payeeSettings(PayeeSettingsModel)
        case addAccount(AddAccountForm)
        case editAccount(EditAccountForm)

        init?(_ model: AppModel, navigation: TouchNavigation) {
            let accounts = model.accounts
            if let payees = model.payeeSettings, navigation.showsPayeeSheet {
                self = .payeeSettings(payees)
            } else if let form = accounts.addForm {
                self = .addAccount(form)
            } else if let form = accounts.editForm {
                self = .editAccount(form)
            } else {
                return nil
            }
        }

        var id: String {
            switch self {
            case .payeeSettings(let model): model.id.uuidString
            case .addAccount(let form): form.id.uuidString
            case .editAccount(let form): form.id.uuidString
            }
        }
    }

    struct TouchSheetView: View {
        let model: AppModel
        let sheet: TouchSheet

        var body: some View {
            switch sheet {
            case .payeeSettings(let payees):
                PayeeSettingsSheet(model: payees, dialogs: model.presentedDialogs)
            case .addAccount(let form):
                AddAccountSheet(controller: model.accounts, form: form)
                    .modifier(DialogAlert(dialogs: model.presentedDialogs))
            case .editAccount(let form):
                EditAccountSheet(controller: model.accounts, form: form)
                    .modifier(DialogAlert(dialogs: model.presentedDialogs))
            }
        }
    }

    extension TouchSheet {
        /// Swiping a sheet away cancels it.
        func cancel(in model: AppModel) {
            switch self {
            case .payeeSettings(let payees): payees.close()
            case .addAccount: model.accounts.addCancelled()
            case .editAccount: model.accounts.editCancelled()
            }
        }
    }
#endif
