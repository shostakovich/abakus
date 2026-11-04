import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

private enum Pick: Hashable, Sendable {
    case yes, no, maybe
}

@MainActor
@Suite struct DialogStackTests {
    private func question(_ instruction: String, dismissal: Pick = .no) -> TaskDialog<Pick> {
        TaskDialog(
            instruction: instruction, content: "",
            buttons: [.init(.no, title: "No"), .init(.yes, title: "Yes", isDefault: true)], dismissal: dismissal)
    }

    @Test func aTouchAlertOffersTheCheckboxWithEachAnswerAndShowsTheDetails() throws {
        let dialog = TransactionEditor.payeeRenameDialog(
            oldName: "REWE SAGT DANKE", newName: "Rewe", matches: 3, uncategorized: 0, categoryName: nil)
        let alert = TouchDialog(dialog.map(AnyDialogChoice.init))
        #expect(alert.title == "Passende Buchungen auch ändern?")
        #expect(alert.message.contains("Umbenennen: 3 passende Buchungen in „Rewe“ umbenennen"))
        #expect(alert.message.contains("Unverändert lassen: Nur diese Buchung ändern, die anderen nicht."))
        #expect(
            alert.answers.map(\.title) == [
                "Umbenennen", "Unverändert lassen", "Umbenennen, bei diesem Empfänger nicht mehr fragen",
                "Unverändert lassen, bei diesem Empfänger nicht mehr fragen", "Abbrechen",
            ])
        #expect(alert.answers.map(\.isChecked) == [false, false, true, true, false])
        #expect(alert.answers.last?.isCancel == true)

        let stack = DialogStack()
        var checked: Bool?
        stack.ask(dialog) { checked = $0.isChecked }
        let answer = try #require(alert.answers.first { $0.isChecked })
        stack.presented.last?.answer(answer.choice, isChecked: answer.isChecked)
        #expect(checked == true)
    }

    @Test func aTouchAlertWithoutAnInstructionTakesTheTitle() {
        let dialog = TaskDialog<Pick>(
            title: "Fehler", instruction: "", content: "", buttons: [.init(.yes, title: "OK")], dismissal: .yes)
        #expect(TouchDialog(dialog.map(AnyDialogChoice.init)).title == "Fehler")
    }

    @Test func dialogsStackInTheOrderTheyWereAsked() {
        let stack = DialogStack()
        #expect(!stack.isPresenting)
        stack.ask(question("first")) { _ in }
        stack.show(.message("second", ""))
        #expect(stack.presented.map(\.dialog.instruction) == ["first", "second"])
        #expect(stack.isPresenting)
    }

    @Test func answeringRemovesTheDialogBeforeTheContinuationRuns() throws {
        let stack = DialogStack()
        var answers: [TaskDialogAnswer<Pick>] = []
        var shownDuringContinuation: [String] = []
        stack.ask(question("below")) { _ in }
        stack.ask(question("top")) { answer in
            answers.append(answer)
            shownDuringContinuation = stack.presented.map(\.dialog.instruction)
        }
        try #require(stack.presented.last).answer(Pick.yes, isChecked: true)
        #expect(answers == [TaskDialogAnswer(choice: .yes, isChecked: true)])
        #expect(shownDuringContinuation == ["below"])
        #expect(stack.presented.map(\.dialog.instruction) == ["below"])
    }

    @Test func theCloseBoxAndEscapeAnswerTheDismissal() throws {
        let stack = DialogStack()
        var answers: [Pick] = []
        stack.ask(question("q", dismissal: .yes)) { answers.append($0.choice) }
        let entry = try #require(stack.presented.last)
        #expect(entry.dialog.dismissal == AnyDialogChoice(Pick.yes))
        #expect(entry.dialog.defaultChoice == AnyDialogChoice(Pick.yes))
        entry.answer(entry.dialog.dismissal)
        #expect(answers == [.yes])
    }

    @Test func aContinuationMayAskAgain() throws {
        let stack = DialogStack()
        var answers: [Pick] = []
        stack.ask(question("first")) { _ in
            stack.ask(question("second")) { answers.append($0.choice) }
        }
        try #require(stack.presented.last).answer(Pick.yes)
        #expect(stack.presented.map(\.dialog.instruction) == ["second"])
        try #require(stack.presented.last).answer(Pick.no)
        #expect(answers == [.no])
        #expect(!stack.isPresenting)
    }

    @Test func aDialogTakesOneAnswerAndOnlyAChoiceItOffers() throws {
        let stack = DialogStack()
        var answers: [Pick] = []
        stack.ask(question("q")) { answers.append($0.choice) }
        let entry = try #require(stack.presented.last)
        entry.answer(Pick.maybe)
        entry.answer(MessageChoice.close)
        #expect(stack.isPresenting)
        entry.answer(Pick.yes)
        entry.answer(Pick.yes)
        #expect(answers == [.yes])
    }

    @Test func anOwnerTakesItsUnansweredDialogsAlong() {
        let stack = DialogStack()
        let owner = NSObject()
        stack.show(.message("other", ""))
        stack.show(.message("owned", ""), owner: owner)
        stack.dismiss(ownedBy: owner)
        #expect(stack.presented.map(\.dialog.instruction) == ["other"])
    }

    @Test func theWindowSharesOneStack() throws {
        let fixture = RegisterFixture()
        let app = AppModel(
            store: BudgetStore(budget: fixture.budget, today: { editDay }), selection: .account(fixture.giro),
            defaults: nil)
        #expect(app.register.dialogs === app.dialogs)
        #expect(app.accounts.dialogs === app.dialogs)
        app.register.grid.beginNew()
        #expect(try #require(app.register.editor).dialogs === app.dialogs)
        app.register.editor?.cancel()
        app.register.scheduler.grid.beginNew()
        #expect(try #require(app.register.scheduler.editor).dialogs === app.dialogs)
        app.register.scheduler.grid.cancelEditing()
        app.openPayeeSettings(payeeName: nil)
        #expect(try #require(app.payeeSettings).dialogs === app.dialogs)
    }

    @Test func anEditorThatEndsTakesItsDialogAlong() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4, cleared: .reconciled)
        let (model, store) = fixture.spied()
        model.beginEditing(id, column: .amount)
        let editor = try #require(model.editor)
        editor.retype("5")
        editor.activate(.done)
        model.showMessage("Register", "")
        #expect(model.dialogs.presented.count == 2)
        editor.cancel()
        #expect(model.dialogs.presented.map(\.dialog.instruction) == ["Register"])
        #expect(store.commands.isEmpty)
    }
}
