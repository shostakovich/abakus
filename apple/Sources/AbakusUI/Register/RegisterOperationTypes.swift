import AbakusCore
import Foundation

public enum RegisterPopup: Equatable, Sendable {
    case needsCategory(rowId: String)
    case removeCategory(rowId: String)

    public var anchor: RegisterAnchorID {
        switch self {
        case .needsCategory(let id), .removeCategory(let id): .error(id)
        }
    }

    public var rowId: String? {
        switch self {
        case .needsCategory(let id), .removeCategory(let id): id
        }
    }
}

public enum RegisterNavigationKey: Hashable, Sendable {
    case up, down, pageUp, pageDown, home, end
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
