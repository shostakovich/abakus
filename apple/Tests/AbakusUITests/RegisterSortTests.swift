import AbakusCore
import Testing

@testable import AbakusUI

@MainActor
@Suite struct RegisterSortTests {
    @Test func defaultSortIsDateAscendingWithLargerAmountsFirstOnTheSameDay() {
        var fixture = RegisterFixture()
        let late = fixture.add(fixture.giro, -5, on: "2014-05-12")
        let small = fixture.add(fixture.giro, -20, on: "2014-05-10")
        let large = fixture.add(fixture.giro, 30, on: "2014-05-10")
        let model = fixture.model()
        #expect(model.sortOrder == .default)
        #expect(model.transactionIds == [fixture.startingBalanceId(of: fixture.giro), large, small, late])
    }

    @Test func clickingTheSortedHeaderReversesTheOrder() {
        var fixture = RegisterFixture()
        let newest = fixture.add(fixture.giro, -5, on: "2014-05-12")
        let model = fixture.model()
        model.grid.headerClicked(.date)
        #expect(model.sortOrder == RegisterSortOrder(column: .date, ascending: false))
        #expect(model.transactionIds.first == newest)
    }

    @Test func clickingAnotherHeaderSortsItAscending() {
        var fixture = RegisterFixture()
        let zebra = fixture.add(fixture.giro, -5, on: "2014-05-01", payee: "Zebra")
        let apple = fixture.add(fixture.giro, -5, on: "2014-05-20", payee: "apple")
        let model = fixture.model()
        model.grid.headerClicked(.date)
        model.grid.headerClicked(.payee)
        #expect(model.sortOrder == RegisterSortOrder(column: .payee, ascending: true))
        #expect(Array(model.transactionIds.prefix(2)) == [fixture.startingBalanceId(of: fixture.giro), apple])
        #expect(model.transactionIds.last == zebra)
    }

    @Test func amountColumnsPutLargerAmountsFirstWhenAscending() {
        var fixture = RegisterFixture()
        let outflow = fixture.add(fixture.giro, -50)
        let inflow = fixture.add(fixture.giro, 20)
        let model = fixture.model()
        model.grid.headerClicked(.outflow)
        #expect(model.transactionIds == [fixture.startingBalanceId(of: fixture.giro), inflow, outflow])
    }

    @Test func clearedSortsStrongestFirst() {
        var fixture = RegisterFixture()
        fixture.add(fixture.giro, -1)
        let model = fixture.model()
        model.grid.headerClicked(.cleared)
        #expect(model.transactionIds.first == fixture.startingBalanceId(of: fixture.giro))
    }

    @Test func theBalanceHeaderNeverSorts() {
        let model = RegisterFixture().model()
        model.grid.headerClicked(.runningBalance)
        #expect(model.sortOrder == .default)
        #expect(RegisterSortOrder.default.clicked(.runningBalance) == .default)
    }

    @Test func splitChildrenStayUnderTheirParent() {
        var fixture = RegisterFixture()
        let split = fixture.add(
            fixture.giro, -30, on: "2014-05-01",
            subtransactions: [
                Subtransaction(transactionId: "", amount: -10, categoryId: fixture.groceries),
                Subtransaction(transactionId: "", amount: -20, categoryId: fixture.groceries),
            ])
        fixture.add(fixture.giro, -5, on: "2014-05-02")
        let model = fixture.model()
        model.toggleSplit(split)
        model.grid.headerClicked(.date)
        let rows = model.rows
        let parent = rows.firstIndex { $0.id == split }!
        #expect(rows[parent + 1].kind == .subtransaction(parentIndex: parent))
        #expect(rows[parent + 2].kind == .subtransaction(parentIndex: parent))
        #expect(model.transactionIds.count == 3)
    }
}
