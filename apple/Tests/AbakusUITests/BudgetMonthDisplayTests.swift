import AbakusCore
import Foundation
import Testing

@testable import AbakusUI

@MainActor
@Suite struct BudgetMonthDisplayTests {
    typealias F = BudgetScreenFixture

    private func month(_ model: BudgetViewModel, _ date: String) throws -> BudgetMonth {
        try #require(model.month(day(date)))
    }

    @Test func subRowsLeaveZerosBlankButVerfuegbar() throws {
        var fixture = F()
        fixture.budget(300, F.lebensmittel, in: "2026-10-01")
        fixture.spend(120, F.lebensmittel, on: "2026-10-05")
        fixture.budget(30, F.notgroschen, in: "2026-10-01")
        fixture.spend(30, F.notgroschen, on: "2026-10-06")
        let model = fixture.model().model
        let october = try month(model, "2026-10-01")
        let food = model.subRowDisplay(F.lebensmittel, in: october)
        #expect([food.assigned, food.outflows, food.balance] == ["300,00", "-120,00", "180,00"])
        #expect(!food.isBalanceNegative && food.hasTransactions)
        let november = model.subRowDisplay(F.lebensmittel, in: try month(model, "2026-11-01"))
        #expect([november.assigned, november.outflows, november.balance] == ["", "", "180,00"])
        #expect(!november.hasTransactions)
        let spentOut = model.subRowDisplay(F.notgroschen, in: october)
        #expect(spentOut.balance == "0,00")
        #expect(spentOut.isBalanceZero && !food.isBalanceZero)
        #expect(spentOut.accessibilityValue == "0,00")
        let empty = model.subRowDisplay(F.kino, in: october)
        #expect([empty.assigned, empty.outflows, empty.balance] == ["", "", "0,00"])
        #expect(empty.isBalanceZero)
    }

    @Test func anOverspentSubIsMarkedAndStartsTheNextMonthAtZero() throws {
        var fixture = F()
        fixture.budget(50, F.kleidung, in: "2026-10-01")
        fixture.spend(80, F.kleidung, on: "2026-10-12")
        let model = fixture.model().model
        let overspent = model.subRowDisplay(F.kleidung, in: try month(model, "2026-10-01"))
        #expect(overspent.balance == "-30,00")
        #expect(overspent.isBalanceNegative)
        #expect(model.subRowDisplay(F.kleidung, in: try month(model, "2026-11-01")).balance == "0,00")
    }

    @Test func masterRowsShowTheirSumsAndLeaveZerosBlank() throws {
        var fixture = F()
        fixture.budget(50, F.kleidung, in: "2026-10-01")
        fixture.spend(80, F.kleidung, on: "2026-10-12")
        fixture.spend(7, nil, on: "2026-10-13")
        let model = fixture.model().model
        let october = try month(model, "2026-10-01")
        let groups = model.groups
        let alltag = try #require(groups.first { $0.id == F.alltag }).header
        let master = model.masterRowDisplay(alltag, in: october)
        #expect([master.assigned, master.outflows, master.balance] == ["50,00", "-80,00", "-30,00"])
        #expect(master.isBalanceNegative && master.hasTransactions)
        let sparen = try #require(groups.first { $0.id == F.sparen }).header
        let quiet = model.masterRowDisplay(sparen, in: october)
        #expect([quiet.assigned, quiet.outflows, quiet.balance] == ["", "", ""])
        #expect(!quiet.isBalanceNegative && !quiet.hasTransactions)
        let uncategorized = try #require(groups.first).header
        #expect(uncategorized.kind == .uncategorized)
        #expect(model.masterRowDisplay(uncategorized, in: october).outflows == "-7,00")
        #expect(model.masterRowDisplay(uncategorized, in: october).assigned == "")
    }

    @Test func zuVerteilenIsGreenAboveZeroRedBelowAndMutedInAPastMonthUnlessRed() throws {
        var fixture = F()
        fixture.spend(-1000, BudgetScreenFixture.readyToAssign, on: "2026-09-01")
        let model = fixture.model().model
        let header = { (date: String) in model.headerDisplay(try month(model, date)) }
        #expect(try header("2026-10-01").availableTint == .positive)
        #expect(try header("2026-09-01").availableTint == .muted)
        #expect(try header("2026-09-01").isPast && !header("2026-10-01").isPast && !header("2026-11-01").isPast)
        try model.store.perform(.setAssigned(month: day("2026-10-01"), categoryId: F.kino, amount: 1000))
        #expect(try header("2026-10-01").availableTint == .neutral)
        try model.store.perform(.setAssigned(month: day("2026-09-01"), categoryId: F.kino, amount: 1500))
        #expect(try header("2026-09-01").availableTint == .negative)
        #expect(try header("2026-10-01").availableTint == .negative)
    }

    @Test func totalsHangTheirTrailingCurrencySymbol() throws {
        var fixture = F()
        fixture.budget(1500, F.kino, in: "2026-11-01")
        let model = fixture.model().model
        let header = model.headerDisplay(try month(model, "2026-11-01"))
        #expect(header.available == "-1.500,00€")
        #expect(header.totals.map(\.text) == ["1.500,00€", "0,00€", "1.500,00€"])
        #expect(header.totals[0] == BudgetTotal(digits: "1.500,00", suffix: "€"))
    }
}
