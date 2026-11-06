import AbakusCore
import Foundation
import Observation

@MainActor
@Observable
public final class AddAccountForm: Identifiable {
    public static let title = "Konto hinzufügen"
    public static let typeHint = "Tracking-Konten zählen nicht zum Budget. Das lässt sich später nicht ändern."

    public let id = UUID()
    public var name = ""
    public var balanceText: String
    public var type = AccountKind.checking

    init(balanceText: String) {
        self.balanceText = balanceText
    }

    public var canCreate: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

@MainActor
@Observable
public final class EditAccountForm: Identifiable {
    public static let title = "Konto bearbeiten"
    public static let closeTitle = "Konto schließen …"

    public let id = UUID()
    public let accountId: String
    public var name: String
    public var type: AccountKind
    public let typeChoices: [AccountKind]
    /// A closed account reopens from its register's banner.
    public let canClose: Bool

    init(account: Account) {
        accountId = account.id
        name = account.name
        type = account.kind
        typeChoices = account.onBudget ? AccountKind.budgetKinds : [.tracking]
        canClose = !account.closed
    }
}
