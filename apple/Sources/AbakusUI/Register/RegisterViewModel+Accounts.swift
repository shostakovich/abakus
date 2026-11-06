import AbakusCore
import Foundation

public enum RegisterBanner: Hashable, Sendable {
    case closed, sharedExpenses

    public var message: String {
        switch self {
        case .closed: "Dieses Konto ist geschlossen."
        case .sharedExpenses: "Buchungen kommen aus der Kasse, keine Buchungen von Hand."
        }
    }

    public static let reopenTitle = "Wieder öffnen"
}

public struct ClosedAccountRow: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
}

extension RegisterViewModel {
    public static let closedAccountsTitle = "Geschlossene Konten"

    public var banner: RegisterBanner? {
        guard let account else { return nil }
        if account.closed { return .closed }
        return account.sharedExpenses ? .sharedExpenses : nil
    }

    public func reopenClicked() {
        guard var account, account.closed else { return }
        account.closed = false
        perform(.editAccount(account))
    }

    public var closedAccounts: [ClosedAccountRow] {
        let budget = store.budget
        let formatter = formatter
        return budget.accounts(in: .closedAccounts).map { account in
            let balance = formatter.currency(budget.balances(forAccount: account.id).working)
            return ClosedAccountRow(id: account.id, name: account.name, detail: "\(account.kind.label) · \(balance)")
        }
    }

    var closedAccountsMenu: [RegisterMenuItem] {
        let count = store.budget.accounts(in: .closedAccounts).count
        guard isAllAccounts, count > 0 else { return [] }
        return [.action("\(Self.closedAccountsTitle) (\(count)) …", .closedAccounts)]
    }

    public func closedAccountsClicked() {
        guard isAllAccounts, !closedAccounts.isEmpty else { return }
        isClosedAccountsListShown = true
    }

    public func closedAccountChosen(_ accountId: String) {
        isClosedAccountsListShown = false
        guard store.budget.account(withId: accountId)?.closed == true else { return }
        navigation.selection = .account(accountId)
    }

    public func closedAccountsDismissed() {
        isClosedAccountsListShown = false
    }
}
