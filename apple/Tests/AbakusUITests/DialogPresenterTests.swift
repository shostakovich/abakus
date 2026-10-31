import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

private enum Pick: Hashable, Sendable {
    case yes, no
}

@MainActor
private final class SpyPresentation: DialogPresentation {
    var shown: [(id: UUID, instruction: String)] = []
    var closed: [UUID] = []
    var answers: [UUID: @MainActor (AnyDialogChoice, Bool) -> Void] = [:]

    func show(
        _ dialog: TaskDialog<AnyDialogChoice>, id: UUID,
        onAnswer: @escaping @MainActor (AnyDialogChoice, Bool) -> Void
    ) {
        shown.append((id, dialog.instruction))
        answers[id] = onAnswer
    }

    func close(_ id: UUID) {
        closed.append(id)
    }
}

@MainActor
@Suite struct DialogPresenterTests {
    private func question(_ instruction: String) -> TaskDialog<Pick> {
        TaskDialog(
            instruction: instruction, content: "",
            buttons: [.init(.yes, title: "Yes", isDefault: true), .init(.no, title: "No")], dismissal: .no)
    }

    @Test func showsEachNewDialogOnTopOnce() {
        let stack = DialogStack()
        let spy = SpyPresentation()
        let presenter = DialogPresenter(presentation: spy)
        stack.ask(question("first")) { _ in }
        presenter.update(stack.presented)
        stack.ask(question("second")) { _ in }
        presenter.update(stack.presented)
        presenter.update(stack.presented)
        #expect(spy.shown.map(\.instruction) == ["first", "second"])
        #expect(spy.closed.isEmpty)
    }

    @Test func anAnswerGoesToTheStackWithoutClosingTheAnsweredSheet() throws {
        let stack = DialogStack()
        let spy = SpyPresentation()
        let presenter = DialogPresenter(presentation: spy)
        var answers: [TaskDialogAnswer<Pick>] = []
        stack.ask(question("q")) { answers.append($0) }
        presenter.update(stack.presented)
        let id = try #require(spy.shown.first?.id)
        let answer = try #require(spy.answers[id])
        answer(AnyDialogChoice(Pick.yes), true)
        presenter.update(stack.presented)
        #expect(answers == [TaskDialogAnswer(choice: .yes, isChecked: true)])
        #expect(spy.closed.isEmpty)
    }

    @Test func aDialogDroppedWithoutAnswerClosesWithTheOnesAboveIt() {
        let stack = DialogStack()
        let spy = SpyPresentation()
        let presenter = DialogPresenter(presentation: spy)
        let owner = NSObject()
        stack.ask(question("below")) { _ in }
        stack.ask(question("owned"), owner: owner) { _ in }
        stack.ask(question("above")) { _ in }
        presenter.update(stack.presented)
        let ids = spy.shown.map(\.id)
        stack.dismiss(ownedBy: owner)
        presenter.update(stack.presented)
        #expect(spy.closed == [ids[2], ids[1]])
        #expect(spy.shown.map(\.instruction) == ["below", "owned", "above", "above"])
    }

    @Test func aDialogWhoseTextChangedIsShownAnew() {
        let spy = SpyPresentation()
        let presenter = DialogPresenter(presentation: spy)
        let id = UUID()
        presenter.update([PresentedDialog(question("old"), id: id) { _ in }])
        presenter.update([PresentedDialog(question("new"), id: id) { _ in }])
        #expect(spy.closed == [id])
        #expect(spy.shown.map(\.instruction) == ["old", "new"])
    }
}
