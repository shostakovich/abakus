import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

/// "Girokonto" with its starting balance and 19 October 2026 transactions, one per day.
@MainActor
private struct Girokonto {
    static let october: [(day: Int, payee: String, amount: Decimal)] = [
        (1, "Wohnbau Lindenhof eG", -950), (2, "Tagesgeld", -200), (3, "REWE", -42.18), (6, "Bargeld", -100),
        (8, "Aral", -62.40), (9, "Amazon", -49.99), (10, "REWE", -67.35), (11, "Bäckerei", -6.80),
        (12, "Telekom", -39.95), (13, "Apotheke", -12.45), (14, "Deutsche Bahn", -89.90),
        (15, "Pizzeria Da Marco", -34.50), (16, "Kino", -24), (17, "REWE", -23.90), (18, "Spotify", -10.99),
        (20, "Kreditkarte", -300), (21, "Stadtwerke", -68), (22, "Kleinanzeigen", 45), (23, "Drogerie", -15.60),
    ]

    let model: RegisterViewModel

    init() {
        var budget = Budget(budgetName: "Scenario")
        let account = NewAccount(
            id: "GIRO", name: "Girokonto", kind: .checking,
            startingBalance: 2450, startDate: day("2026-09-30"))
        try! budget.apply(.addAccount(account))
        for entry in Self.october {
            let date = String(format: "2026-10-%02d", entry.day)
            try! budget.apply(
                .addTransaction(
                    Transaction(accountId: "GIRO", date: day(date), amount: entry.amount), payeeName: entry.payee))
        }
        model = RegisterViewModel(
            store: BudgetStore(budget: budget, today: { day("2026-10-24") }),
            navigation: NavigationState(selection: .account("GIRO")))
    }

    func row(_ date: String) -> RegisterRow {
        model.rows.first { $0.date == date }!
    }
}

@MainActor
@Suite struct RegisterMultiSelectionTests {
    @Test func selectSeveralTransactionsWithoutTheCheckboxColumn() {
        let girokonto = Girokonto()
        let model = girokonto.model
        #expect(model.rows.count == 20)
        model.rowClicked(girokonto.row("17.10."), column: .payee, modifiers: [])
        model.rowClicked(girokonto.row("20.10."), column: .payee, modifiers: .command)
        #expect(model.selection.count == 2)
        #expect(model.selectedTotal?.title == "Auswahl (2)")
        #expect(model.selectedTotal?.amountText == "-323,90€")
        #expect(model.actionButtonTitle.trimmingCharacters(in: .whitespaces) == "2 Buchungen bearbeiten")
        #expect(model.editor == nil)
    }

    @Test func selectARangeAndEverything() {
        let girokonto = Girokonto()
        let model = girokonto.model
        model.rowClicked(girokonto.row("01.10."), column: .payee, modifiers: [])
        model.rowClicked(girokonto.row("06.10."), column: .payee, modifiers: .shift)
        #expect(model.selection.count == 4)
        #expect(
            model.rows.filter { model.selection.contains($0.transactionId) }.map(\.date)
                == ["06.10.", "03.10.", "02.10.", "01.10."])
        #expect(model.selectAllKeyPressed())
        #expect(model.selection.count == 20)
    }

    @Test func theColumnsHaveNoCheckbox() {
        let model = Girokonto().model
        #expect(model.visibleColumns.first == .date)
        #expect(!RegisterColumn.allCases.map(\.rawValue).contains("select"))
    }

    @Test func aSingleSelectionShowsNoSelectedTotal() {
        let girokonto = Girokonto()
        let model = girokonto.model
        model.rowClicked(girokonto.row("17.10."), column: .payee, modifiers: [])
        #expect(model.selectedTotal == nil)
        #expect(model.summary.first.title == "Gebucht")
        #expect(model.summary.second.title == "Vorgemerkt")
    }
}
