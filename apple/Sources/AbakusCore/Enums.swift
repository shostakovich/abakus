public enum ClearedStatus: String, Codable, CaseIterable, Sendable {
    case uncleared
    case cleared
    case reconciled

    public var integerValue: Int {
        switch self {
        case .uncleared: 0
        case .cleared: 1
        case .reconciled: 2
        }
    }
}

public enum ErrorLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case none = "None"
    case needsCategory = "NeedsCategory"
    case forReview = "ForReview"
    case error = "Error"

    public var rank: Int {
        switch self {
        case .none: 0
        case .needsCategory: 1
        case .forReview: 5
        case .error: 10
        }
    }

    /// Ranks NeedsCategory above ForReview, unlike `rank`.
    public var accountPriority: Int {
        switch self {
        case .none: 0
        case .forReview: 1
        case .needsCategory: 2
        case .error: 3
        }
    }

    public static func < (lhs: ErrorLevel, rhs: ErrorLevel) -> Bool { lhs.rank < rhs.rank }
}

public struct ErrorState: Hashable, Sendable {
    public var level: ErrorLevel
    public var message: String

    public init(level: ErrorLevel, message: String) {
        self.level = level
        self.message = message
    }

    public static let noError = ErrorState(level: .none, message: "")
}

public enum BudgetType: String, Codable, Sendable {
    case personal = "Personal"
    case business = "Business"
}
