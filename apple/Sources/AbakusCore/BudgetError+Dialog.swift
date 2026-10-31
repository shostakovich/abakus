import Foundation

extension BudgetError {
    public var dialogInstruction: String {
        switch self {
        case .transferIntoMoveTarget(let name): "Nicht alle diese Buchungen lassen sich nach „\(name)“ verschieben."
        default: errorDescription ?? ""
        }
    }

    public var dialogContent: String? {
        switch self {
        case .transferToSameAccount:
            "Ändere zuerst das Konto oder das Gegenkonto dieser Umbuchung."
        case .invalidTransferPayee(let name):
            "„\(name)“ ist kein gültiger Kontoname. Beginnt ein Empfänger mit „Transfer :“, muss ein gültiger "
                + "Kontoname folgen."
        case .splitCannotBeTransfer:
            "Diese Buchung ist schon aufgeteilt und kann darum keine Umbuchung werden. Um eine Umbuchung "
                + "aufzuteilen, mache die Buchung selbst nicht zur Umbuchung, sondern teile sie auf und mache die "
                + "Teile zu Umbuchungen."
        case .transferFromSplitAmountLocked:
            "Diese Buchung ist die Gegenbuchung eines Teils. Ihr Betrag lässt sich nur in der Aufteilung ändern."
        case .transferFromSplitPayeeLocked:
            "Diese Buchung ist die Gegenbuchung eines Teils, darum lässt sich ihr Empfänger nicht ändern. Ändere "
                + "sie in der Aufteilung."
        case .ledTransaction(let leader):
            "Betrag, Datum, Konto und Empfänger ändern sich nur \(leader.inName); aufteilen oder löschen lässt sie sich "
                + "hier nicht. Kategorie, Memo und Status lassen sich ändern."
        case .transferIntoMoveTarget: errorDescription
        case .emptyPayeeName: "Der neue Empfänger darf nicht leer sein."
        case .transferPayeeName(let name):
            "„\(name)“ ist kein gültiger Empfängername. „Transfer :“ am Anfang ist Umbuchungen vorbehalten."
        default: nil
        }
    }
}
