import Foundation

/// Stored by constant name, shown by label.
public enum StringOperator: String, Codable, CaseIterable, Hashable, Sendable {
    case contains
    case `is`
    case startsWith = "starts_with"
    case endsWith = "ends_with"

    public var label: String {
        switch self {
        case .contains: "enthält"
        case .is: "ist"
        case .startsWith: "beginnt mit"
        case .endsWith: "endet mit"
        }
    }
}

public struct PayeeRenameCondition: Hashable, Identifiable, Sendable, Positioned {
    public var id: String
    /// Set by the budget when the conditions are stored.
    public var payeeId: String
    public var position: Int
    public var `operator`: StringOperator
    public var text: String

    public init(
        id: String = EntityID.createUID(), payeeId: String = "", position: Int = 0,
        operator: StringOperator = .contains, text: String = ""
    ) {
        self.id = id
        self.payeeId = payeeId
        self.position = position
        self.operator = `operator`
        self.text = text
    }

    public var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    public func matches(_ name: String) -> Bool {
        guard !isBlank else { return false }
        switch self.operator {
        case .contains: return name.range(of: text, options: .caseInsensitive) != nil
        case .is: return name.caseInsensitiveCompare(text) == .orderedSame
        case .startsWith: return name.range(of: text, options: [.anchored, .caseInsensitive]) != nil
        case .endsWith: return name.range(of: text, options: [.anchored, .backwards, .caseInsensitive]) != nil
        }
    }

    public func isEquivalent(to other: PayeeRenameCondition) -> Bool {
        self.operator == other.operator && text.caseInsensitiveCompare(other.text) == .orderedSame
    }
}
