import AbakusCore
import Foundation

public enum RegisterMenuAction: Hashable, Sendable {
    case markCleared, markUncleared, approve, reject
    case categorize(categoryId: String?)
    case renamePayee, payeeSettings, makeRecurring, moveToScheduler
    case moveToAccount(accountId: String)
    case delete
    case timeframe, showReconciled
    case toggleColumn(RegisterColumn)
    case applyColumnsToAllAccounts
    case toggleScheduledColumn(RegisterColumn)
    case applyScheduledColumnsToAllAccounts
    case enterScheduledNow, skipScheduled, deleteScheduled
    case moveScheduled(accountId: String)
    case quickBudget(QuickBudgetFill)
    case fillUnderfunded, assignToCategory
    case frequency(ScheduledTransactionFrequency)
}

public struct RegisterMenuItem: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case action(RegisterMenuAction)
        case title
        case separator
        case submenu([RegisterMenuItem])
    }

    public var id: String
    public var title: String
    public var kind: Kind
    public var isEnabled: Bool
    public var isChecked: Bool

    public init(id: String, title: String, kind: Kind, isEnabled: Bool = true, isChecked: Bool = false) {
        self.id = id
        self.title = title
        self.kind = kind
        self.isEnabled = isEnabled
        self.isChecked = isChecked
    }

    static func action(_ title: String, _ action: RegisterMenuAction, enabled: Bool = true, checked: Bool = false)
        -> RegisterMenuItem
    {
        RegisterMenuItem(id: "\(action)", title: title, kind: .action(action), isEnabled: enabled, isChecked: checked)
    }

    static func separator(_ index: Int) -> RegisterMenuItem {
        RegisterMenuItem(id: "separator\(index)", title: "", kind: .separator)
    }

    static func frequencyMenu(selected: ScheduledTransactionFrequency?) -> [RegisterMenuItem] {
        ScheduledTransactionFrequency.allCases.map { .action($0.readableName, .frequency($0), checked: $0 == selected) }
    }
}

public enum RegisterAnchorID: Hashable, Sendable {
    case viewMenu, columnTab, schedulerTitle, schedulerColumnTab
    case error(String)
    case balance(String)
}

public struct RegisterMenuRequest: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var items: [RegisterMenuItem]
    /// The menu opens at the anchor's bottom-left corner, one point down (`showMenu(left, bottom + 1)`).
    public var anchor: RegisterAnchorID
}
