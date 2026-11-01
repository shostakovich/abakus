import Foundation
import Testing

@testable import AbakusCore

/// Abakus's target tests (`test/abakus/budget_test.exs`, "targets"), its amounts in euros instead of cents.
@Suite struct TargetTests {
    static let one = "ONE"
    static let two = "TWO"

    struct Targets {
        var scenario = ScenarioBudget(
            income: nil,
            masters: [(id: "GOALS", name: "Ziele", subs: [(TargetTests.one, "Eins"), (TargetTests.two, "Zwei")])],
            start: "2026-08-01")
        var through = date("2026-10-01")

        init() {
            scenario.today = date("2026-10-15")
        }

        mutating func set(_ target: Target, for category: String = one, from month: String = "2026-09-01")
            throws
        {
            try scenario.budget.apply(.setTarget(month: date(month), categoryId: category, target: target))
        }

        mutating func assign(_ amounts: [(String, String, Decimal)]) throws {
            for (category, month, amount) in amounts { try scenario.budget(amount, category, in: month) }
        }

        mutating func spend(_ amount: Decimal, _ category: String, on day: String) throws {
            try scenario.add(-amount, on: day, category: category)
        }

        func figures(_ month: String, _ category: String = one) -> BudgetTargetFigures? {
            let sheet = scenario.budget.budgetSheet(today: scenario.today, including: [through])
            return sheet.month(date(month))?.category(category)?.target
        }
    }

    static func yearly(_ amount: Decimal, due: String, setAside: Bool = true) -> Target {
        .byDate(amount, due: date(due), repeatsYearly: true, setAside: setAside)
    }

    @Test func monthlySetAsideNeedsTheAmountWhateverIsCarried() throws {
        var targets = Targets()
        try targets.set(.monthly(50))
        try targets.assign([(Self.one, "2026-09-01", 80), (Self.one, "2026-10-01", 20)])
        let september = try #require(targets.figures("2026-09-01"))
        #expect([september.needed, september.underfunded] == [50, 0])
        #expect(september.progress == 1)
        let october = try #require(targets.figures("2026-10-01"))
        #expect([october.needed, october.underfunded] == [50, 30])
        #expect(abs(october.progress - 0.4) < 1e-9)
    }

    @Test func monthlyRefillNeedsWhatIsMissingFromTheCarry() throws {
        var targets = Targets()
        try targets.set(.monthly(50, setAside: false))
        try targets.assign([(Self.one, "2026-09-01", 30)])
        try targets.spend(10, Self.one, on: "2026-09-10")
        let september = try #require(targets.figures("2026-09-01"))
        #expect([september.needed, september.underfunded] == [50, 20])
        let october = try #require(targets.figures("2026-10-01"))
        #expect([october.needed, october.underfunded] == [30, 30])
        #expect(october.progress == 0)
    }

    @Test func aYearlyTargetSpreadsWhatIsMissingOverTheMonthsUpToItsDueMonthRoundedUp() throws {
        var targets = Targets()
        try targets.set(Self.yearly(100, due: "2026-12-24"))
        try targets.assign([(Self.one, "2026-09-01", 20)])
        let september = try #require(targets.figures("2026-09-01"))
        #expect([september.needed, september.underfunded] == [25, 5])
        let october = try #require(targets.figures("2026-10-01"))
        #expect([october.needed, october.underfunded] == [decimal("26.67"), decimal("26.67")])
        #expect(abs(october.progress - 0.2) < 1e-9)
    }

    @Test func aYearlyRefillTargetCountsWhatIsCarried() throws {
        var targets = Targets()
        try targets.set(Self.yearly(100, due: "2026-11-30", setAside: false))
        try targets.assign([(Self.one, "2026-09-01", 60)])
        try targets.spend(20, Self.one, on: "2026-09-10")
        let october = try #require(targets.figures("2026-10-01"))
        #expect([october.needed, october.underfunded] == [30, 30])
        #expect(abs(october.progress - 0.4) < 1e-9)
    }

    @Test func aMonthlyRefillTargetCountsASurplusAgainstMoneyTakenOut() throws {
        var targets = Targets()
        try targets.set(.monthly(50, setAside: false), for: Self.one)
        try targets.set(.monthly(50, setAside: false), for: Self.two)
        try targets.assign([
            (Self.one, "2026-09-01", 80), (Self.one, "2026-10-01", -20), (Self.two, "2026-09-01", 80),
            (Self.two, "2026-10-01", -40),
        ])
        let one = try #require(targets.figures("2026-10-01", Self.one))
        #expect([one.needed, one.underfunded] == [0, 0])
        #expect(one.progress == 1)
        let two = try #require(targets.figures("2026-10-01", Self.two))
        #expect([two.needed, two.underfunded] == [0, 10])
        #expect(two.progress == 0)
    }

    @Test func aYearlyRefillTargetCountsASurplusAgainstMoneyTakenOut() throws {
        var targets = Targets()
        try targets.set(Self.yearly(100, due: "2026-11-30", setAside: false), for: Self.one)
        try targets.set(Self.yearly(100, due: "2026-11-30", setAside: false), for: Self.two)
        try targets.assign([
            (Self.one, "2026-09-01", 150), (Self.one, "2026-10-01", -50), (Self.two, "2026-09-01", 150),
            (Self.two, "2026-10-01", -60),
        ])
        #expect(targets.figures("2026-10-01", Self.one).map { [$0.needed, $0.underfunded] } == [0, 0])
        #expect(targets.figures("2026-10-01", Self.two).map { [$0.needed, $0.underfunded] } == [0, 10])
    }

    @Test func afterItsDueMonthAYearlyTargetStartsItsNextCycle() throws {
        var targets = Targets()
        try targets.set(Self.yearly(120, due: "2026-09-15"))
        try targets.assign([(Self.one, "2026-09-01", 120)])
        #expect(targets.figures("2026-09-01").map { [$0.needed, $0.underfunded] } == [120, 0])
        #expect(targets.figures("2026-10-01")?.needed == 10)
    }

    @Test func aYearlyTargetsFirstCycleBeginsWithTheTargetEvenMoreThanAYearBeforeItIsDue() throws {
        var targets = Targets()
        try targets.set(Self.yearly(1200, due: "2027-12-15"), from: "2026-10-01")
        try targets.assign(["2026-10-01", "2026-11-01", "2026-12-01"].map { (Self.one, $0, 80) })
        for month in ["2026-10-01", "2026-11-01", "2026-12-01"] { #expect(targets.figures(month)?.needed == 80) }
        let january = try #require(targets.figures("2027-01-01"))
        #expect(january.needed == 80)
        #expect(abs(january.progress - 0.2) < 1e-9)
    }

    @Test func aYearlySetAsideTargetCountsNothingAssignedBeforeItBeganAndKeepsCountingWhenChanged() throws {
        var targets = Targets()
        try targets.set(Self.yearly(600, due: "2026-12-01"), from: "2026-09-01")
        try targets.set(Self.yearly(900, due: "2026-12-01"), from: "2026-11-01")
        try targets.assign([(Self.one, "2026-08-01", 50), (Self.one, "2026-09-01", 200), (Self.one, "2026-10-01", 200)])
        #expect(targets.figures("2026-09-01")?.needed == 150)
        #expect(targets.figures("2026-11-01")?.needed == 250)
    }

    @Test func aTargetByADateSpreadsWhatIsMissing() throws {
        var targets = Targets()
        try targets.set(.byDate(1200, due: date("2027-06-01")), from: "2026-10-01")
        #expect(
            targets.figures("2026-10-01").map { [$0.needed, $0.underfunded] } == [decimal("133.34"), decimal("133.34")])
        #expect(targets.figures("2026-11-01").map { [$0.needed, $0.underfunded] } == [150, 150])
    }

    @Test func theBarOfATargetByADateShowsTheWholeAmountAndMarksWhereItShouldStand() throws {
        var targets = Targets()
        try targets.set(.byDate(1200, due: date("2027-06-01")), from: "2026-10-01")
        try targets.assign([(Self.one, "2026-10-01", 80)])
        let october = try #require(targets.figures("2026-10-01"))
        #expect(october.saved == 80)
        #expect(october.underfunded == decimal("53.34"))
        #expect(abs(october.progress - 80.0 / 1200) < 1e-9)
        #expect(october.mark.map { ($0 * 100).rounded() } == 11)
    }

    @Test func onlyATargetByADateCountsWhatIsSaved() throws {
        var targets = Targets()
        try targets.set(.monthly(50))
        #expect(try #require(targets.figures("2026-10-01")).saved == nil)
        #expect(targets.figures("2026-10-01", Self.two) == nil)
        #expect(try #require(targets.figures("2026-10-01")).mark == nil)
    }

    @Test func aTargetByADateWithoutRepeatingEndsAfterItsMonth() throws {
        var targets = Targets()
        targets.through = date("2027-05-01")
        try targets.set(.byDate(300, due: date("2027-03-01")), from: "2026-10-01")
        try targets.assign([(Self.one, "2027-03-01", 100), (Self.one, "2027-04-01", -50)])
        #expect(targets.figures("2027-03-01").map { [$0.needed, $0.underfunded] } == [300, 200])
        for month in ["2027-04-01", "2027-05-01"] {
            let figures = try #require(targets.figures(month))
            #expect(figures.target.amount == 300)
            #expect([figures.needed, figures.underfunded] == [0, 0])
        }
    }

    @Test func aRepeatingTargetStartsAgain() throws {
        var targets = Targets()
        targets.through = date("2028-03-01")
        try targets.set(Self.yearly(300, due: "2027-03-01"), from: "2026-10-01")
        #expect(targets.figures("2027-03-01")?.needed == 300)
        #expect(targets.figures("2027-04-01").map { [$0.needed, $0.underfunded] } == [25, 25])
        #expect(targets.figures("2028-03-01")?.needed == 300)
    }

    @Test func aNewTargetByADateAfterADueMonthStartsAfresh() throws {
        var targets = Targets()
        targets.through = date("2027-01-01")
        try targets.set(.byDate(300, due: date("2026-12-01")), from: "2026-10-01")
        try targets.set(.byDate(600, due: date("2027-06-01")), from: "2027-01-01")
        try targets.assign(["2026-10-01", "2026-11-01", "2026-12-01"].map { (Self.one, $0, 100) })
        let january = try #require(targets.figures("2027-01-01"))
        #expect(january.needed == 100)
        #expect(january.saved == 0)
    }

    @Test func aRepeatingTargetChangedAfterItsDueMonthCountsOnlyTheNewCycle() throws {
        var targets = Targets()
        targets.through = date("2027-02-01")
        try targets.set(Self.yearly(30, due: "2026-12-01"), from: "2026-10-01")
        try targets.set(Self.yearly(240, due: "2027-12-01"), from: "2027-02-01")
        try targets.assign(
            ["2026-10-01", "2026-11-01", "2026-12-01"].map { (Self.one, $0, 10) } + [(Self.one, "2027-01-01", 20)])
        let february = try #require(targets.figures("2027-02-01"))
        #expect(february.needed == 20)
        #expect(february.saved == 20)
    }

    @Test func appliesTheVersionInEffectNoneBeforeTheFirstOrAfterItEnds() throws {
        var targets = Targets()
        targets.through = date("2026-12-01")
        try targets.set(.monthly(10), from: "2026-11-01")
        try targets.set(.ended, from: "2026-12-01")
        #expect(targets.figures("2026-10-01") == nil)
        #expect(targets.figures("2026-11-01")?.needed == 10)
        #expect(targets.figures("2026-12-01") == nil)
    }

    @Test func aSnoozedTargetStillSaysWhatIsMissing() throws {
        var targets = Targets()
        try targets.set(.monthly(50))
        try targets.scenario.budget.apply(
            .setTargetSnoozed(month: date("2026-10-01"), categoryId: Self.one, true))
        targets.through = date("2026-11-01")
        let october = try #require(targets.figures("2026-10-01"))
        #expect(october.isSnoozed)
        #expect([october.needed, october.underfunded, october.openNeed] == [50, 50, 0])
        #expect(october.progress == 0)
        let november = try #require(targets.figures("2026-11-01"))
        #expect(!november.isSnoozed)
        #expect(november.openNeed == 50)
    }

    @Test func theRingShowsTheFundedShareOfAMonthlyTargetRoundedDown() throws {
        var targets = Targets()
        try targets.set(.monthly(40))
        try targets.assign([(Self.one, "2026-09-01", 40), (Self.one, "2026-10-01", 25)])
        #expect(targets.figures("2026-10-01")?.fundedPercent == 62)
        #expect(targets.figures("2026-09-01")?.fundedPercent == nil)
        try targets.set(.monthly(40), for: Self.two)
        #expect(targets.figures("2026-10-01", Self.two)?.fundedPercent == 0)
    }

    @Test func theRingOfATargetByADateShowsTheFundedShareOfThisMonthsNeed() throws {
        var targets = Targets()
        try targets.set(.byDate(1200, due: date("2027-06-01")), from: "2026-10-01")
        try targets.assign([(Self.one, "2026-10-01", 80)])
        let october = try #require(targets.figures("2026-10-01"))
        #expect([october.needed, october.underfunded] == [decimal("133.34"), decimal("53.34")])
        #expect(october.fundedPercent == 59)
    }

    @Test func aSnoozedTargetHasNoRing() throws {
        var targets = Targets()
        try targets.set(.monthly(40))
        try targets.assign([(Self.one, "2026-10-01", 25)])
        try targets.scenario.budget.apply(
            .setTargetSnoozed(month: date("2026-10-01"), categoryId: Self.one, true))
        let october = try #require(targets.figures("2026-10-01"))
        #expect(october.underfunded == 15)
        #expect(october.fundedPercent == nil)
    }
}
