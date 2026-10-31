import AbakusCore
import Foundation

public struct TaskDialog<Choice: Hashable & Sendable>: Hashable, Sendable {
    public struct CommandLink: Hashable, Sendable {
        public var choice: Choice
        public var title: String
        public var detail: String
        public var isDefault: Bool

        public init(_ choice: Choice, title: String, detail: String, isDefault: Bool = false) {
            self.choice = choice
            self.title = title
            self.detail = detail
            self.isDefault = isDefault
        }
    }

    public struct Button: Hashable, Sendable {
        public var choice: Choice
        public var title: String
        public var isDefault: Bool

        public init(_ choice: Choice, title: String, isDefault: Bool = false) {
            self.choice = choice
            self.title = title
            self.isDefault = isDefault
        }
    }

    public var title: String?
    /// `instruction` and `content` may carry `<b>` and `<br/>` markup.
    public var instruction: String
    public var content: String
    public var commandLinks: [CommandLink]
    public var buttons: [Button]
    public var checkbox: String?
    /// What Escape answers.
    public var dismissal: Choice

    public init(
        title: String? = nil, instruction: String, content: String,
        commandLinks: [CommandLink] = [], buttons: [Button], checkbox: String? = nil, dismissal: Choice
    ) {
        self.title = title
        self.instruction = instruction
        self.content = content
        self.commandLinks = commandLinks
        self.buttons = buttons
        self.checkbox = checkbox
        self.dismissal = dismissal
    }

    /// What Return answers.
    public var defaultChoice: Choice? {
        commandLinks.first(where: \.isDefault)?.choice ?? buttons.first(where: \.isDefault)?.choice
    }

    public func offers(_ choice: Choice) -> Bool {
        choice == dismissal || buttons.contains { $0.choice == choice } || commandLinks.contains { $0.choice == choice }
    }

    public func map<Other>(_ transform: (Choice) -> Other) -> TaskDialog<Other> {
        TaskDialog<Other>(
            title: title, instruction: instruction, content: content,
            commandLinks: commandLinks.map {
                .init(transform($0.choice), title: $0.title, detail: $0.detail, isDefault: $0.isDefault)
            },
            buttons: buttons.map { .init(transform($0.choice), title: $0.title, isDefault: $0.isDefault) },
            checkbox: checkbox, dismissal: transform(dismissal))
    }
}

public struct TaskDialogAnswer<Choice: Hashable & Sendable>: Hashable, Sendable {
    public var choice: Choice
    public var isChecked: Bool

    public init(choice: Choice, isChecked: Bool = false) {
        self.choice = choice
        self.isChecked = isChecked
    }
}

public enum MessageChoice: Hashable, Sendable {
    case close
}

extension TaskDialog where Choice == MessageChoice {
    public static func message(_ instruction: String, _ content: String) -> Self {
        TaskDialog(
            instruction: instruction, content: content,
            buttons: [Button(.close, title: "OK", isDefault: true)], dismissal: .close)
    }

    /// Only Konto hinzufügen shows the typed text in bold.
    public static func invalidBalance(_ text: String, bold: Bool = false) -> Self {
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return .message(InvalidBalance.instruction, InvalidBalance.content(escaped, bold: bold))
    }
}

public struct AddCategoryForm: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var masterName: String
    public var name: String
    /// Closing the error dialog hands the focus back to a field, as Flex's focus manager does after a popup.
    public internal(set) var refocusRequest = 0

    public init(masterName: String, name: String) {
        self.masterName = masterName
        self.name = name
    }
}
