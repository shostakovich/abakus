import AbakusCore
import AppKit
import Foundation
import Testing

@testable import AbakusMacUI
@testable import AbakusUI
@testable import AbakusUITests

@MainActor
@Suite struct EditorDetailTests {
    @Test func aRejectedDateDoesNotPullALaterClickBack() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries)
        let model = fixture.model()
        model.beginEditing(id)
        let editor = try #require(model.editor)
        editor.retype("99/99/99")
        editor.fieldDidLoseFocus(.main(.date))
        #expect(editor.dateCallout != nil)
        editor.fieldClicked(.main(.payee))
        #expect(editor.focus == .field(.main(.payee)))
    }

    @Test func foldedCompletionSplicesAfterTheMatchedText() {
        let payee = DropDownItem(id: "p", kind: .payee(name: "Großmarkt"), label: "Großmarkt", value: "Großmarkt")
        let (text, range) = DropDownMatching.completion(payee, text: "Gross", caret: 5)
        #expect(text == "Grossmarkt")
        #expect(range == NSRange(location: 5, length: 5))
        let transfer = DropDownItem(
            id: "t", kind: .transfer(accountName: "Savings"), label: "Savings", value: "Transfer : Savings")
        #expect(DropDownMatching.completion(transfer, text: " tra", caret: 4).0 == " transfer : Savings")
    }

    @Test func onlyAmountFieldsTakeTheNumpadSeparator() {
        #expect(EditorTextField.numpadReplacement(".", column: .amount, isNumericPad: true, separator: ",") == ",")
        #expect(EditorTextField.numpadReplacement(".", column: .memo, isNumericPad: true, separator: ",") == nil)
        #expect(EditorTextField.numpadReplacement(".", column: .amount, isNumericPad: false, separator: ",") == nil)
    }

    @Test func completeIsNotEscape() {
        #expect(EditorTextField.command(for: #selector(NSTextView.complete(_:))) == .swallow)
        #expect(EditorTextField.command(for: #selector(NSResponder.cancelOperation(_:))) == .key(.escape))
    }
}
