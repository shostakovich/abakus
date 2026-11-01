import AbakusCore
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterRowTests {
    @Test func startingBalanceShowsTheReferenceScreenshotTexts() {
        let row = RegisterFixture().model().rows[0]
        #expect(row.date == "29/04")
        #expect(row.payee == "Anfangssaldo")
        #expect(row.category == "Zu verteilen")
        #expect(row.categoryStyle == .plain)
        #expect(row.amountText == "+1,111.00")
        #expect(row.isInflow)
        #expect(row.cleared == .cleared)
        #expect(row.cleared.symbol.name == "checkmark.circle.fill")
        #expect(row.errorLevel.symbol == nil)
    }

    @Test func voiceOverCallsATransferUmbuchung() {
        #expect(StatusSymbol.transfer.label == "Umbuchung")
    }

    @Test func theStatusColumnShowsVorgemerktGebuchtAndAbgeglichen() {
        #expect(
            ClearedStatus.uncleared.symbol
                == StatusSymbol(name: "circle", color: ThemeColor.secondaryText, label: "Vorgemerkt"))
        #expect(ClearedStatus.cleared.symbol.color == ThemeColor.positive)
        #expect(
            ClearedStatus.reconciled.symbol
                == StatusSymbol(name: "lock.fill", color: ThemeColor.positive, label: "Abgeglichen"))
    }

    @Test func theCategoryShowsWithoutItsGroupWhichMovesToTheTooltip() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -12.5, category: fixture.groceries)
        let row = fixture.model().rows.first { $0.id == id }!
        #expect(row.category == "Groceries")
        #expect(row.categoryTooltip == "Everyday Expenses: Groceries")
    }

    @Test func datesKeepTheirYearWhenNoMonthHeadingNamesIt() {
        let model = RegisterFixture().model()
        model.grid.headerClicked(.payee)
        #expect(model.rows[0].date == "29/04/14")
    }

    @Test func uncategorisedTransactionsAskForACategory() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -12.5)
        let row = fixture.model().rows.first { $0.id == id }!
        #expect(row.category == "Kategorie fehlt")
        #expect(row.categoryTooltip == nil)
        #expect(row.categoryStyle == .needsCategory)
        #expect(row.errorLevel.symbol?.name == StatusSymbol.warning)
        #expect(row.amountText == "−12.50")
        #expect(!row.isInflow)
        #expect(row.textStyle == .plain)
    }

    @Test func outflowsAndInflowsShareTheBetragColumnWithTheirSign() {
        var fixture = RegisterFixture()
        let outflow = fixture.add(fixture.giro, -88.12)
        let inflow = fixture.add(fixture.giro, 3180)
        let rows = fixture.model().rows
        let columns = fixture.model().visibleColumns
        #expect(columns.contains(.amount))
        #expect(RegisterColumn.amount.header == .text("Betrag"))
        #expect(rows.first { $0.id == outflow }?.amountText == "−88.12")
        #expect(rows.first { $0.id == outflow }?.isInflow == false)
        #expect(rows.first { $0.id == inflow }?.amountText == "+3,180.00")
        #expect(rows.first { $0.id == inflow }?.isInflow == true)
    }

    @Test func onBudgetTransfersShowTheOtherAccountAfterTheTransferIconAndNoCategory() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -100, target: fixture.tagesgeld)
        let row = fixture.model().rows.first { $0.id == id }!
        #expect(row.payee == "Tagesgeld")
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
        #expect(row.category == "Groceries")
        #expect(row.errorLevel.symbol?.label == "Bestätigen")
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
            fixture.giro, -10,
            subtransactions: [
                Subtransaction(transactionId: "", amount: 10, categoryId: fixture.groceries, memo: "Milk"),
                Subtransaction(transactionId: "", amount: -20).transferring(to: fixture.tagesgeld),
            ])
        let model = fixture.model()
        #expect(model.rows.count == 2)
        #expect(model.rows[0].split == .collapsed)
        #expect(model.rows[0].category == "Aufgeteilt (2)")
        model.toggleSplit(split)
        let rows = model.rows
        #expect(rows.count == 4)
        #expect(rows[0].split == .expanded)
        #expect(rows[1].category == "Groceries")
        #expect(rows[1].memo == "Milk")
        #expect(rows[1].amountText == "+10.00")
        #expect(rows[1].isInflow)
        #expect(rows[1].transactionId == split)
        #expect(rows[2].payee == "Tagesgeld")
        #expect(rows[2].hasTransferIcon)
        #expect(rows[2].amountText == "−20.00")
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
        let index = try #require(model.rows.firstIndex { $0.id == split })
        #expect(model.rows[index + 1...index + 2].map(\.payee) == ["Bakery", ""])
    }

    @Test func runningBalanceIsFilledOnlyWhenTheColumnIsShown() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -11)
        let model = fixture.model()
        #expect(model.rows.first?.runningBalance == "")
        model.toggleColumnVisibility(.runningBalance)
        #expect(model.rows.first?.runningBalance == "1,100.00")
        #expect(model.visibleColumns.contains(.runningBalance))
    }

    @Test func thePayeeTooltipIsThePayee() {
        var fixture = RegisterFixture()
        let id = fixture.add(fixture.giro, -3, payee: "Bakery")
        let row = fixture.model().rows.first { $0.id == id }!
        #expect(row.payeeTooltip == "Bakery")
    }
}
