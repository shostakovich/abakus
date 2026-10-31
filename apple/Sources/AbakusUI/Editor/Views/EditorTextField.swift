import AppKit
import SwiftUI

/// The text input of the focused edit cell: an AppKit field whose keys and text changes go to the editor first.
struct EditorTextField: NSViewRepresentable {
    let editor: TransactionEditor
    let field: EditorFieldID
    let font: ThemeFont
    var prompt = ""
    var alignment: NSTextAlignment = .left
    var isActive = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> BridgedTextField {
        let view = BridgedTextField()
        view.isBordered = false
        view.isBezeled = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.lineBreakMode = .byClipping
        view.cell?.isScrollable = true
        view.cell?.wraps = false
        view.cell?.usesSingleLineMode = true
        view.delegate = context.coordinator
        view.coordinator = context.coordinator
        context.coordinator.view = view
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: BridgedTextField, context: Context) {
        update(view, coordinator: context.coordinator)
    }

    private func update(_ view: BridgedTextField, coordinator: Coordinator) {
        coordinator.editor = editor
        coordinator.field = field
        view.font = font.nsFont
        view.textColor = .labelColor
        view.alignment = alignment
        if view.placeholderString != prompt {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            view.placeholderAttributedString = NSAttributedString(
                string: prompt,
                attributes: [
                    .font: font.nsFont, .foregroundColor: NSColor.placeholderTextColor,
                    .paragraphStyle: paragraph,
                ])
        }
        coordinator.syncFromEditor()
        if isActive && editor.focus == .field(field) {
            DispatchQueue.main.async { coordinator.takeFocusIfNeeded() }
        }
    }

    static func dismantleNSView(_ view: BridgedTextField, coordinator: Coordinator) {
        coordinator.isDismantled = true
    }

    enum Command: Equatable {
        case key(EditorKey)
        case swallow
    }

    /// `complete:` (F5, Option-Esc) would open AppKit's word completion.
    static func command(for selector: Selector) -> Command? {
        switch selector {
        case #selector(NSResponder.insertTab(_:)): .key(.tab)
        case #selector(NSResponder.insertBacktab(_:)): .key(.backTab)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)): .key(.enter)
        case #selector(NSResponder.cancelOperation(_:)): .key(.escape)
        case #selector(NSTextView.complete(_:)): .swallow
        case #selector(NSResponder.moveUp(_:)): .key(.up)
        case #selector(NSResponder.moveDown(_:)): .key(.down)
        case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)): .key(.pageUp)
        case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)): .key(.pageDown)
        case #selector(NSResponder.deleteBackward(_:)): .key(.backspace)
        default: nil
        }
    }

    static func numpadReplacement(
        _ replacement: String, column: EditorColumn, isNumericPad: Bool, separator: String
    ) -> String? {
        guard column.isAmount, isNumericPad, replacement == "." || replacement == ",", replacement != separator else {
            return nil
        }
        return separator
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var editor: TransactionEditor?
        var field: EditorFieldID?
        weak var view: BridgedTextField?
        var isDismantled = false
        private var appliedGeneration = -1
        private var isApplying = false
        var pendingDeletion = false

        func syncFromEditor() {
            guard let editor, let field, let view, !isApplying else { return }
            let wanted = editor.text(field)
            isApplying = true
            defer { isApplying = false }
            if let fieldEditor = view.currentEditor() {
                if fieldEditor.string != wanted { fieldEditor.string = wanted }
            } else if view.stringValue != wanted {
                view.stringValue = wanted
            }
            if let request = editor.selectionRequest, request.field == field, request.generation != appliedGeneration,
                let fieldEditor = view.currentEditor()
            {
                appliedGeneration = request.generation
                let length = (fieldEditor.string as NSString).length
                let location = min(request.range.location, length)
                fieldEditor.selectedRange = NSRange(
                    location: location, length: min(request.range.length, length - location))
            }
        }

        func takeFocusIfNeeded() {
            guard !isDismantled, let editor, let field, editor.focus == .field(field), let view,
                let window = view.window
            else { return }
            if view.currentEditor() == nil || window.firstResponder !== view.currentEditor() {
                window.makeFirstResponder(view)
            }
            syncFromEditor()
        }

        private func reportSelection() {
            guard let editor, let field, let fieldEditor = view?.currentEditor() else { return }
            editor.selectionDidChange(field, selection: fieldEditor.selectedRange)
        }

        /// Characters about to be typed: the editor may take them (shortcuts, calculator operators).
        func shouldInsert(_ string: String) -> Bool {
            guard let editor, !isApplying else { return true }
            reportSelection()
            if string.isEmpty {
                pendingDeletion = true
                return true
            }
            pendingDeletion = false
            guard string.count == 1 else { return true }
            if editor.handleKey(.character(string)) {
                syncFromEditor()
                return false
            }
            return true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let editor, let field, let fieldEditor = view?.currentEditor(), !isApplying else { return }
            let deletion = pendingDeletion
            pendingDeletion = false
            editor.textDidChange(
                field, text: fieldEditor.string, selection: fieldEditor.selectedRange, isDeletion: deletion)
            syncFromEditor()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let editor, let field, !isApplying else { return }
            editor.fieldDidLoseFocus(field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let editor else { return false }
            reportSelection()
            guard let command = EditorTextField.command(for: selector) else { return false }
            guard case .key(let key) = command else { return true }
            if key == .backspace { pendingDeletion = true }
            let handled = editor.handleKey(key)
            if handled {
                pendingDeletion = false
                syncFromEditor()
            }
            return handled
        }

        func becameFirstResponder() {
            guard let editor, let field, !isApplying else { return }
            if editor.focus != .field(field) { editor.fieldClicked(field) }
        }
    }
}

final class BridgedTextField: NSTextField {
    weak var coordinator: EditorTextField.Coordinator?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { coordinator?.becameFirstResponder() }
        return became
    }

    @objc(textView:shouldChangeTextInRange:replacementString:)
    func textView(
        _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?
    ) -> Bool {
        let replacement = replacementString ?? ""
        if let column = coordinator?.field?.column,
            let separator = coordinator?.editor?.formatter.currencyLocale.decimalSeparator,
            let remapped = EditorTextField.numpadReplacement(
                replacement, column: column,
                isNumericPad: NSApp.currentEvent?.modifierFlags.contains(.numericPad) == true, separator: separator)
        {
            textView.insertText(remapped, replacementRange: affectedCharRange)
            return false
        }
        return coordinator?.shouldInsert(replacement) ?? true
    }
}
