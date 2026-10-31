import AbakusCore
import Foundation

public enum RegisterPopup: Equatable, Sendable {
    case approveReject(rowId: String)
    case needsCategory(rowId: String)
    case removeCategory(rowId: String)
    case runningBalance(rowId: String)
    case timeframe
    case scheduledCallout(RegisterScheduledCallout)

    public var anchor: RegisterAnchorID {
        switch self {
        case .approveReject(let id), .needsCategory(let id), .removeCategory(let id): .error(id)
        case .runningBalance(let id): .balance(id)
        case .timeframe: .dateButton
        case .scheduledCallout: .schedulerTitle
        }
    }

    public var rowId: String? {
        switch self {
        case .approveReject(let id), .needsCategory(let id), .removeCategory(let id), .runningBalance(let id): id
        case .timeframe, .scheduledCallout: nil
        }
    }
}

public enum RegisterNavigationKey: Hashable, Sendable {
    case up, down, pageUp, pageDown, home, end
}

public enum RegisterScheduledCallout: Equatable, Sendable {
    case added, moved

    public var title: String {
        switch self {
        case .added: "Geplante Buchung hinzugefügt"
        case .moved: "Buchung verschoben"
        }
    }

    public var message: String {
        switch self {
        case .added:
            "Unten in den geplanten Buchungen steht jetzt eine neue. Ihre Häufigkeit ist <b>Monatlich</b>, "
                + "lässt sich aber ändern."
        case .moved:
            "Die ausgewählte Buchung steht jetzt unten in den geplanten Buchungen. Ihre Häufigkeit ist "
                + "<b>Einmalig</b>, lässt sich aber ändern."
        }
    }
}

public struct RenamePayeeForm: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var payeeId: String
    public var currentName: String

    public var description: String {
        "Alle Buchungen mit „\(currentName)“ bekommen den neuen Namen als Empfänger. (So lässt sich auch die "
            + "Groß- und Kleinschreibung ändern.)"
    }
}

/// A single undo slot for deletes and moves, shown by the undo notifier until the budget changes again.
public struct RegisterUndoSlot: Equatable, Sendable {
    enum Restore: Equatable, Sendable {
        case deleted([Transaction], payees: [Payee])
        case moved([MovedTransaction])
        case movedSchedules([MovedTransaction])
    }

    public let id = UUID()
    public var message: String
    var restore: Restore
    var reselect: [String]
    var budgetAfter: Budget
}

public struct RegisterNotifier: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case error, warning, reminder, undo
    }

    public var kind: Kind
    public var text: String
    public var link: String?

    public var id: Kind { kind }
}

struct RegisterOverlayState {
    var menuRequest: RegisterMenuRequest?
    var popup: RegisterPopup?
    var searchDropDown: SearchDropDownState?
    var timeframe: TimeframeState?
}

public struct SearchDropDownState: Equatable, Sendable {
    public var items: [RegisterSearchSuggestion]
    public var highlighted: Int?
}

public struct TimeframeState: Equatable, Sendable {
    public var start: DateWithoutTime
    public var end: DateWithoutTime
    public var range: DateFilterRange
    public var isChanged = false
}
