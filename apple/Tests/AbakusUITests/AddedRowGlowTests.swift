import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct AddedRowGlowTests {
    @Test func rowsACommandAddsGlowAndTheOthersDoNot() throws {
        var fixture = RegisterFixture()
        let old = fixture.add(fixture.giro, -10)
        let model = fixture.model()
        _ = model.rows
        let new = Transaction(accountId: fixture.giro, date: day("2014-05-11"), amount: -5)
        try model.store.perform(.addTransaction(new, payeeName: "Shop"))
        #expect(model.addedRowGlowStart(new.id) != nil)
        #expect(model.addedRowGlowStart(old) == nil)
    }

    @Test func showingTheListAnewDoesNotGlow() throws {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -10)
        let model = fixture.model()
        model.search.text = "zzz"
        model.search.commit()
        #expect(model.rows.isEmpty)
        model.search.clearClicked()
        #expect(model.rows.contains { $0.transactionId == id })
        #expect(model.addedRowGlowStart(id) == nil)
    }

    @Test func anEditKeepsTheLastGlowWithoutStartingANewOne() throws {
        let fixture = RegisterFixture()
        let model = fixture.model()
        _ = model.rows
        let new = Transaction(accountId: fixture.giro, date: day("2014-05-11"), amount: -5)
        try model.store.perform(.addTransaction(new, payeeName: "Shop"))
        let start = model.addedRowGlowStart(new.id)
        var edited = try #require(model.store.budget.transaction(withId: new.id))
        edited.memo = "Edited"
        try model.store.perform(.updateTransaction(edited))
        #expect(model.addedRowGlowStart(new.id) == start)
    }
}
