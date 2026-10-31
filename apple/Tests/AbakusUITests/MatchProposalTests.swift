import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct MatchProposalTests {
    @Test func aProposalFromBankSyncStaysOutOfTheRegisterAndItsBalance() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -42.10, payee: "Rewe", id: "REWE")
        let database = try BudgetDatabase()
        try database.save(fixture.budget, over: nil, now: Date())
        let store = try BudgetStore.open(database, today: { editDay })
        let clock = "2026-11-04T10:00:00.000Z-0000-server"
        func field(_ table: String, _ id: String, _ column: String, _ value: SyncValue) -> SyncMessage {
            SyncMessage(table: table, rowId: id, column: column, value: value, clock: clock)
        }
        try store.receive([
            field("payees", "BANK-PAYEE", "name", .text("REWE SAGT DANKE")),
            field("transactions", "BANK", "account_id", .text(fixture.giro)),
            field("transactions", "BANK", "date", .text("2014-05-10")),
            field("transactions", "BANK", "amount", .integer(-4210)),
            field("transactions", "BANK", "payee_id", .text("BANK-PAYEE")),
            field("transactions", "BANK", "source", .text("bank")),
            field("transactions", "BANK", "cleared", .text("cleared")),
            field("transactions", "BANK", "matched_transaction_id", .text("REWE")),
        ])

        let model = RegisterViewModel(store: store, navigation: NavigationState(selection: .account(fixture.giro)))
        #expect(model.rows.map(\.payee).sorted() == ["Anfangssaldo", "Rewe"])
        #expect(model.summary.working.amountText == "$1,068.90")
    }
}
