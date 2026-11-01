import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct PayeeSettingsEntryTests {
    @Test func theActionMenuOpensOnTheFirstSelectedPayee() throws {
        let setup = PayeeSettingsFixture()
        let app = setup.app()
        let row = try #require(app.register.rows.first { $0.id == setup.rewe })
        app.register.rowClicked(row, column: nil, modifiers: .command)
        app.register.performMenuAction(.payeeSettings)
        #expect(app.payeeSettings?.selection == [setup.id(app, "REWE")])
    }

    @Test func theShortcutOpensOnTheSelectedTransaction() throws {
        let setup = PayeeSettingsFixture()
        let app = setup.app()
        let row = try #require(app.register.rows.first { $0.id == setup.aral })
        app.register.rowClicked(row, column: nil, modifiers: .command)
        app.register.payeeSettingsShortcut()
        #expect(app.payeeSettings?.selection == [setup.id(app, "Aral")])
    }

    @Test func editPayeesOpensOnTheTypedPayee() throws {
        let setup = PayeeSettingsFixture()
        let app = setup.app()
        app.register.today = { editDay }
        app.register.beginEditing(setup.aral, column: .payee)
        let editor = try #require(app.register.editor)
        editor.retype("Lid")
        editor.dropDownFooterClicked()
        #expect(editor.dropDown == nil)
        #expect(app.payeeSettings?.selection == [setup.id(app, "Lidl")])
    }
}

@MainActor
@Suite struct PayeeSettingsAutoFillTests {
    @Test func theFooterSettingsArePreferences() throws {
        let setup = PayeeSettingsFixture()
        let storage = MemorySettingsStorage()
        let app = setup.app(storage: storage)
        #expect(app.register.autoFillSettings == AutoFillSettings())
        let dialog = try setup.dialog(app)
        dialog.setAutoFill(AutoFillSettings(category: false, memo: true, amount: true))
        #expect(app.register.autoFillSettings == AutoFillSettings(category: false, memo: true, amount: true))
        #expect(storage.string(forKey: "shouldAutofillMemo") == "true")
        #expect(setup.app(storage: storage).register.autoFillSettings.amount)
    }

    @Test func theEditorFillsMemoAndAmountWhenSwitchedOn() throws {
        var fixture = RegisterFixture()
        let bakery = Transaction(
            accountId: fixture.giro, date: editDay, categoryId: fixture.groceries, memo: "Brötchen", amount: -4.5)
        try fixture.budget.apply(
            .saveTransaction(TransactionSave(transaction: bakery, payeeName: "Bakery", isNew: true)))
        let model = fixture.model()
        model.autoFillSettings = AutoFillSettings(category: true, memo: true, amount: true)
        model.addTransactionClicked()
        let editor = try #require(model.editor)
        editor.fieldClicked(.main(.payee))
        editor.type("Bak")
        editor.press(.tab)
        #expect(editor.clone.categoryId == fixture.groceries)
        #expect(editor.clone.memo == "Brötchen")
        #expect(editor.clone.amount == -4.5)
        #expect(editor.text(.main(.memo)) == "Brötchen")
        #expect(editor.text(.main(.amount)) == "4.50")
    }

    @Test func theEditorKeepsMemoAndAmountByDefault() throws {
        var fixture = RegisterFixture()
        let bakery = Transaction(
            accountId: fixture.giro, date: editDay, categoryId: fixture.groceries, memo: "Brötchen", amount: -4.5)
        try fixture.budget.apply(
            .saveTransaction(TransactionSave(transaction: bakery, payeeName: "Bakery", isNew: true)))
        let model = fixture.model()
        model.addTransactionClicked()
        let editor = try #require(model.editor)
        editor.fieldClicked(.main(.payee))
        editor.type("Bak")
        editor.press(.tab)
        #expect(editor.clone.memo == nil || editor.clone.memo == "")
        #expect(editor.clone.amount == 0)
    }
}
