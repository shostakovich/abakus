import AbakusCore
import CoreGraphics
import Foundation

public enum EditorColumn: String, Hashable, Sendable, CaseIterable {
    case account, date, frequency, payee, category, memo, outflow, inflow

    public var gridColumn: RegisterColumn {
        switch self {
        case .account: .account
        case .date: .date
        case .frequency: .frequency
        case .payee: .payee
        case .category: .category
        case .memo: .memo
        case .outflow: .outflow
        case .inflow: .inflow
        }
    }

    public init?(_ column: RegisterColumn) {
        guard let match = Self.allCases.first(where: { $0.gridColumn == column }) else { return nil }
        self = match
    }

    public var isAmount: Bool { self == .outflow || self == .inflow }
}

public struct EditorFieldID: Hashable, Sendable, CustomStringConvertible {
    public let subId: String?
    public let column: EditorColumn

    public static func main(_ column: EditorColumn) -> EditorFieldID { EditorFieldID(subId: nil, column: column) }
    public static func sub(_ id: String, _ column: EditorColumn) -> EditorFieldID {
        EditorFieldID(subId: id, column: column)
    }

    public var isSub: Bool { subId != nil }
    public var description: String { (subId.map { "sub[\($0)]." } ?? "") + column.rawValue }
}

public enum EditorButton: String, Hashable, Sendable, CaseIterable {
    case done, approveAndFindNext, approve, delete, saveAndAddAnother, save, cancel

    public var title: String {
        switch self {
        case .done: "Fertig"
        case .approveAndFindNext: "Bestätigen und weiter"
        case .approve: "Bestätigen"
        case .delete: "Löschen"
        case .saveAndAddAnother: "Sichern und weitere"
        case .save: "Sichern"
        case .cancel: "Abbrechen"
        }
    }

    public var systemImage: String? {
        switch self {
        case .approve: "checkmark"
        case .delete: "trash"
        case .done, .approveAndFindNext, .saveAndAddAnother, .save, .cancel: nil
        }
    }
}

public enum EditorFocus: Hashable, Sendable {
    case field(EditorFieldID)
    case button(EditorButton)

    public var field: EditorFieldID? {
        if case .field(let id) = self { return id }
        return nil
    }
}

/// Keys the editor interprets before the text field edits; `character` is text about to be inserted.
public enum EditorKey: Hashable, Sendable {
    case tab, backTab, enter, escape, space, up, down, pageUp, pageDown, backspace
    case character(String)
}

/// Enter and comma commits are ignored by the row, so they have no reason.
enum CommitReason: Hashable {
    case lostFocus
    case clickedItem(backward: Bool)
}

/// A selection the text field should apply, in UTF-16 offsets.
public struct EditorSelection: Hashable, Sendable {
    public var field: EditorFieldID
    public var range: NSRange
    public var generation: Int
}

public enum EditorMode: Hashable, Sendable {
    case existing
    case new
}

public struct EditorCalculator: Hashable, Sendable {
    public var field: EditorFieldID
    public var calculator: Calculator
}

public struct EditorDateCallout: Hashable, Sendable {
    public var title: String
    public var message: String
}

public enum EditRowMetrics {
    public static let padding: CGFloat = 2
    public static let fieldBandHeight: CGFloat = 28
    public static let fieldHeight: CGFloat = 24
    public static let buttonRowHeight: CGFloat = 32
    public static let subRowHeight: CGFloat = 28
    public static let splitAddRowHeight: CGFloat = 32

    public static func height(subRows: Int?) -> CGFloat {
        let split = subRows.map { CGFloat($0) * subRowHeight + splitAddRowHeight } ?? 0
        return padding + fieldBandHeight + split + buttonRowHeight + padding
    }
}
