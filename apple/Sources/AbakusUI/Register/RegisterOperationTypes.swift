import AbakusCore
import Foundation

public enum RegisterPopup: Equatable, Sendable {
    case needsCategory(rowId: String)
    case removeCategory(rowId: String)
    case scheduledCallout(RegisterScheduledCallout)

    public var anchor: RegisterAnchorID {
        switch self {
        case .needsCategory(let id), .removeCategory(let id): .error(id)
        case .scheduledCallout: .schedulerTitle
        }
    }

    public var rowId: String? {
        switch self {
        case .needsCategory(let id), .removeCategory(let id): id
        case .scheduledCallout: nil
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

    /// Touch screens show the scheduled transactions in a sheet of their own, not below the register.
    public var touchMessage: String {
        switch self {
        case .added:
            "Sie steht jetzt in den geplanten Buchungen. Ihre Häufigkeit ist <b>Monatlich</b>, lässt sich aber ändern."
        case .moved:
            "Sie steht jetzt in den geplanten Buchungen. Ihre Häufigkeit ist <b>Einmalig</b>, lässt sich aber ändern."
        }
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
    public var tooltip: String?
    public var isClickable = true

    public var id: Kind { kind }
}

struct RegisterOverlayState {
    var menuRequest: RegisterMenuRequest?
    var popup: RegisterPopup?
}
