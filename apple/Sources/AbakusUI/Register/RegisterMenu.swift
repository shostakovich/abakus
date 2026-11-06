import AbakusCore
import Foundation

public enum RegisterMenuAction: Hashable, Sendable {
    case categorize(categoryId: String?)
    case makeRecurring, moveToScheduler
    case moveToAccount(accountId: String)
    case delete
    case filter(RegisterFilter)
    case togglePicking, toggleSelectAll
    case toggleScheduler, editAccount
    case toggleColumn(RegisterColumn)
    case toggleScheduledColumn(RegisterColumn)
    case applyScheduledColumnsToAllAccounts
    case enterScheduledNow, skipScheduled, deleteScheduled
    case moveScheduled(accountId: String)
    case fillUnderfunded, resetAssigned
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
    public var systemImage: String?
    public var subtitle: String?
    public var isDestructive: Bool

    public init(
        id: String, title: String, kind: Kind, isEnabled: Bool = true, isChecked: Bool = false,
        systemImage: String? = nil, subtitle: String? = nil, isDestructive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.isDestructive = isDestructive
    }

    static func action(
        _ title: String, _ action: RegisterMenuAction, enabled: Bool = true, checked: Bool = false,
        systemImage: String? = nil, subtitle: String? = nil, isDestructive: Bool = false
    ) -> RegisterMenuItem {
        RegisterMenuItem(
            id: "\(action)", title: title, kind: .action(action), isEnabled: enabled, isChecked: checked,
            systemImage: systemImage, subtitle: subtitle, isDestructive: isDestructive)
    }

    static func separator(_ index: Int) -> RegisterMenuItem {
        RegisterMenuItem(id: "separator\(index)", title: "", kind: .separator)
    }

    package static func frequencyMenu(selected: ScheduledTransactionFrequency?) -> [RegisterMenuItem] {
        ScheduledTransactionFrequency.allCases.map { .action($0.readableName, .frequency($0), checked: $0 == selected) }
    }
}

public enum RegisterAnchorID: Hashable, Sendable {
    case schedulerTitle, schedulerColumnTab
    case error(String)
}

public struct RegisterMenuRequest: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var items: [RegisterMenuItem]
    /// The menu opens at the anchor's bottom-left corner, one point down (`showMenu(left, bottom + 1)`).
    public var anchor: RegisterAnchorID
}
