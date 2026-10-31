import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct AddCategoryDialogTests {
    @Test func closingTheErrorHandsTheFocusBackToTheForm() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let model = fixture.model()
        model.beginEditing(id, column: .category)
        let editor = try #require(model.editor)
        editor.retype("Hobby: Bücher")
        editor.press(.tab)
        editor.addCategoryConfirmed(masterName: "", name: "Bücher")
        let failed = try #require(editor.addCategoryForm)
        #expect(editor.taskDialog?.instruction == "Bitte einen anderen Kategorienamen wählen.")
        editor.answer(MessageChoice.close)
        let form = try #require(editor.addCategoryForm)
        #expect(!editor.dialogs.isPresenting)
        #expect(form.refocusRequest == failed.refocusRequest + 1)
    }
}
