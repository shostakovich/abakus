import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct AppSheetTests {
    @Test func aFormIsShownAsTheWindowsSheetUntilItCloses() throws {
        let app = AppModel(store: BudgetStore(budget: RegisterFixture().budget), defaults: nil)
        #expect(app.sheet == nil)
        app.accounts.addAccountClicked()
        let form = try #require(app.accounts.addForm)
        #expect(app.sheet?.id == form.id)
        app.accounts.addCancelled()
        #expect(app.sheet == nil)
    }

    @Test func anEditorsNewCategoryCoversTheOtherForms() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let app = AppModel(store: BudgetStore(budget: fixture.budget), defaults: nil)
        app.register.beginEditing(id, column: .category)
        let editor = try #require(app.register.editor)
        editor.retype("Hobby: Bücher")
        editor.press(.tab)
        app.accounts.addAccountClicked()
        let category = try #require(editor.addCategoryForm)
        #expect(app.sheet?.id == category.id)
        editor.addCategoryCancelled()
        #expect(app.sheet?.id == app.accounts.addForm?.id)
    }

    @Test func payeeSettingsStaysTheSheetWhileItsNewCategoryCoversIt() throws {
        let setup = PayeeSettingsFixture()
        let app = setup.app()
        let payees = try setup.dialog(app, on: "Aral")
        #expect(app.sheet?.id == payees.id)
        payees.categoryTextChanged("Hobby: Bücher")
        payees.commitCategory()
        let form = try #require(payees.addCategoryForm)
        #expect(app.sheet?.id == payees.id)
        #expect(payees.addCategoryRequest?.id == form.id)
        payees.addCategoryCancelled()
        #expect(payees.addCategoryRequest?.id == nil)
        payees.close()
        #expect(app.sheet == nil)
    }
}
