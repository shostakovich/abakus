import Foundation

public struct Payee: Hashable, Identifiable, Sendable {
    public static let transferPrefix = "Transfer : "
    public static let startingBalanceName = "Anfangssaldo"
    public static let manualBalanceAdjustmentName = "Saldoanpassung"
    public static let reconciliationBalanceAdjustmentName = "Ausgleichsbuchung"

    public var id: String
    public var name: String
    public var hidden: Bool
    public var transferAccountId: String?
    public var lastCategoryId: String?

    public var isTransferPayee: Bool { transferAccountId != nil }

    public init(
        id: String = EntityID.createUID(),
        name: String,
        hidden: Bool = false,
        transferAccountId: String? = nil,
        lastCategoryId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hidden = hidden
        self.transferAccountId = transferAccountId
        self.lastCategoryId = lastCategoryId
    }

    public static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lookupKey == rhs.lookupKey
    }

    public static func transferPayee(for account: Account) -> Payee {
        Payee(
            id: EntityID.transferPayee(accountId: account.id), name: account.transferPayeeName,
            transferAccountId: account.id)
    }

    /// Spaces and case do not matter when `Transfer:` is typed into the payee field.
    public static func isTransferPayeeName(_ text: String) -> Bool {
        text.replacingOccurrences(of: " ", with: "").lowercased().hasPrefix("transfer:")
    }

    public static func transferTargetAccountName(_ text: String) -> String? {
        guard isTransferPayeeName(text), let colon = text.firstIndex(of: ":") else { return nil }
        return text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
}
