import AbakusCore
import AbakusUI
import AppKit
import Carbon.HIToolbox
import Foundation

/// Puts the register into an editing state by sending real key events to the offscreen window.
@MainActor
struct EditHarness {
    enum State: String, CaseIterable {
        case existing, new
        case payeeDropdown = "payee-dropdown"
        case categoryDropdown = "category-dropdown"
        case split, errors
        case unassigned, calendar, calculator
        case invalidPayee = "invalid-payee"
        case incomeCheck = "income-check"
        case accountField = "account-field"
    }

    let model: AppModel
    let window: NSWindow
    var trace = false

    private var register: RegisterViewModel { model.register }

    func run(_ state: State) throws {
        settle()
        switch state {
        case .existing:
            let id = try transaction { self.payee($0) == "REWE" }
            try edit(id, column: .memo)
            type("Wochenmarkt statt REWE")
        case .new:
            register.addTransactionClicked()
            settle()
            key(kVK_Tab)
            type("Bäc")
            key(kVK_Tab)
            key(kVK_Escape)
            key(kVK_Tab)
            type("Brötchen")
            key(kVK_Tab)
            type("4,20")
        case .payeeDropdown:
            register.addTransactionClicked()
            settle()
            key(kVK_Tab)
            type("Re")
        case .categoryDropdown:
            let id = try transaction { self.payee($0) == "Aral" }
            try edit(id, column: .category)
            type("🛒 All")
        case .split:
            let id = try transaction { self.payee($0) == "Aral" }
            try edit(id, column: .category)
            type("Aufteilung")
            key(kVK_Tab)
            let editor = try require(register.editor)
            editor.fieldClicked(.sub(editor.subIds[0], .category))
            settle()
            type("🛒 Alltag: ⛽ Tanken")
            key(kVK_Escape)
            key(kVK_Tab)
            type("Tankfüllung")
            key(kVK_Tab)
            type("50")
            key(kVK_Tab)
        case .errors:
            let id = try transaction { self.payee($0) == "Kleinanzeigen" }
            try edit(id, column: .date)
            type("32.13.26")
            key(kVK_Tab)
        case .unassigned:
            try run(.split)
            try require(register.editor).activate(.done)
        case .calendar:
            let id = try transaction { self.payee($0) == "Telekom" }
            try edit(id, column: .date)
            type("+")
        case .calculator:
            let id = try transaction { self.payee($0) == "Telekom" }
            try edit(id, column: .outflow)
            type("*3")
        case .invalidPayee:
            let id = try transaction { self.payee($0) == "Telekom" }
            try edit(id, column: .payee)
            type("Transfer : Sparschwein")
            key(kVK_Tab)
        case .incomeCheck:
            let id = try transaction { self.payee($0) == "Telekom" }
            try edit(id, column: .category)
            type("Zu verteilen")
            key(kVK_Tab)
            key(kVK_Return)
        case .accountField:
            register.navigation.selection = .allAccounts
            settle()
            register.addTransactionClicked()
            settle()
            try require(register.editor).fieldClicked(.main(.account))
        }
        settle()
        if trace, let editor = register.editor { print(Self.describe(editor)) }
    }

    static func describe(_ editor: TransactionEditor) -> String {
        var lines = ["focus: \(editor.focus.map { "\($0)" } ?? "none")"]
        for column in editor.mainColumns() { lines.append("  \(column.rawValue): '\(editor.text(.main(column)))'") }
        for id in editor.subIds {
            lines.append(
                "  sub: " + editor.subColumns().map { "'\(editor.text(.sub(id, $0)))'" }.joined(separator: " "))
        }
        if let list = editor.dropDown {
            lines.append(
                "  list \(list.kind): \(list.items.count) rows, highlighted \(list.highlightedItem?.label ?? "-")")
        }
        if let callout = editor.dateCallout { lines.append("  callout: \(callout.message)") }
        if let calculator = editor.calculator { lines.append("  calculator: \(calculator.calculator.display)") }
        if editor.isCalendarOpen { lines.append("  calendar open") }
        if let dialog = editor.dialogs.presented.last?.dialog { lines.append("  dialog: \(dialog.instruction)") }
        return lines.joined(separator: "\n")
    }

    private func payee(_ transaction: Transaction) -> String {
        model.store.budget.payeeName(of: transaction)
    }

    private func transaction(where predicate: (Transaction) -> Bool) throws -> String {
        guard let match = register.transactions.first(where: predicate) else { throw SnapshotError.render }
        return match.id
    }

    private func require<T>(_ value: T?) throws -> T {
        guard let value else { throw SnapshotError.render }
        return value
    }

    private func edit(_ id: String, column: RegisterColumn) throws {
        guard let row = register.rows.first(where: { $0.id == id }) else { throw SnapshotError.render }
        register.rowClicked(row, column: column, modifiers: [])
        register.rowClicked(row, column: column, modifiers: [])
        settle()
    }

    func type(_ text: String) {
        for character in text {
            send(String(character), keyCode: 0)
        }
        settle()
    }

    func key(_ code: Int, shift: Bool = false) {
        let characters: String
        switch code {
        case kVK_Tab: characters = shift ? "\u{19}" : "\t"
        case kVK_Return: characters = "\r"
        case kVK_Escape: characters = "\u{1B}"
        case kVK_DownArrow: characters = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case kVK_UpArrow: characters = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case kVK_Delete: characters = "\u{7F}"
        default: characters = ""
        }
        send(characters, keyCode: UInt16(code), modifiers: shift ? .shift : [])
        settle()
    }

    func send(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
            else { continue }
            window.sendEvent(event)
        }
    }

    func settle() {
        for _ in 0..<4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }
}
