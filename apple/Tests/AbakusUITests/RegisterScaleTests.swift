import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterScaleTests {
    /// 4000 Giro transactions over 800 payees: enough that a per-row scan of the payees or the selection shows.
    private func largeModel() -> RegisterViewModel {
        var fixture = RegisterFixture()
        fixture.budget.payees += (0..<800).map { Payee(id: "P\($0)", name: "Payee \($0)") }
        fixture.budget.transactions += (0..<4000).map { index in
            Transaction(
                id: "T\(index)", accountId: fixture.giro, date: day("2014-05-10").addingDays(index % 300),
                payeeId: "P\(index % 800)", categoryId: fixture.groceries, amount: Decimal(-(index % 50) - 1))
        }
        return fixture.model()
    }

    private func seconds(_ work: () -> Void) -> Double {
        let start = ContinuousClock.now
        work()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test func derivingRowsDoesNotScanThePayeesPerRow() {
        let model = largeModel()
        model.toggleColumnVisibility(.runningBalance)
        #expect(seconds { _ = model.rows } < 0.4)
    }

    @Test func theActionMenuDoesNotScanTheBudgetPerSelectedRow() {
        let model = largeModel()
        model.selectAll()
        #expect(seconds { _ = model.transactionActionsMenu(withTitle: true) } < 0.1)
    }

    @Test func gridSortAndRunningBalanceUseOneCategoryKey() {
        var fixture = RegisterFixture()
        let income = fixture.add(fixture.giro, 100, on: "2014-12-10", category: fixture.budget.readyToAssignCategoryId)
        let refund = fixture.add(fixture.giro, 100, on: "2014-12-10", category: fixture.groceries)
        let model = fixture.model()
        let order = fixture.budget.transactionsInDefaultOrder(forAccount: fixture.giro).map(\.id)
        #expect(order.filter { [income, refund].contains($0) } == [refund, income])
        #expect(model.transactionIds.filter { [income, refund].contains($0) } == [income, refund])
    }
}
