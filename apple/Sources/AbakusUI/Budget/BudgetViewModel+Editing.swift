import AbakusCore
import CoreGraphics
import Foundation
import SwiftUI

public struct BudgetCellID: Hashable, Sendable {
    public let month: DateWithoutTime
    public let categoryId: String

    public init(month: DateWithoutTime, categoryId: String) {
        self.month = month.firstOfMonth
        self.categoryId = categoryId
    }
}

public struct BudgetCellEdit: Hashable, Sendable {
    public let cell: BudgetCellID
    public internal(set) var text: String
    public internal(set) var selectAllRequest = 0
    /// Why the typed text is no amount; the cell keeps it and the focus until it is changed or cancelled.
    public internal(set) var error: String?
    /// Counts every refusal, also of the same text, so each one takes the focus back.
    public internal(set) var refusals = 0
}

public enum BudgetCellKey: Hashable, Sendable {
    case tab, backTab, enter, up, down, escape, pageUp, pageDown
}

extension BudgetViewModel {
    public func assignedText(_ cell: BudgetCellID) -> String {
        let assigned = month(cell.month)?.category(cell.categoryId)?.assigned ?? 0
        return assigned == 0 ? "" : formatter.currencyNoSymbol(assigned)
    }

    public func beginEdit(_ cell: BudgetCellID) {
        guard editor?.cell != cell, commitEdit() else { return }
        guard shownMonths.contains(cell.month), groups.editableCategoryIds.contains(cell.categoryId) else { return }
        editor = BudgetCellEdit(cell: cell, text: assignedText(cell), selectAllRequest: 1)
        reveal(cell.categoryId)
    }

    /// A text field hands its unchanged text back when it loses the focus, which keeps a refusal.
    public func cellTextChanged(_ text: String) {
        guard text != editor?.text else { return }
        editor?.text = text
        editor?.error = nil
    }

    /// False while the edited cell or the sheet's Zugewiesen holds text that is no amount.
    @discardableResult
    public func commitEdit() -> Bool {
        let sheetCommitted = commitSheetAssigned()
        guard let edit = editor else { return sheetCommitted }
        if let error = assign(edit.text, to: edit.cell) {
            editor?.error = error
            editor?.refusals += 1
            announceRefusal(error)
            return false
        }
        editor = nil
        return sheetCommitted
    }

    /// Where the edit cannot stay, such as a month scrolled away, a refused amount is dropped.
    func commitOrDropEdit() {
        guard !commitEdit() else { return }
        cancelEdit()
        dropSheetAssigned()
    }

    public func cancelEdit() {
        editor = nil
    }

    /// Empty text is zero; text that is no sum of amounts keeps the stored one, and the reason is returned.
    @discardableResult
    public func assign(_ text: String, to cell: BudgetCellID) -> String? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard let amount = typed.isEmpty ? 0 : Calculator.evaluate(typed, formatter: formatter) else {
            return InvalidAmount.content(typed)
        }
        setAssigned(amount, in: cell)
        return nil
    }

    func setAssigned(_ amount: Decimal, in cell: BudgetCellID) {
        guard amount != month(cell.month)?.category(cell.categoryId)?.assigned else { return }
        try? store.perform(.setAssigned(month: cell.month, categoryId: cell.categoryId, amount: amount))
        dropStaleUndo()
        callouts.refreshAvailableForm()
    }

    /// The reason stands beside the field, which VoiceOver does not visit on its own.
    func announceRefusal(_ error: String) {
        AccessibilityNotification.Announcement(error).post()
    }

    @discardableResult
    public func cellKey(_ key: BudgetCellKey) -> Bool {
        guard let edit = editor else { return false }
        switch key {
        case .tab, .enter, .down: moveEdit(from: edit.cell, forward: true)
        case .backTab, .up: moveEdit(from: edit.cell, forward: false)
        case .escape: cancelEdit()
        case .pageUp, .pageDown: pageScroll(down: key == .pageDown)
        }
        return true
    }

    /// What a cell keeps of typed or pasted text; the true minus that Abakus writes reads as a sign.
    public static func allowedText(_ text: String) -> String {
        String(text.replacingOccurrences(of: "\u{2212}", with: "-").filter(allowsTyping))
    }

    /// Everything up to "/" passes, so "+" and "−" can be typed and other operators are refused when committed.
    public static func allowsTyping(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return scalar.value <= 0x2F || ("0"..."9").contains(character) || character == "[" || character == "]"
    }

    private func moveEdit(from cell: BudgetCellID, forward: Bool) {
        let order = groups.editableCategoryIds
        guard let index = order.firstIndex(of: cell.categoryId) else { return }
        let next = order[(index + (forward ? 1 : order.count - 1)) % order.count]
        guard next != cell.categoryId else {
            commitEdit()
            beginEdit(cell)
            return
        }
        beginEdit(BudgetCellID(month: cell.month, categoryId: next))
    }

    public func panelKey(_ key: BudgetCellKey) -> Bool {
        switch key {
        case .pageUp, .pageDown:
            pageScroll(down: key == .pageDown)
            return true
        default:
            return false
        }
    }

    public func mouseDownOutsideEditedRow() {
        commitEdit()
    }
}
