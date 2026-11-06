import AbakusCore
import AbakusUI
import AppKit
import SwiftUI

/// The toolbar's search box; Return hands the keys to the list, Escape empties the box, then leaves it.
struct RegisterSearchField: NSViewRepresentable {
    let search: RegisterSearchController
    let text: String
    let prompt: String
    let focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(search: search, focusRequest: focusRequest)
    }

    func makeNSView(context: Context) -> NSSearchField {
        Self.makeField(coordinator: context.coordinator)
    }

    static func makeField(coordinator: Coordinator) -> NSSearchField {
        let field = FocusReportingSearchField()
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = coordinator
        field.target = coordinator
        field.action = #selector(Coordinator.fieldChanged(_:))
        field.sendsSearchStringImmediately = true
        field.onFocus = { [weak coordinator] in coordinator?.search.focusChanged(true) }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        let coordinator = context.coordinator
        coordinator.search = search
        if field.placeholderString != prompt { field.placeholderString = prompt }
        if field.stringValue != text { field.stringValue = text }
        if focusRequest != coordinator.focusRequest {
            coordinator.focusRequest = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var search: RegisterSearchController
        var focusRequest: Int

        init(search: RegisterSearchController, focusRequest: Int) {
            self.search = search
            self.focusRequest = focusRequest
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            fieldChanged(field)
        }

        /// The cancel button clears the field through the action alone.
        @objc func fieldChanged(_ field: NSSearchField) {
            if field.stringValue != search.text { search.boxChanged(field.stringValue) }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            search.focusChanged(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                search.submitted()
            case #selector(NSResponder.cancelOperation(_:)):
                if !search.escapePressed() { control.window?.makeFirstResponder(nil) }
            default:
                return false
            }
            return true
        }
    }

    final class FocusReportingSearchField: NSSearchField {
        var onFocus: () -> Void = {}

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { onFocus() }
            return became
        }
    }
}
