import AbakusCore
import Foundation
import Observation

@MainActor
@Observable
public final class AddAccountForm: Identifiable {
    public static let title = "Konto hinzufügen"
    public static let typePlaceholder = "Art wählen …"
    public static let typeHint = "Trackingkonten zählen nicht zum Budget. Das lässt sich später nicht ändern."

    public let id = UUID()
    public var name: String
    public var balanceText: String
    public var date: DateWithoutTime
    public var type: AccountKind?

    init(name: String, balanceText: String, date: DateWithoutTime) {
        self.name = name
        self.balanceText = balanceText
        self.date = date
    }

    public var canCreate: Bool { type != nil }
}

@MainActor
@Observable
public final class EditAccountForm: Identifiable {
    public static let title = "Konto bearbeiten"

    public let id = UUID()
    public let accountId: String
    public var name: String
    public var type: AccountKind
    public let typeChoices: [AccountKind]

    init(account: Account) {
        accountId = account.id
        name = account.name
        type = account.kind
        typeChoices = account.onBudget ? AccountKind.budgetKinds : [.tracking]
    }
}

@MainActor
@Observable
public final class AdjustBalanceForm: Identifiable {
    public let id = UUID()
    public let accountId: String
    public let accountName: String
    public let hasTransactions: Bool
    public let workingBalanceText: String
    public var amountText: String

    init(account: Account, hasTransactions: Bool, workingBalanceText: String, amountText: String) {
        accountId = account.id
        accountName = account.name
        self.hasTransactions = hasTransactions
        self.workingBalanceText = workingBalanceText
        self.amountText = amountText
    }

    public var title: String {
        hasTransactions ? "Saldo von „\(accountName)“ anpassen" : "Anfangssaldo von „\(accountName)“ eingeben"
    }

    public var instruction: String {
        hasTransactions
            ? "Gib den neuen Arbeitssaldo von „\(accountName)“ ein. Die Differenz wird als Buchung angelegt."
            : "Gib den Anfangssaldo von „\(accountName)“ ein. Er wird als Buchung angelegt."
    }

    public var fieldLabel: String { hasTransactions ? "Neuer Arbeitssaldo" : "Anfangssaldo" }
    public static let hint = "Aktueller Arbeitssaldo: "
    public static let buttonTitle = "Anpassen"
}
