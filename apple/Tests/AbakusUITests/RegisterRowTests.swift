import AbakusCore
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterRowTests {
    @Test func startingBalanceShowsTheReferenceScreenshotTexts() {
        let row = RegisterFixture().model().rows[0]
        #expect(row.date == "29/04/14")
        #expect(row.payee == "Anfangssaldo")
        #expect(row.category == "Zu verteilen")
        #expect(row.categoryStyle == .plain)
        #expect(row.inflow == "1,111.00")
        #expect(row.outflow == "")
        #expect(row.cleared == .cleared)
        #expect(row.cleared.symbol(reconciling: false).name == "checkmark.circle.fill")
        #expect(row.errorLevel.symbol == nil)
    }

    @Test func voiceOverCallsATransferUmbuchung() {
        #expect(StatusSymbol.transfer.label == "Umbuchung")
    }

    @Test func uncategorisedTransactionsAskForACategory() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -12.5)
        let row = fixture.model().rows.first { $0.id == id }!
        #expect(row.category == "Kategorie fehlt")
        #expect(row.categoryStyle == .needsCategory)
        #expect(row.errorLevel.symbol?.name == StatusSymbol.warning)
        #expect(row.outflow == "12.50")
        #expect(row.textStyle == .plain)
    }

    @Test func onBudgetTransfersShowTheTransferIconAndNoCategory() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -100, target: fixture.tagesgeld)
        let row = fixture.model().rows.first { $0.id == id }!
        #expect(row.payee == "Transfer : Tagesgeld")
        #expect(row.hasTransferIcon)
        #expect(row.category == "")
        #expect(row.errorLevel == .none)
    }

    @Test func categorisedOnBudgetTransfersAreErrors() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -100, category: fixture.groceries, target: fixture.tagesgeld)
        let row = fixture.model().rows.first { $0.id == id }!
        #expect(row.categoryStyle == .error)
        #expect(row.errorLevel.symbol?.name == "xmark.octagon.fill")
        #expect(row.errorMessage == ErrorMessages.onBudgetTransferCategorized)
    }

    @Test func unapprovedImportedRowsAreBold() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -9, category: fixture.groceries, approved: false, source: .bank)
        let row = fixture.model().rows.first { $0.id == id }!
        #expect(row.textStyle == .bold)
        #expect(row.categoryStyle == .bold)
        #expect(row.category == "Everyday Expenses: Groceries")
        #expect(row.errorLevel.symbol?.label == "Zu bestätigen")
    }

    @Test func offBudgetAccountsHaveNoCategoryText() {
        var fixture = RegisterFixture()
        fixture.add(fixture.depot, -5)
        let model = fixture.model(selection: .account(fixture.depot))
        #expect(model.rows.allSatisfy { $0.category == "" })
        #expect(!model.visibleColumns.contains(.category))
    }

    @Test func splitsAreCollapsedUntilToggled() {
        var fixture = RegisterFixture()
        let split = fixture.add(
            fixture.giro, -30,
            subtransactions: [
                Subtransaction(transactionId: "", amount: -10, categoryId: fixture.groceries, memo: "Milk"),
                Subtransaction(transactionId: "", amount: -20).transferring(to: fixture.tagesgeld),
            ])
        let model = fixture.model()
        #expect(model.rows.count == 2)
        #expect(model.rows[1].split == .collapsed)
        #expect(model.rows[1].category == "Aufteilung")
        model.toggleSplit(split)
        let rows = model.rows
        #expect(rows.count == 4)
        #expect(rows[1].split == .expanded)
        #expect(rows[2].category == "Everyday Expenses: Groceries")
        #expect(rows[2].memo == "Milk")
        #expect(rows[2].transactionId == split)
        #expect(rows[3].payee == "Transfer : Tagesgeld")
        #expect(rows[3].outflow == "20.00")
        model.toggleSplit(split)
        #expect(model.rows.count == 2)
    }

    @Test func splitLinesShowTheirOwnPayee() throws {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1, payee: "Bakery")
        let bakery = try #require(fixture.budget.payee(named: "Bakery")).id
        let split = fixture.add(
            fixture.giro, -30,
            subtransactions: [
                Subtransaction(transactionId: "", amount: -10, payeeId: bakery),
                Subtransaction(transactionId: "", amount: -20),
            ])
        let model = fixture.model()
        model.toggleSplit(split)
        #expect(model.rows.suffix(2).map(\.payee) == ["Bakery", ""])
    }

    @Test func runningBalanceIsFilledOnlyWhenTheColumnIsShown() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -11)
        let model = fixture.model()
        #expect(model.rows.last?.runningBalance == "")
        model.toggleColumnVisibility(.runningBalance)
        #expect(model.rows.last?.runningBalance == "1,100.00")
        #expect(model.visibleColumns.contains(.runningBalance))
    }

    @Test func thePayeeTooltipIsThePayee() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -3, payee: "Bakery")
        let row = fixture.model().rows.first { $0.id == id }!
        #expect(row.payeeTooltip == "Bakery")
    }
}
