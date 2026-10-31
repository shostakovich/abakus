import AppKit

/// A task dialog without command links as a system alert with the app icon.
@MainActor
struct DialogAlert {
    let alert = NSAlert()
    private let choices: [AnyDialogChoice]
    private let dismissal: AnyDialogChoice
    /// No button answers the dismissal, so Escape needs its own handling.
    let escapesWithoutButton: Bool

    init(_ dialog: TaskDialog<AnyDialogChoice>) {
        let defaultButton = dialog.buttons.first(where: \.isDefault)
        let cancelButton = dialog.buttons.first { $0.choice == dialog.dismissal && !$0.isDefault }
        let otherButtons = dialog.buttons.filter { $0 != defaultButton && $0 != cancelButton }
        let ordered = [defaultButton].compactMap(\.self) + otherButtons + [cancelButton].compactMap(\.self)
        alert.icon = NSApplication.shared.applicationIconImage
        alert.messageText = TextMarkup.plain(dialog.instruction.isEmpty ? dialog.title ?? "" : dialog.instruction)
        alert.informativeText = TextMarkup.plain(dialog.content)
        for button in ordered {
            let added = alert.addButton(withTitle: button.title)
            added.keyEquivalent = button == defaultButton ? "\r" : button == cancelButton ? "\u{1B}" : ""
        }
        if let checkbox = dialog.checkbox {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = checkbox
        }
        choices = ordered.map(\.choice)
        dismissal = dialog.dismissal
        escapesWithoutButton = cancelButton == nil
    }

    var isSuppressed: Bool { alert.suppressionButton?.state == .on }

    func choice(for response: NSApplication.ModalResponse) -> AnyDialogChoice {
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return choices.indices.contains(index) ? choices[index] : dismissal
    }
}
