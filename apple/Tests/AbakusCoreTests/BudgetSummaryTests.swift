import Foundation
import Testing

@testable import AbakusCore

@Suite struct BudgetSummaryTests {
    typealias S = ScenarioBudget

    private func summary(_ budget: Budget, _ source: OutflowSummarySource, month: String = "2026-10-01")
        -> TransactionSummary
    {
        budget.outflowSummary(source, month: date(month), today: october24, formatter: german)
    }

    private func scenario() throws -> ScenarioBudget {
        var scenario = ScenarioBudget()
        try scenario.budget.apply(
            .addAccount(
                NewAccount(
                    id: "BAR", name: "Bargeld", kind: .cash, startingBalance: 0,
                    startDate: date("2026-10-01"))))
        try scenario.add(-12, on: "2026-10-03", category: S.lebensmittel, payee: "Bäcker", account: "BAR", memo: "Brot")
        try scenario.add(-40, on: "2026-10-09", category: S.lebensmittel, payee: "REWE", id: "REWE")
        try scenario.split(
            [(-70, S.lebensmittel), (-30, S.kleidung), (-5, ScenarioBudget.readyToAssign)], on: "2026-10-15",
            payee: "Kaufhaus", id: "SPLIT", memo: "Einkauf")
        try scenario.add(-7, on: "2026-10-20", category: nil, payee: "Kiosk")
        return scenario
    }

    @Test func aSubCategoryListsItsTransactionsAndSplitLinesNewestFirst() throws {
        let budget = try scenario().budget
        let result = summary(budget, .category(S.lebensmittel))
        #expect(result.title == "Alltag: Lebensmittel")
        #expect(result.message == "122,00€ ausgegeben in 3 Buchungen:")
        #expect(result.rows.map(\.payee) == ["[Aufgeteilt] Kaufhaus ", "REWE", "Bäcker"])
        #expect(result.rows.map(\.amount) == [-70, -40, -12])
        #expect(result.rows.map(\.transactionId) == ["SPLIT", "REWE", result.rows[2].transactionId])
        #expect(result.rows[0].memo == "Einkauf")
        #expect(result.rows[2].accountName == "Bargeld")
        #expect(
            result.accountView
                == AccountViewFilter(
                    accountId: EntityID.allAccounts, searchText: "Kategorie: Alltag: Lebensmittel, ",
                    dateFilter: DateFilterSelection(
                        preset: .thisMonth, start: date("2026-10-01"), end: date("2026-10-01"), label: "Dieser Monat")))
        #expect(result.emptyOutflowHelp == nil)
    }

    @Test func aMasterCountsDistinctTransactions() throws {
        let budget = try scenario().budget
        let result = summary(budget, .masterCategory(S.alltag))
        #expect(result.title == "Alltag")
        #expect(result.message == "152,00€ ausgegeben in 3 Buchungen:")
        #expect(result.rows.map(\.amount) == [-70, -30, -40, -12])
        #expect(result.accountView?.searchText == "Kategorie: Alltag, ")
    }

    @Test func allOutflowsShowsThePositiveTotalAndEveryLineButImmediateIncome() throws {
        let budget = try scenario().budget
        let result = summary(budget, .allOutflows)
        #expect(result.title == "Alle Kategorien")
        #expect(result.message == "159,00€ ausgegeben in 4 Buchungen:")
        #expect(result.rows.map(\.amount) == [-7, -70, -30, -40, -12])
        #expect(result.accountView?.searchText == "")
        #expect(result.emptyOutflowHelp == nil)
    }

    @Test func uncategorizedTransactionsHaveTheirOwnMessageAndSearch() throws {
        let budget = try scenario().budget
        let result = summary(budget, .masterCategory(EntityID.uncategorizedMasterCategory))
        #expect(result.title == "Nicht kategorisiert")
        #expect(result.message == "7,00€ ausgegeben in 1 Buchung ohne Kategorie:")
        #expect(result.accountView?.accountId == S.giro)
        #expect(result.accountView?.searchText == "Kategorie: , ")
    }

    @Test func splitLinesNameTheirTransferAndJoinTheMemos() throws {
        var scenario = ScenarioBudget()
        try scenario.budget.apply(
            .addAccount(
                NewAccount(
                    id: "DEPOT", name: "Depot", kind: .tracking, startingBalance: 0,
                    startDate: date("2026-10-01"))))
        let lines = [
            Subtransaction(
                transactionId: "P", amount: -100, categoryId: S.notgroschen, memo: "ETF"
            ).transferring(to: "DEPOT"),
            Subtransaction(transactionId: "P", amount: -20, categoryId: S.notgroschen),
        ]
        try scenario.budget.apply(
            .addTransaction(
                Transaction(
                    id: "P", accountId: S.giro, date: date("2026-09-10"), memo: "Sparen", amount: -120,
                    subtransactions: lines),
                payeeName: ""))
        let result = summary(scenario.budget, .category(S.notgroschen), month: "2026-09-01")
        #expect(result.rows.map(\.payee) == ["[Aufgeteilt] / Transfer : Depot", "[Aufgeteilt] "])
        #expect(result.rows.map(\.memo) == ["ETF - Sparen", "Sparen"])
        #expect(result.transactionCount == 1)
        #expect(result.accountView?.dateFilter?.label == "September 2026")
        #expect(result.accountView?.dateFilter?.preset == nil)
    }

    @Test func aSplitLineWithItsOwnPayeeShowsThatPayee() throws {
        var scenario = ScenarioBudget()
        let lines = [
            Subtransaction(id: "L1", transactionId: "P", amount: -30, categoryId: S.lebensmittel),
            Subtransaction(id: "L2", transactionId: "P", amount: -20, categoryId: S.kleidung),
        ]
        let split = Transaction(
            id: "P", accountId: S.giro, date: date("2026-10-15"), categoryId: EntityID.splitCategory, amount: -50,
            subtransactions: lines)
        try scenario.budget.apply(
            .saveTransaction(
                TransactionSave(transaction: split, payeeName: "Kaufland", subPayeeNames: ["L1": "dm"], isNew: true)))
        #expect(summary(scenario.budget, .category(S.lebensmittel)).rows.map(\.payee) == ["[Aufgeteilt] dm "])
        #expect(summary(scenario.budget, .category(S.kleidung)).rows.map(\.payee) == ["[Aufgeteilt] Kaufland "])
    }

    @Test func thisMonthAlsoComparesTheYear() throws {
        var scenario = ScenarioBudget()
        try scenario.add(-10, on: "2025-10-10", category: S.kleidung)
        try scenario.add(-10, on: "2025-12-10", category: S.lebensmittel)
        try scenario.split([(-1, S.lebensmittel), (-1, S.kleidung)], on: "2025-10-11", payee: "Markt")
        let lastOctober = summary(scenario.budget, .category(S.kleidung), month: "2025-10-01")
        #expect(lastOctober.accountView?.dateFilter?.label == "Oktober 2025")
        #expect(lastOctober.accountView?.accountId == S.giro)
    }

    @Test func emptyCategoriesOfferTheOutflowHelp() throws {
        let budget = try scenario().budget
        let result = summary(budget, .category(S.notgroschen))
        #expect(result.rows.isEmpty && result.accountView == nil)
        #expect(result.message == "0,00€ ausgegeben in 0 Buchungen:")
        #expect(
            result.emptyOutflowHelp
                == "Im Oktober 2026 gibt es noch keine Ausgaben in <b>„Sparen: Notgroschen“</b>.<br/><br/>Um eine "
                + "Ausgabe einzutragen, wähle ein Konto und lege eine neue Buchung an. Gib ihr die Kategorie "
                + "<b>„Sparen: Notgroschen“</b> und ein Datum im Oktober 2026, dann erscheint sie hier.")
        #expect(summary(budget, .masterCategory(S.sparen)).emptyOutflowHelp?.contains("<b>„Sparen“</b>") == true)
        #expect(summary(budget, .allOutflows, month: "2026-11-01").emptyOutflowHelp == nil)
    }

    @Test func incomeListsWhatWasBookedToZuVerteilenInTheMonth() throws {
        var scenario = try scenario()
        try scenario.add(2000, on: "2026-09-28", category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        let result = scenario.budget.incomeSummary(month: date("2026-10-01"), today: october24, formatter: german)
        #expect(result.title == "Einnahmen im Oktober")
        #expect(result.message == "<b>995,00€</b> Einnahmen im Oktober.")
        #expect(result.rows.map(\.amount) == [-5, 0, 1000, 0])
        #expect(result.accountView?.searchText == "Einnahmen: Oktober 2026, ")
        #expect(result.accountView?.dateFilter == nil)
        let september = scenario.budget.incomeSummary(month: date("2026-09-01"), today: october24, formatter: german)
        #expect(september.rows.map(\.amount) == [2000])
        let empty = scenario.budget.incomeSummary(month: date("2027-01-01"), today: october24, formatter: german)
        #expect(empty.message == "Keine Einnahmen im Januar.")
        #expect(empty.accountView == nil)
    }
}
