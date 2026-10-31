import Foundation

public enum BudgetError: Error, Equatable, Sendable, LocalizedError {
    case emptyAccountName
    case duplicateAccountName
    case invalidAccountNameCharacter
    case accountNotFound(String)
    case budgetStateIsFixed
    case transactionNotFound(String)
    case transferToSameAccount
    case invalidTransferPayee(String)
    case splitAmountMismatch
    case splitCannotBeTransfer
    case transferFromSplitAmountLocked
    case transferFromSplitPayeeLocked
    case ledTransaction(TransactionLeader)
    case categoryNameMissing
    case duplicateCategoryName
    case categoryCantBeIncome
    case categoryIsReserved
    case categoryIllegalCharacters
    case categoryNotFound(String)
    case categoryMustHaveName
    case categoryNameUsed
    case categoryNameTakenInGroup(group: String, name: String)
    case categoryInUse
    case categoryGroupNotEmpty
    case transferIntoMoveTarget(String)
    case emptyPayeeName
    case transferPayeeName(String)
    case transferPayeeCannotBeRenamed
    case amountNotFinite
    case targetAmountNotPositive
    case targetDueBeforeStart

    public var errorDescription: String? {
        switch self {
        case .emptyAccountName: "Der Kontoname darf nicht leer sein."
        case .duplicateAccountName: "Ein Konto mit diesem Namen gibt es schon."
        case .invalidAccountNameCharacter: "Ein Kontoname darf kein ` enthalten."
        case .accountNotFound(let id): "Konto \(id) nicht gefunden."
        case .budgetStateIsFixed: "Ein Budgetkonto kann kein Trackingkonto werden und umgekehrt."
        case .transactionNotFound(let id): "Buchung \(id) nicht gefunden."
        case .transferToSameAccount: "Ein Konto kann nicht auf sich selbst umbuchen."
        case .invalidTransferPayee: "Ungültiger Empfänger"
        case .splitAmountMismatch: "Die Teile ergeben nicht den Betrag der Buchung."
        case .splitCannotBeTransfer: "Diese Buchung kann keine Umbuchung werden."
        case .transferFromSplitAmountLocked: "Der Betrag dieser Buchung lässt sich hier nicht ändern."
        case .transferFromSplitPayeeLocked: "Der Empfänger dieser Buchung lässt sich hier nicht ändern."
        case .ledTransaction(let leader): "Diese Buchung wird \(leader.byName) geführt."
        case .categoryNameMissing: "Bitte zuerst eine Gruppe und einen Kategorienamen eingeben."
        case .duplicateCategoryName: "Eine Kategorie mit diesem Namen gibt es schon."
        case .categoryCantBeIncome: "Einnahmen gehen an „Zu verteilen“. Bitte einen anderen Gruppennamen wählen."
        case .categoryIsReserved: "Dieser Name ist reserviert. Bitte einen anderen wählen."
        case .categoryIllegalCharacters: "Eine Kategorie darf weder „:“ noch „`“ enthalten."
        case .categoryNotFound(let id): "Kategorie \(id) nicht gefunden."
        case .categoryMustHaveName: "Die Kategorie braucht einen Namen."
        case .categoryNameUsed: "Diesen Kategorienamen gibt es schon."
        case .categoryNameTakenInGroup(let master, let name):
            "Es gibt schon eine Kategorie „\(master): \(name)“.\nBitte eine der beiden umbenennen und es erneut versuchen."
        case .categoryInUse: "Die Kategorie wird schon verwendet."
        case .categoryGroupNotEmpty: "Nur leere Gruppen lassen sich löschen."
        case .transferIntoMoveTarget(let name):
            "Mindestens eine dieser Buchungen ist eine Umbuchung mit „\(name)“, darum wird keine verschoben."
        case .emptyPayeeName: "Ungültiger Empfänger"
        case .transferPayeeName: "Ungültiger Empfängername"
        case .transferPayeeCannotBeRenamed: "Der Empfänger einer Umbuchung lässt sich nicht umbenennen."
        case .amountNotFinite: "Der Betrag ist zu groß."
        case .targetAmountNotPositive: "Bitte einen Betrag über null angeben."
        case .targetDueBeforeStart: "Das Datum darf nicht vor dem Beginn des Ziels liegen."
        }
    }
}
