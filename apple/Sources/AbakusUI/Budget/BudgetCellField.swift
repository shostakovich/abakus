import AppKit
import Carbon.HIToolbox
import SwiftUI

struct BudgetCellField: NSViewRepresentable {
    let model: BudgetViewModel
    let edit: BudgetCellEdit

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> BudgetTextField {
        let view = BudgetTextField()
        view.isBordered = false
        view.isBezeled = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.alignment = .right
        view.lineBreakMode = .byClipping
        view.cell?.isScrollable = true
        view.cell?.wraps = false
        view.cell?.usesSingleLineMode = true
        view.font = BudgetStyle.assignedFont.nsFont
        view.textColor = .labelColor
        view.delegate = context.coordinator
        view.coordinator = context.coordinator
        context.coordinator.view = view
        update(view, context.coordinator)
        return view
    }

    func updateNSView(_ view: BudgetTextField, context: Context) {
        update(view, context.coordinator)
    }

    private func update(_ view: BudgetTextField, _ coordinator: Coordinator) {
        let zero = model.zeroText
        if view.placeholderAttributedString?.string != zero {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            view.placeholderAttributedString = NSAttributedString(
                string: zero,
                attributes: [
                    .font: BudgetStyle.assignedFont.nsFont, .foregroundColor: NSColor.placeholderTextColor,
                    .paragraphStyle: paragraph,
                ])
        }
        coordinator.model = model
        coordinator.cell = edit.cell
        coordinator.sync(edit)
        DispatchQueue.main.async { coordinator.takeFocus(edit) }
    }

    static func dismantleNSView(_ view: BudgetTextField, coordinator: Coordinator) {
        coordinator.isDismantled = true
    }

    enum Command: Hashable {
        case key(BudgetCellKey)
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

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var model: BudgetViewModel?
        var cell: BudgetCellID?
        weak var view: BudgetTextField?
        var isDismantled = false
        private var appliedSelection = 0
        private var isApplying = false

        func sync(_ edit: BudgetCellEdit) {
            guard let view, !isApplying else { return }
            isApplying = true
            defer { isApplying = false }
            if let fieldEditor = view.currentEditor() {
                if fieldEditor.string != edit.text { fieldEditor.string = edit.text }
            } else if view.stringValue != edit.text {
                view.stringValue = edit.text
            }
            if edit.selectAllRequest != appliedSelection, let fieldEditor = view.currentEditor() {
                appliedSelection = edit.selectAllRequest
                fieldEditor.selectedRange = NSRange(location: 0, length: (fieldEditor.string as NSString).length)
            }
        }

        func takeFocus(_ edit: BudgetCellEdit) {
            guard !isDismantled, let view, let window = view.window, model?.editor?.cell == edit.cell,
                model?.calculator == nil
            else { return }
            if view.currentEditor() == nil || window.firstResponder !== view.currentEditor() {
                window.makeFirstResponder(view)
            }
            if let current = model?.editor { sync(current) }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let fieldEditor = view?.currentEditor(), !isApplying else { return }
            model?.cellTextChanged(fieldEditor.string)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard !isApplying, let model, let cell, model.editor?.cell == cell, model.quickBudget == nil else { return }
            model.commitEdit()
        }

        func functionKey(_ event: NSEvent) -> Bool {
            guard let model, event.keyCode == UInt16(kVK_F2) else { return false }
            return model.cellKey(.f2)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let model else { return false }
            switch BudgetCellField.command(for: selector) {
            case .key(let key): return model.cellKey(key)
            case .swallow: return true
            case nil: return false
            }
        }

        func shouldInsert(_ replacement: String, in textView: NSTextView, range: NSRange) -> Bool {
            guard let model, !isApplying else { return true }
            if replacement.count == 1, model.cellKey(.character(replacement)) { return false }
            let allowed = String(replacement.filter(BudgetViewModel.allowsTyping))
            guard allowed != replacement else { return true }
            if !allowed.isEmpty { textView.insertText(allowed, replacementRange: range) }
            return false
        }
    }
}

/// F2 has no key binding, so the field editor would drop it before any delegate sees it.
final class BudgetFieldEditor: NSTextView {
    weak var coordinator: BudgetCellField.Coordinator?

    override func keyDown(with event: NSEvent) {
        if coordinator?.functionKey(event) == true { return }
        super.keyDown(with: event)
    }
}

final class BudgetTextFieldCell: NSTextFieldCell {
    let editor: BudgetFieldEditor = {
        let editor = BudgetFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

final class BudgetTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { BudgetTextFieldCell.self }
        set {}
    }

    weak var coordinator: BudgetCellField.Coordinator? {
        didSet { (cell as? BudgetTextFieldCell)?.editor.coordinator = coordinator }
    }

    /// The numpad's decimal key types the locale's separator; "." from the main keys stays a thousands mark.
    @objc(textView:shouldChangeTextInRange:replacementString:)
    func textView(
        _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?
    ) -> Bool {
        let replacement = replacementString ?? ""
        if let model = coordinator?.model,
            let remapped = EditorTextField.numpadReplacement(
                replacement, column: .outflow,
                isNumericPad: NSApp.currentEvent?.modifierFlags.contains(.numericPad) == true,
                separator: model.formatter.currencyLocale.decimalSeparator)
        {
            textView.insertText(remapped, replacementRange: affectedCharRange)
            return false
        }
        return coordinator?.shouldInsert(replacement, in: textView, range: affectedCharRange) ?? true
    }
}
