import AbakusCore
import Foundation
import SwiftUI
import Testing

@testable import AbakusUI

@Suite struct DropDownMatchingTests {
    let transfer = DropDownItem(
        id: "t", kind: .transfer(accountName: "Tagesgeld"), label: "Tagesgeld", value: "Transfer : Tagesgeld")
    let payee = DropDownItem(id: "p", kind: .payee(name: "Walmart"), label: "Walmart", value: "Walmart")

    @Test func transferRowsMatchThePrefixOfTransferAndTheAccount() {
        #expect(
            DropDownMatching.transferMatches("Transfer : Tagesgeld", accountName: "Tagesgeld", text: "tr", prefix: true)
        )
        #expect(
            DropDownMatching.transferMatches(
                "Transfer : Tagesgeld", accountName: "Tagesgeld", text: "tr:ta", prefix: true))
        #expect(
            !DropDownMatching.transferMatches(
                "Transfer : Tagesgeld", accountName: "Tagesgeld", text: "tr:x", prefix: true))
        #expect(
            DropDownMatching.transferMatches(
                "Transfer : Tagesgeld", accountName: "Tagesgeld", text: "geld", prefix: false))
        #expect(
            !DropDownMatching.transferMatches(
                "Transfer : Tagesgeld", accountName: "Tagesgeld", text: "geld", prefix: true))
    }

    @Test func completionKeepsTheTypedPrefixAndSelectsTheRest() {
        let (text, range) = DropDownMatching.completion(payee, text: "wal", caret: 3)
        #expect(text == "walmart")
        #expect(range == NSRange(location: 3, length: 4))
        let (transferText, transferRange) = DropDownMatching.completion(transfer, text: "Transfer:", caret: 9)
        #expect(transferText == "Transfer : Tagesgeld")
        #expect(transferRange == NSRange(location: 11, length: 9))
    }

    @Test func headersStayWhileAChildMatches() {
        let header = DropDownItem(
            id: "h", kind: .transfersHeader, label: "Umbuchung mit Konto:", value: "", group: "transfers")
        var row = transfer
        row.group = "transfers"
        #expect(DropDownMatching.filter([header, row, payee], kind: .payee, text: "tag").map(\.id) == ["h", "t"])
        #expect(DropDownMatching.filter([header, row, payee], kind: .payee, text: "mart").map(\.id) == ["p"])
        #expect(DropDownMatching.filter([header, row, payee], kind: .payee, text: " ").count == 3)
    }

    @Test func startsWithIgnoresCaseAndDiacritics() {
        #expect(DropDownMatching.startsWith("Bäckerei", "back"))
        #expect(DropDownMatching.startsWith("Anything", ""))
        #expect(!DropDownMatching.startsWith("Rewe", "ew"))
    }
}

@MainActor
@Suite struct EditorLayoutTests {
    @Test func listContentCountsTheEditedRowsExtraHeight() {
        #expect(registerListContentHeight(rowCount: 10, viewportHeight: 200, extraHeight: 31) == CGFloat(200 + 4 * 28))
    }

    @Test func markupKeepsBoldRunsAndLineBreaks() {
        let text = TextMarkup.attributed("a <b>b</b><br/>&nbsp;c")
        #expect(String(text.characters) == "a b\n\u{00A0}c")
        #expect(text.runs.count == 3)
    }

    @Test func quittingSavesAnOpenEdit() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -4)
        let app = AppModel(store: BudgetStore(budget: fixture.budget), defaults: nil)
        app.register.beginEditing(id, column: .memo)
        app.register.editor?.type("vor dem Beenden")
        #expect(app.commitBeforeQuit())
        #expect(app.store.budget.transaction(withId: id)?.memo == "vor dem Beenden")
        app.register.beginEditing(id)
        app.register.editor?.retype("abc")
        #expect(!app.commitBeforeQuit())
    }

    @Test func iconClicksOnOtherRowsGoThroughTheEditGuard() throws {
        var fixture = RegisterFixture()
        let first = fixture.add(fixture.giro, -4)
        let second = fixture.add(fixture.giro, -5)
        let model = fixture.model()
        model.beginEditing(first, column: .memo)
        model.editor?.type("x")
        let other = try #require(model.rows.first { $0.id == second })
        model.errorIconClicked(other)
        #expect(model.popup == nil)
        #expect(model.editor?.glowCount == 1)
        model.rowClicked(other, column: nil, modifiers: .command)
        #expect(model.selectedTransactionIds == [first])
    }
}
