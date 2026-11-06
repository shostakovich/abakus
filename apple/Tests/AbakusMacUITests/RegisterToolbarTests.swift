import AbakusCore
import AppKit
import SwiftUI
import Testing

@testable import AbakusMacUI
@testable import AbakusUI
@testable import AbakusUITests

@MainActor
@Suite struct RegisterSearchFieldKeyTests {
    @MainActor
    private struct Box {
        let model: RegisterViewModel
        let window: NSWindow
        let field: NSSearchField
        let coordinator: RegisterSearchField.Coordinator

        func type(_ text: String) {
            for character in text { send(String(character), keyCode: 0) }
        }

        func press(_ keyCode: UInt16, _ characters: String) {
            send(characters, keyCode: keyCode)
        }

        private func send(_ characters: String, keyCode: UInt16) {
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                keyCode: keyCode)!
            window.sendEvent(event)
        }
    }

    private static let down = (UInt16(125), String(UnicodeScalar(NSDownArrowFunctionKey)!))
    private static let up = (UInt16(126), String(UnicodeScalar(NSUpArrowFunctionKey)!))

    /// The toolbar's field, focused in a window of its own: keys reach it through the field editor as in the app.
    private func focusedField() -> Box {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -40, payee: "Aral")
        fixture.add(fixture.giro, -60, payee: "Arena")
        let model = fixture.model()
        let coordinator = RegisterSearchField.Coordinator(search: model.search, focusRequest: 0)
        let field = RegisterSearchField.makeField(coordinator: coordinator)
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 22)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        return Box(model: model, window: window, field: field, coordinator: coordinator)
    }

    @Test func focusingTheFieldMarksTheSearchFocused() {
        let box = focusedField()
        #expect(box.model.search.isFocused)
    }

    @Test func typingFiltersAtOnceAndReturnHandsTheFocusToTheGrid() {
        let box = focusedField()
        box.type("aral")
        #expect(box.model.search.text == "aral")
        #expect(box.model.transactions.map { box.model.store.budget.payeeName(of: $0) } == ["Aral"])
        box.press(36, "\r")
        #expect(box.model.gridFocusRequest == 1)
    }

    @Test func upAndDownLeaveTheTextAlone() {
        let box = focusedField()
        box.type("ar")
        box.press(Self.down.0, Self.down.1)
        box.press(Self.up.0, Self.up.1)
        #expect(box.model.search.text == "ar")
        #expect(box.model.transactions.count == 2)
    }

    @Test func escapeEmptiesTheFieldThenLeavesIt() {
        let box = focusedField()
        box.type("aral")
        box.press(53, "\u{1B}")
        #expect(box.model.search.text.isEmpty)
        #expect(box.model.search.isFocused)
        box.press(53, "\u{1B}")
        #expect(!box.model.search.isFocused)
        #expect(box.window.firstResponder !== box.field.currentEditor())
    }

}

@MainActor
@Suite struct RegisterCommandTests {
    @Test func theTransactionsMenuHoldsOnlyNewTransactionAndSearch() {
        #expect(RegisterCommand.allCases.map(\.title) == ["Neue Buchung", "Suchen"])
        #expect(RegisterCommand.matching("n", modifiers: .command) == .addTransaction)
        #expect(RegisterCommand.matching("f", modifiers: .command) == .search)
        #expect(RegisterCommand.matching("k", modifiers: .command) == nil)
        #expect(RegisterCommand.matching("c", modifiers: [.command, .shift]) == nil)
    }

    @Test func newTransactionOpensTheAddEditor() {
        let model = RegisterFixture().model()
        RegisterCommand.addTransaction.perform(in: model)
        #expect(model.editor?.mode == .new)
        #expect(model.editor?.focus == .field(.main(.date)))
        #expect(model.editor?.text(.main(.payee)) == "")
    }

    @Test func searchFocusesTheBox() {
        let model = RegisterFixture().model()
        RegisterCommand.search.perform(in: model)
        #expect(model.search.focusRequest == 1)
    }

    @Test func commandsWaitWhileADialogIsOpen() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries, target: fixture.tagesgeld)
        let model = fixture.model()
        model.deleteTransactions([id])
        #expect(model.dialogs.isPresenting)
        RegisterCommand.search.perform(in: model)
        RegisterCommand.addTransaction.perform(in: model)
        #expect(model.search.focusRequest == 0)
        #expect(model.editor == nil)
    }

    @Test func theTransactionsMenuOnlyServesAShownRegister() {
        let fixture = RegisterFixture()
        let app = AppModel(
            store: BudgetStore(budget: fixture.budget), selection: .account(fixture.giro), defaults: nil)
        #expect(app.showsRegister)
        app.goToBudget()
        #expect(!app.showsRegister)
    }
}
