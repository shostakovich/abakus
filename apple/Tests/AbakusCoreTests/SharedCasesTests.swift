import Foundation
import Testing

@testable import AbakusCore

/// The cases of `sync/cases/` every writer runs: the setup's messages, then each device's in every order.
struct SharedCase: Decodable, Sendable {
    let name: String
    let setup: [SyncMessage]
    let devices: [String: [SyncMessage]]
    let rows: [String: [String: SyncRow]]
    let budget: [String: [String: [String: Int]]]
    let serverOnly: Bool?

    private enum CodingKeys: String, CodingKey {
        case name, setup, devices, rows, budget
        case serverOnly = "server_only"
    }

    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("sync/cases")

    static var files: [URL] {
        get throws {
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
        }
    }

    static var all: [SharedCase] {
        get throws { try files.map { try JSONDecoder().decode(SharedCase.self, from: Data(contentsOf: $0)) } }
    }

    var orders: [[String]] {
        let names = devices.keys.sorted()
        return names.count == 2 ? [names, names.reversed()] : [names]
    }
}

@Suite struct SharedCasesTests {
    private static let today = DateWithoutTime(year: 2026, month: 11, day: 2)

    @Test func everyCaseIsReadable() throws {
        let files = try SharedCase.files
        #expect(!files.isEmpty)
        #expect(try SharedCase.all.count == files.count)
    }

    @Test(arguments: try SharedCase.all.filter { $0.serverOnly != true })
    func everyOrderGivesTheExpectedRowsAndFigures(_ shared: SharedCase) throws {
        for order in shared.orders {
            let database = try BudgetDatabase()
            try database.receive(shared.setup)
            for device in order { try database.receive(shared.devices[device] ?? []) }
            let context = "\(shared.name), \(order.joined(separator: " before "))"
            try expectRows(shared.rows, in: database, context)
            try expectFigures(shared.budget, of: database.budget(), context)
        }
    }

    private func expectRows(_ expected: [String: [String: SyncRow]], in database: BudgetDatabase, _ context: String)
        throws
    {
        let rows = try database.rows()
        for (table, byId) in expected {
            for (id, fields) in byId {
                let row = try #require(rows[table]?[id], "\(table) \(id): \(context)")
                for (column, value) in fields {
                    #expect(row[column] == value, "\(table).\(column) of \(id): \(context)")
                }
            }
        }
    }

    private func expectFigures(
        _ expected: [String: [String: [String: Int]]], of budget: Budget, _ context: String
    ) throws {
        let sheet = budget.budgetSheet(today: Self.today)
        for (month, categories) in expected {
            let shown = try #require(sheet.month(date(month)), "\(month): \(context)")
            for (categoryId, figures) in categories {
                let row = try #require(shown.category(categoryId), "\(categoryId) in \(month): \(context)")
                for (figure, cents) in figures {
                    #expect(Self.figure(figure, of: row) == cents, "\(figure) of \(categoryId) in \(month): \(context)")
                }
            }
        }
    }

    private static func figure(_ name: String, of row: BudgetCategoryFigures) -> Int? {
        switch name {
        case "assigned": SyncFormat.cents(row.assigned)
        case "activity": SyncFormat.cents(row.outflows)
        case "available": SyncFormat.cents(row.balance)
        default: nil
        }
    }
}

extension SharedCase: CustomTestStringConvertible {
    var testDescription: String { name }
}
