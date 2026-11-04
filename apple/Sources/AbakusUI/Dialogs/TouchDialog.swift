import Foundation

/// The command links' details join the message, and a checkbox gives each answer a second, checked button.
public struct TouchDialog: Hashable, Sendable {
    public struct Answer: Hashable, Sendable {
        public let title: String
        public let choice: AnyDialogChoice
        public let isChecked: Bool
        public let isCancel: Bool
    }

    public let title: String
    public let message: String
    public let answers: [Answer]

    public init(_ dialog: TaskDialog<AnyDialogChoice>) {
        title = TextMarkup.plain(dialog.instruction.isEmpty ? dialog.title ?? "" : dialog.instruction)
        let details = dialog.commandLinks.map { "\($0.title): \($0.detail)" }
        message = ([TextMarkup.plain(dialog.content)] + details)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let offered = dialog.commandLinks.map { ($0.choice, $0.title) } + dialog.buttons.map { ($0.choice, $0.title) }
        let plain = offered.map { choice, title in
            Answer(title: title, choice: choice, isChecked: false, isCancel: choice == dialog.dismissal)
        }
        guard let checkbox = dialog.checkbox else {
            answers = plain
            return
        }
        let checked = plain.filter { !$0.isCancel }.map { answer in
            Answer(
                title: answer.title + ", " + checkbox.prefix(1).lowercased() + checkbox.dropFirst(),
                choice: answer.choice, isChecked: true, isCancel: false)
        }
        answers = plain.filter { !$0.isCancel } + checked + plain.filter(\.isCancel)
    }
}
