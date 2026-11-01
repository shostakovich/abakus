import AbakusCore
import AppKit
import SwiftUI
import Testing

@testable import AbakusUI

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

    @Test func upAndDownMoveTheHighlightThroughTheSuggestions() throws {
        let box = focusedField()
        box.type("Empfänger: Ar")
        #expect(box.model.search.text == "Empfänger: Ar")
        let count = try #require(box.model.search.dropDown?.items.count)
        #expect(count >= 2)
        #expect(box.model.search.dropDown?.highlighted == nil)
        box.press(Self.down.0, Self.down.1)
        box.press(Self.down.0, Self.down.1)
        #expect(box.model.search.dropDown?.highlighted == 1)
        box.press(Self.up.0, Self.up.1)
        #expect(box.model.search.dropDown?.highlighted == 0)
        box.press(Self.up.0, Self.up.1)
        #expect(box.model.search.dropDown?.highlighted == 0)
    }

    @Test func returnPicksTheHighlightedSuggestionAndKeepsTypingInTheField() throws {
        let box = focusedField()
        box.type("Empfänger: Ar")
        let items = try #require(box.model.search.dropDown?.items)
        let index = try #require(items.firstIndex { !$0.searchText.isEmpty })
        for _ in 0...index { box.press(Self.down.0, Self.down.1) }
        let picked = items[index].searchText
        box.press(36, "\r")
        #expect(box.model.search.text == picked + ", ")
        #expect(box.model.search.filter?.label == picked)
        #expect(box.model.search.dropDown == nil)
        #expect(box.model.gridFocusRequest == 0)
    }

    @Test func returnWithoutAHighlightRunsTheTypedSearchAndHandsTheFocusToTheGrid() {
        let box = focusedField()
        box.type("aral")
        box.press(36, "\r")
        #expect(box.model.search.filter?.label == "aral")
        #expect(box.model.gridFocusRequest == 1)
    }

    @Test func escapeClosesTheSuggestionsThenEmptiesTheFieldThenLeavesIt() {
        let box = focusedField()
        box.type("aral")
        #expect(box.model.search.dropDown != nil)
        box.press(53, "\u{1B}")
        #expect(box.model.search.dropDown == nil)
        #expect(box.model.search.text == "aral")
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
    @Test func theRegistersKeyEquivalentsAreMenuCommands() {
        #expect(RegisterCommand.matching("n", modifiers: .command) == .addTransaction)
        #expect(RegisterCommand.matching("k", modifiers: .command) == .approve)
        #expect(RegisterCommand.matching("c", modifiers: [.command, .shift]) == .toggleCleared)
        #expect(RegisterCommand.matching("f", modifiers: .command) == .search)
        let shortcuts = RegisterCommand.allCases.compactMap(\.shortcut)
        #expect(Set(shortcuts.map { "\($0.key.character)\($0.modifiers.rawValue)" }).count == shortcuts.count)
    }

    @Test func theAddMenuCommandsOpenANewTransactionOrTransfer() {
        let fixture = RegisterFixture()
        let model = fixture.model()
        RegisterCommand.addTransaction.perform(in: model)
        #expect(model.editor?.mode == .new)
        #expect(model.editor?.focus == .field(.main(.date)))
        model.grid.cancelEditing()
        RegisterCommand.makeTransfer.perform(in: model)
        #expect(model.editor?.mode == .new)
        #expect(model.editor?.text(.main(.payee)) == Payee.transferPrefix)
    }

    @Test func aTransferNeedsAnotherOpenAccount() throws {
        var single = Budget(budgetName: "Single")
        try single.apply(
            .addAccount(
                NewAccount(
                    id: "ONLY", name: "Only", kind: .cash, startingBalance: 1,
                    startDate: day("2014-01-01"))))
        let model = RegisterViewModel(
            store: BudgetStore(budget: single), navigation: NavigationState(selection: .account("ONLY")))
        #expect(RegisterCommand.addTransaction.isEnabled(in: model))
        #expect(!RegisterCommand.makeTransfer.isEnabled(in: model))
        RegisterCommand.makeTransfer.perform(in: model)
        #expect(model.editor == nil)
    }

    @Test func showReconciledTogglesAndRestsWhileSearching() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "REWE")
        let model = fixture.model()
        RegisterCommand.showReconciled.perform(in: model)
        #expect(!model.isShowingReconciled)
        model.search.run("rewe")
        #expect(!RegisterCommand.showReconciled.isEnabled(in: model))
        RegisterCommand.showReconciled.perform(in: model)
        #expect(!model.isShowingReconciled)
    }

    @Test func searchAndTimeframeFocusTheBoxAndOpenTheDateFilter() {
        let model = RegisterFixture().model()
        RegisterCommand.search.perform(in: model)
        #expect(model.search.focusRequest == 1)
        RegisterCommand.timeframe.perform(in: model)
        #expect(model.popup == .timeframe)
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

    @Test func approveAndToggleClearedActOnTheSelection() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -5, payee: "REWE")
        let model = fixture.model()
        let row = try #require(model.rows.first { $0.id == id })
        model.rowClicked(row, column: .payee, modifiers: [])
        let before = model.store.budget.transaction(withId: id)?.cleared
        RegisterCommand.toggleCleared.perform(in: model)
        #expect(model.store.budget.transaction(withId: id)?.cleared != before)
    }

    @Test func theMenuBarsEditTransactionsItemsActOnTheSelection() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -5, payee: "REWE")
        let model = fixture.model()
        let row = try #require(model.rows.first { $0.id == id })
        model.rowClicked(row, column: .payee, modifiers: [])
        let items = model.transactionActionsMenu(withTitle: false)
        #expect(items.item(titled: "Als gebucht markieren")?.isEnabled == true)
        model.editTransactionsCommandChosen(.markCleared)
        #expect(model.store.budget.transaction(withId: id)?.cleared == .cleared)
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
