import Foundation

public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case checking
    case savings
    case cash
    case tracking

    public static let budgetKinds: [AccountKind] = [.checking, .savings, .cash]

    public var label: String {
        switch self {
        case .checking: "Girokonto"
        case .savings: "Sparkonto"
        case .cash: "Bargeld"
        case .tracking: "Tracking"
        }
    }

    public var isBudgetAccount: Bool { self != .tracking }
}

public struct Account: Hashable, Identifiable, Sendable, Positioned {
    public static let allAccountsName = "Alle Konten"

    public var id: String
    public var name: String
    public var kind: AccountKind
    /// The account the Kasse books into; the Mac keeps it as it is.
    public var sharedExpenses: Bool
    public var closed: Bool
    public var note: String?
    public var position: Int
    public var lastReconciledAt: Date?

    public var onBudget: Bool { kind.isBudgetAccount }
    public var transferPayeeName: String { Payee.transferPrefix + name }

    public init(
        id: String = EntityID.createUID(),
        name: String,
        kind: AccountKind,
        sharedExpenses: Bool = false,
        closed: Bool = false,
        note: String? = nil,
        position: Int = 0,
        lastReconciledAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sharedExpenses = sharedExpenses
        self.closed = closed
        self.note = note
        self.position = position
        self.lastReconciledAt = lastReconciledAt
    }

    public var lastReconciledOn: DateWithoutTime? {
        lastReconciledAt.map { DateWithoutTime.today(now: $0) }
    }
}
