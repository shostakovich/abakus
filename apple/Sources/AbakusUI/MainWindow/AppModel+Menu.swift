import Foundation

extension AppModel {
    public func goToBudget() {
        navigation.selection = .budget
    }

    /// View › "Zu den Konten": back from Budget to the register last shown.
    public func goToAccounts() {
        guard !navigation.selection.showsRegister else { return }
        let last = lastRegisterSelection.flatMap { selection -> SidebarSelection? in
            if case .account(let id) = selection, store.budget.account(withId: id) == nil { return nil }
            return selection
        }
        navigation.selection = last ?? Self.defaultSelection(in: store.budget)
    }

    /// The register's toolbar and Buchungen menu exist only while it shows an account.
    public var showsRegister: Bool { navigation.selection != .budget && register.accountKey != nil }

    /// Edit › "Konto bearbeiten …": shown only while the register shows a single account.
    public var showsAccountProperties: Bool { register.account != nil }

    public func accountPropertiesClicked() {
        guard let account = register.account else { return }
        accounts.editAccountRequested(account.id)
    }
}
