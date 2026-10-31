import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct EditPayeesFooterTests {
    @Test func editPayeesOpensForTheTypedPayee() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -2, payee: "Lidl", category: fixture.groceries)
        let id = fixture.add(fixture.giro, -1, payee: "Rewe", category: fixture.groceries)
        let model = fixture.model()
        var opened: [String?] = []
        model.onEditPayees = { opened.append($0) }
        model.beginEditing(id, column: .payee)
        let editor = try #require(model.editor)
        editor.retype("Lid")
        #expect(editor.dropDown?.kind == .payee)
        editor.dropDownFooterClicked()
        #expect(opened == ["Lidl"])
    }
}
