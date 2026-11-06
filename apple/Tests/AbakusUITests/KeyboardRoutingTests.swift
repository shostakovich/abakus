import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct KeyboardRoutingTests {
    @Test func findWaitsWhileADialogIsOpen() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -1, category: fixture.groceries, target: fixture.tagesgeld)
        let model = fixture.model()
        model.deleteTransactions([id])
        #expect(model.dialogs.isPresenting)
        model.search.focus()
        #expect(model.search.focusRequest == 0)
    }

    @Test func escapeThatEmptiesTheBoxKeepsItsFocus() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "REWE")
        let model = fixture.model()
        model.search.boxChanged("rewe")
        model.search.submitted()
        let requests = model.gridFocusRequest
        #expect(model.search.escapePressed())
        #expect(model.search.text.isEmpty)
        #expect(model.gridFocusRequest == requests)
        #expect(!model.search.escapePressed())
    }

    @Test func typingKeepsTheSearchBoxAndReturnLeavesIt() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "Aral")
        let model = fixture.model()
        model.search.boxChanged("aral,")
        #expect(model.gridFocusRequest == 0)
        model.search.submitted()
        #expect(model.gridFocusRequest == 1)
    }

    @Test func pageAndEndKeysMoveBySlices() {
        var fixture = RegisterFixture()
        for offset in 1...9 { fixture.add(fixture.giro, Decimal(-offset), on: "2014-05-1\(offset)") }
        let model = fixture.model()
        let ids = model.transactionIds
        model.rowClicked(model.rows[0], column: .payee, modifiers: [])
        model.grid.navigationKeyPressed(.pageDown, extending: false, caretOnly: false, pageRows: 3)
        #expect(model.selectedTransactionIds == [ids[3]])
        model.grid.navigationKeyPressed(.end, extending: false, caretOnly: false, pageRows: 3)
        #expect(model.selectedTransactionIds == [ids[9]])
        model.grid.navigationKeyPressed(.pageUp, extending: true, caretOnly: false, pageRows: 3)
        #expect(model.selectedTransactionIds == Array(ids[6...9]))
        model.grid.navigationKeyPressed(.home, extending: false, caretOnly: false, pageRows: 3)
        #expect(model.selectedTransactionIds == [ids[0]])
        model.grid.navigationKeyPressed(.down, extending: false, caretOnly: true, pageRows: 3)
        #expect(model.selectedTransactionIds == [ids[0]])
        model.grid.navigationKeyPressed(.down, extending: true, caretOnly: false, pageRows: 3)
        #expect(model.selectedTransactionIds == Array(ids[0...2]))
    }
}
