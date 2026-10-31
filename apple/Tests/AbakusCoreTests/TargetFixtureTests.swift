import Foundation
import Testing

@testable import AbakusCore

/// Abakus's `test/fixtures/budget/targets.json`: monthly set-aside and refill targets, yearly ones by a date and a
/// snoozed month, with the figures Abakus computes for them.
@Suite struct TargetFixtureTests {
    static let categories = ["PHONE", "GROCERIES", "INSURANCE", "HOLIDAY", "GYM"]

    private static func budget() throws -> ScenarioBudget {
        var scenario = ScenarioBudget(
            income: nil,
            masters: [(id: "FIXTURE", name: "Fixture", subs: categories.map { (id: $0, name: $0.capitalized) })],
            start: "2026-09-01")
        scenario.today = date("2026-10-15")
        let targets: [(String, Target)] = [
            ("PHONE", .monthly(30)),
            ("GROCERIES", .monthly(400, setAside: false)),
            ("INSURANCE", .byDate(600, due: date("2027-01-15"), repeatsYearly: true)),
            ("HOLIDAY", .byDate(1200, due: date("2026-12-20"), repeatsYearly: true, setAside: false)),
            ("GYM", .monthly(40)),
        ]
        for (category, target) in targets {
            try scenario.budget.apply(.setTarget(month: date("2026-09-01"), categoryId: category, target: target))
        }
        try scenario.budget.apply(.setTargetSnoozed(month: date("2026-10-01"), categoryId: "GYM", true))
        try scenario.add(3000, on: "2026-09-01", category: ScenarioBudget.readyToAssign, payee: "Arbeitgeber")
        let activity: [(String, String, Decimal)] = [
            ("2026-09-05", "PHONE", -30), ("2026-09-14", "GROCERIES", -350), ("2026-09-20", "GYM", -40),
            ("2026-10-12", "GROCERIES", -320), ("2026-10-20", "GYM", -10),
        ]
        for (day, category, amount) in activity { try scenario.add(amount, on: day, category: category) }
        let assigned: [(String, String, Decimal)] = [
            ("2026-09-01", "PHONE", 30), ("2026-09-01", "GROCERIES", 400), ("2026-09-01", "INSURANCE", 100),
            ("2026-09-01", "HOLIDAY", 300), ("2026-09-01", "GYM", 40), ("2026-10-01", "PHONE", 30),
            ("2026-10-01", "GROCERIES", 300), ("2026-10-01", "INSURANCE", 120), ("2026-11-01", "PHONE", 30),
            ("2026-11-01", "GROCERIES", 400), ("2026-11-01", "HOLIDAY", 250),
        ]
        for (month, category, amount) in assigned { try scenario.budget(amount, category, in: month) }
        return scenario
    }

    @Test func targetsFixtureMatchesAbakus() throws {
        let scenario = try Self.budget()
        // Per category: assigned, activity, available, underfunded.
        let expected: [(month: String, readyToAssign: Decimal, rows: [String: [Decimal]])] = [
            (
                "2026-09-01", 2130,
                [
                    "PHONE": [30, -30, 0, 0], "GROCERIES": [400, -350, 50, 0], "INSURANCE": [100, 0, 100, 20],
                    "HOLIDAY": [300, 0, 300, 0], "GYM": [40, -40, 0, 0],
                ]
            ),
            (
                "2026-10-01", 1680,
                [
                    "PHONE": [30, 0, 30, 0], "GROCERIES": [300, -320, 30, 50], "INSURANCE": [120, 0, 220, 5],
                    "HOLIDAY": [0, 0, 300, 300], "GYM": [0, -10, -10, 40],
                ]
            ),
            (
                "2026-11-01", 990,
                [
                    "PHONE": [30, 0, 60, 0], "GROCERIES": [400, 0, 430, 0],
                    "INSURANCE": [0, 0, 220, decimal("126.67")],
                    "HOLIDAY": [250, 0, 550, 200], "GYM": [0, 0, 0, 40],
                ]
            ),
            (
                "2026-12-01", 990,
                [
                    "PHONE": [0, 0, 60, 30], "GROCERIES": [0, 0, 430, 0], "INSURANCE": [0, 0, 220, 190],
                    "HOLIDAY": [0, 0, 550, 650], "GYM": [0, 0, 0, 40],
                ]
            ),
        ]
        for (day, readyToAssign, rows) in expected {
            let month = scenario.month(day)
            #expect(month.readyToAssign == readyToAssign, "\(day)")
            for (category, figures) in rows {
                let row = try #require(month.category(category))
                let actual = [row.assigned, -row.spent, row.balance, row.target?.underfunded ?? -1]
                #expect(actual == figures, "\(day) \(category)")
            }
        }
    }
}
