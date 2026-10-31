import Foundation
import Observation

/// A choice of any dialog, so that dialogs with different choice enums share one stack.
public struct AnyDialogChoice: Hashable, Sendable {
    public let base: any Hashable & Sendable

    public init(_ base: some Hashable & Sendable) {
        self.base = (base as? AnyDialogChoice)?.base ?? base
    }

    public static func == (lhs: AnyDialogChoice, rhs: AnyDialogChoice) -> Bool {
        AnyHashable(lhs.base) == AnyHashable(rhs.base)
    }

    public func hash(into hasher: inout Hasher) {
        AnyHashable(base).hash(into: &hasher)
    }
}

public struct PresentedDialog: Identifiable {
    public let id: UUID
    public let dialog: TaskDialog<AnyDialogChoice>
    let owner: ObjectIdentifier?
    private let respond: @MainActor (TaskDialogAnswer<AnyDialogChoice>) -> Void

    init<Choice>(
        _ dialog: TaskDialog<Choice>, id: UUID = UUID(), owner: AnyObject? = nil,
        then respond: @escaping @MainActor (TaskDialogAnswer<Choice>) -> Void
    ) {
        self.id = id
        self.dialog = dialog.map(AnyDialogChoice.init)
        self.owner = owner.map(ObjectIdentifier.init)
        self.respond = { answer in
            guard let choice = answer.choice.base as? Choice else { return }
            respond(TaskDialogAnswer(choice: choice, isChecked: answer.isChecked))
        }
    }

    @MainActor
    public func answer(_ choice: some Hashable & Sendable, isChecked: Bool = false) {
        let choice = AnyDialogChoice(choice)
        guard dialog.offers(choice) else { return }
        respond(TaskDialogAnswer(choice: choice, isChecked: isChecked))
    }
}

@MainActor
@Observable
public final class DialogStack {
    public private(set) var presented: [PresentedDialog] = []

    public init() {}

    public var isPresenting: Bool { !presented.isEmpty }

    func isPresenting(ownedBy owner: AnyObject) -> Bool {
        presented.contains { $0.owner == ObjectIdentifier(owner) }
    }

    /// Answering removes the dialog before the continuation runs, so the continuation may ask again.
    public func ask<Choice>(
        _ dialog: TaskDialog<Choice>, owner: AnyObject? = nil,
        then continuation: @escaping @MainActor (TaskDialogAnswer<Choice>) -> Void
    ) {
        let id = UUID()
        presented.append(
            PresentedDialog(dialog, id: id, owner: owner) { [weak self] answer in
                guard let self, let index = presented.firstIndex(where: { $0.id == id }) else { return }
                presented.remove(at: index)
                continuation(answer)
            })
    }

    public func show(
        _ message: TaskDialog<MessageChoice>, owner: AnyObject? = nil,
        then continuation: @escaping @MainActor () -> Void = {}
    ) {
        ask(message, owner: owner) { _ in continuation() }
    }

    /// Drops the owner's unanswered dialogs without answering them: an editor that ends, a newer clock question.
    func dismiss(ownedBy owner: AnyObject) {
        presented.removeAll { $0.owner == ObjectIdentifier(owner) }
    }
}
