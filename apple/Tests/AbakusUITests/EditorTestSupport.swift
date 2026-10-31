import AbakusCore
import Foundation

@testable import AbakusUI

let editDay = day("2014-05-20")

/// Drives the editor like the text field bridge does: keys first, then the text change.
extension TransactionEditor {
    func type(_ string: String) {
        for character in string {
            guard let field = focusedField else { return }
            if handleKey(.character(String(character))) { continue }
            let current = text(field) as NSString
            let range = NSRange(
                location: min(fieldSelection.location, current.length),
                length: min(fieldSelection.length, current.length - min(fieldSelection.location, current.length)))
            let updated = current.replacingCharacters(in: range, with: String(character))
            textDidChange(
                field, text: updated, selection: NSRange(location: range.location + 1, length: 0), isDeletion: false)
        }
    }

    func paste(_ string: String) {
        guard let field = focusedField else { return }
        textDidChange(
            field, text: string, selection: NSRange(location: (string as NSString).length, length: 0),
            isDeletion: false)
    }

    func backspace() {
        guard let field = focusedField, !handleKey(.backspace) else { return }
        let current = text(field) as NSString
        var range = fieldSelection
        if range.length == 0 {
            guard range.location > 0 else { return }
            range = NSRange(location: range.location - 1, length: 1)
        }
        let updated = current.replacingCharacters(in: range, with: "")
        textDidChange(field, text: updated, selection: NSRange(location: range.location, length: 0), isDeletion: true)
    }

    func press(_ keys: EditorKey...) {
        for key in keys { handleKey(key) }
    }

    /// Replaces the whole text of the focused field, as typing over a selection does.
    func retype(_ string: String) {
        guard let field = focusedField else { return }
        selectAll(field)
        if string.isEmpty {
            textDidChange(field, text: "", selection: NSRange(location: 0, length: 0), isDeletion: true)
        }
        type(string)
    }

    var selectedText: String {
        guard let field = focusedField else { return "" }
        let current = text(field) as NSString
        guard NSMaxRange(fieldSelection) <= current.length else { return "" }
        return current.substring(with: fieldSelection)
    }

    var taskDialog: TaskDialog<AnyDialogChoice>? { dialogs.presented.last?.dialog }

    func answer(_ choice: some Hashable & Sendable, isChecked: Bool = false) {
        dialogs.presented.last?.answer(choice, isChecked: isChecked)
    }
}

func decimal(_ text: String) -> Decimal {
    Decimal(string: text)!
}
