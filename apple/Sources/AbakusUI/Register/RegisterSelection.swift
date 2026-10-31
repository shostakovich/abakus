public struct RegisterClickModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = RegisterClickModifiers(rawValue: 1)
    public static let shift = RegisterClickModifiers(rawValue: 2)
}

public struct RegisterSelection: Hashable, Sendable {
    public enum ClickResult: Hashable, Sendable {
        case selectionChanged
        case beginEdit
    }

    public private(set) var ids: Set<String> = []
    public private(set) var anchor: String?
    public private(set) var caret: String?
    /// The caret index outlives its row, so the arrows go on from where a deleted row was.
    private var caretIndex: Int?

    public init() {}

    public var count: Int { ids.count }
    public var isEmpty: Bool { ids.isEmpty }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    public func ordered(by order: [String]) -> [String] {
        order.filter(ids.contains)
    }

    public mutating func click(_ id: String, modifiers: RegisterClickModifiers, order: [String]) -> ClickResult {
        if modifiers.contains(.shift), let anchor, let range = range(from: anchor, to: id, in: order) {
            ids = Set(range)
            caret = id
            return .selectionChanged
        }
        if modifiers.contains(.command) {
            toggle(id)
            return .selectionChanged
        }
        if ids == [id] && modifiers.isEmpty { return .beginEdit }
        select(id)
        return .selectionChanged
    }

    public mutating func select(_ id: String) {
        ids = [id]
        anchor = id
        caret = id
    }

    public mutating func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        anchor = id
        caret = id
    }

    public mutating func selectAll(_ order: [String]) {
        ids = Set(order)
        anchor = order.first
        caret = order.last
    }

    public mutating func clear() {
        self = RegisterSelection()
    }

    /// `caretOnly` is Cmd+arrow.
    @discardableResult
    public mutating func moveCaret(by offset: Int, extending: Bool, caretOnly: Bool = false, order: [String])
        -> String?
    {
        guard !order.isEmpty else { return nil }
        let target: String
        if let caret, let index = order.firstIndex(of: caret) {
            target = order[min(max(index + offset, 0), order.count - 1)]
        } else if let caretIndex {
            let index = offset > 0 ? caretIndex + offset - 1 : caretIndex + offset
            target = order[min(max(index, 0), order.count - 1)]
        } else {
            target = offset >= 0 ? order[0] : order[order.count - 1]
        }
        if caretOnly {
            caret = target
        } else if extending, let anchor, let range = range(from: anchor, to: target, in: order) {
            ids = Set(range)
            caret = target
        } else {
            select(target)
        }
        return target
    }

    mutating func rememberCaretIndex(in order: [String]) {
        guard let caret else { return }
        caretIndex = order.firstIndex(of: caret) ?? caretIndex
    }

    public mutating func retain(_ visible: Set<String>) {
        ids.formIntersection(visible)
        if let anchor, !visible.contains(anchor) { self.anchor = nil }
        if let caret, !visible.contains(caret) { self.caret = nil }
    }

    private func range(from start: String, to end: String, in order: [String]) -> ArraySlice<String>? {
        guard let first = order.firstIndex(of: start), let last = order.firstIndex(of: end) else { return nil }
        return order[min(first, last)...max(first, last)]
    }
}
