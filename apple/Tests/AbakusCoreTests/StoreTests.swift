import Foundation
import Testing

@testable import AbakusCore

@MainActor
@Suite struct BudgetStoreTests {
    private func unclearCommand(_ store: BudgetStore) -> BudgetCommand {
        .setCleared([store.budget.transactions[0].id], .uncleared)
    }

    private func opened(_ budget: Budget = TestBudget().budget, today: DateWithoutTime = october23) throws
        -> (BudgetStore, BudgetDatabase)
    {
        let database = try BudgetDatabase()
        try database.save(budget, over: nil, now: Date())
        return (try BudgetStore.open(database, today: { today }), database)
    }

    @Test func performAppliesTheCommand() throws {
        let store = BudgetStore(budget: TestBudget().budget)
        try store.perform(unclearCommand(store))
        #expect(store.budget.transactions[0].cleared == .uncleared)
    }

    @Test func failingCommandsChangeNothing() {
        let store = BudgetStore(budget: TestBudget().budget)
        let before = store.budget
        let missing = Account(id: "MISSING", name: "Weg", kind: .cash)
        #expect(throws: BudgetError.self) { try store.perform(.editAccount(missing)) }
        #expect(store.budget == before)
    }

    @Test func commandsWithoutEffectAreNotWritten() throws {
        let (store, database) = try opened()
        let outbox = try database.outbox()
        try store.perform(.setCleared(["missing"], .reconciled))
        #expect(try database.outbox() == outbox)
    }

    @Test func everyCommandIsWrittenToTheDatabase() throws {
        let (store, database) = try opened()
        try store.perform(unclearCommand(store))
        #expect(try database.budget().syncedRows == store.budget.syncedRows)
        #expect(!store.hasUnsavedChanges)
    }

    @Test func theMacsOwnSettingsAreKept() throws {
        let (store, database) = try opened()
        let group = store.budget.budgetCategoryGroups[0].id
        try store.perform(.setCategoryGroupExpanded(groupId: group, false))
        let loaded = try database.budget()
        #expect(loaded.collapsedCategoryGroupIds == [group])
        #expect(loaded.budgetName == "Test")
    }

    @Test func anUnsignedEmptyDatabaseStaysEmpty() throws {
        let database = try BudgetDatabase()
        let store = try BudgetStore.open(database, today: { october23 })
        #expect(store.budget.accounts.isEmpty)
        #expect(try database.isEmpty)
        #expect(try database.outbox().isEmpty)
    }

    @Test func anEmptyBudgetOfAServerStaysEmpty() throws {
        let database = try BudgetDatabase()
        try database.adopt(
            SyncSnapshot(cursor: 3, tables: [:]), deviceId: "mac-1", serverURL: URL(string: "https://abakus.test")!,
            settings: LocalBudgetSettings(budgetName: "abakus.test"))

        let store = try BudgetStore.open(database, today: { october23 })

        #expect(store.budget.accounts.isEmpty)
        #expect(try database.outbox().isEmpty)
        #expect(try database.isEmpty)
    }

    @Test func anOpenedBudgetEntersDueSchedulesOnceItHasPulled() throws {
        var fixture = TestBudget()
        let transaction = Transaction(id: "S1", accountId: fixture.girokonto, date: date("2026-11-02"), amount: -9)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, repeats: .monthly, payeeName: "Netflix", isNew: true)))
        let (store, database) = try opened(fixture.budget, today: date("2026-12-05"))
        #expect(!store.budget.transactions.contains { $0.scheduledTransactionId == "S1" })

        store.pulled()

        #expect(store.budget.transactions.filter { $0.scheduledTransactionId == "S1" }.count == 2)
        #expect(try database.budget().scheduledTransactions.first?.nextDate == date("2027-01-02"))
    }

    private func storeWithADeletedOccurrence() throws -> (BudgetStore, BudgetDatabase, occurrence: String) {
        var fixture = TestBudget()
        let transaction = Transaction(id: "S1", accountId: fixture.girokonto, date: date("2026-11-02"), amount: -9)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, repeats: .monthly, payeeName: "Netflix", isNew: true)))
        let database = try BudgetDatabase()
        try database.save(fixture.budget, over: nil, now: Date())
        let occurrence = EntityID.enteredTransaction(scheduledId: "S1", date: date("2026-11-02"))
        let clock = "2026-11-02T10:00:00.000Z-0000-web"
        try database.receive([
            SyncMessage(
                table: "transactions", rowId: occurrence, column: "account_id", value: .text(fixture.girokonto),
                clock: clock),
            SyncMessage(
                table: "transactions", rowId: occurrence, column: "deleted_at",
                value: .text("2026-11-02T10:00:00.000000Z"), clock: clock),
        ])
        return (try BudgetStore.open(database, today: { date("2026-11-05") }), database, occurrence)
    }

    @Test func aDeletedOccurrenceIsNotEnteredAgain() throws {
        let (store, database, occurrence) = try storeWithADeletedOccurrence()

        store.pulled()

        #expect(store.budget.transaction(withId: occurrence) == nil)
        #expect(try database.rows()["transactions"]?[occurrence]?["deleted_at"] != .null)
        #expect(store.budget.scheduledTransactions.first?.nextDate == date("2026-12-02"))
    }

    @Test func enteringNowDoesNotEnterADeletedOccurrenceAgain() throws {
        let (store, database, occurrence) = try storeWithADeletedOccurrence()

        try store.perform(.enterScheduledTransactions(ScheduledEntry(scheduledIds: ["S1"], approved: true)))

        #expect(store.budget.transaction(withId: occurrence) == nil)
        #expect(try database.rows()["transactions"]?[occurrence]?["deleted_at"] != .null)
        #expect(store.budget.scheduledTransactions.first?.nextDate == date("2026-12-02"))
    }

    @Test func aFailedWriteLeavesRowsMessagesAndClocksAsTheyWere() throws {
        var fixture = TestBudget()
        _ = try fixture.transfer(from: fixture.girokonto, to: fixture.tagesgeld, -50, id: "TR")
        let (store, database) = try opened(fixture.budget)
        let (rows, outbox, clocks) = (try database.rows(), try database.outbox(), try database.fieldClocks())
        try database.execute(
            """
            CREATE TRIGGER refuse BEFORE INSERT ON sync_messages
            WHEN (SELECT count(*) FROM sync_messages) > \(outbox.count) + 1
            BEGIN SELECT RAISE(ABORT, 'Die Platte ist voll'); END
            """)
        let edited = Transaction(
            id: "TR", accountId: fixture.girokonto, date: date("2026-10-13"), memo: "Sparen", amount: -60
        ).transferring(to: fixture.tagesgeld)
        try store.perform(.updateTransaction(edited))
        #expect(store.hasUnsavedChanges)
        #expect(store.lastSaveError?.contains("Die Platte ist voll") == true)
        #expect(try database.rows() == rows)
        #expect(try database.outbox() == outbox)
        #expect(try database.fieldClocks() == clocks)

        try database.execute("DROP TRIGGER refuse")
        store.retrySave()
        #expect(!store.hasUnsavedChanges)
        #expect(try database.budget().transaction(withId: "TR")?.memo == "Sparen")
    }

    @Test func theFirstSaveOfADayKeepsTheDatabaseAsItWasAsBackup() throws {
        try withTemporaryDatabase { url in
            let original = TestBudget().budget
            let database = try BudgetDatabase(url: url)
            try database.save(original, over: nil, now: Date())
            let store = try BudgetStore.open(database, today: { october23 })
            let backup = try #require(database.backupURL)
            let id = original.transactions[0].id
            try store.perform(.setCleared([id], .uncleared))
            #expect(try rows(at: backup) == original.syncedRows)
            try FileManager.default.setAttributes([.modificationDate: try noon(23)], ofItemAtPath: backup.path)
            try store.perform(.setCleared([id], .reconciled))
            #expect(try rows(at: backup) == original.syncedRows)
            let reconciled = store.budget.syncedRows
            try FileManager.default.setAttributes([.modificationDate: try noon(22)], ofItemAtPath: backup.path)
            try store.perform(.setCleared([id], .cleared))
            #expect(try rows(at: backup) == reconciled)
        }
    }

    private func rows(at url: URL) throws -> SyncRows {
        try BudgetDatabase(url: url).budget().syncedRows
    }

    private func noon(_ day: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)))
    }

    @Test(arguments: [1, 2]) func aStoreOfAnEarlierVersionLosesTheColumnsAbakusDropped(version: Int) throws {
        let dropped = [
            ("accounts", "note"), ("category_groups", "hidden"), ("category_groups", "note"), ("categories", "hidden"),
            ("categories", "note"),
        ]
        let fields = dropped + [("accounts", "name")]
        try withTemporaryDatabase { url in
            let budget = TestBudget().budget
            let pending = try {
                let database = try BudgetDatabase(url: url)
                try database.save(budget, over: nil, now: Date())
                return try database.pendingChanges
            }()
            let clocks = fields.enumerated().map { index, field in
                "INSERT INTO sync_field_clocks VALUES ('\(field.0)', 'row', '\(field.1)', 'c\(index)');"
                    + "INSERT INTO sync_messages (\"table\", row_id, \"column\", value, clock, outbox) "
                    + "VALUES ('\(field.0)', 'row', '\(field.1)', '\"\"', 'c\(index)', 1);"
            }
            let index = version == 1 ? "DROP INDEX sync_field_clocks_clock;" : ""
            try SQLite(path: url.path).execute(
                Self.version3Schedules + dropped.map { "ALTER TABLE \($0.0) ADD COLUMN \($0.1);" }.joined()
                    + clocks.joined() + index
                    + "UPDATE accounts SET note = 'Alt'; UPDATE categories SET hidden = 1; "
                    + "PRAGMA user_version = \(version);")

            let database = try BudgetDatabase(url: url)

            #expect(try database.budget().syncedRows == budget.syncedRows)
            #expect(try database.pendingChanges == pending + 1)
            let sqlite = try SQLite(path: url.path)
            for (table, column) in dropped {
                let columns = try sqlite.query("SELECT name FROM pragma_table_info('\(table)')").compactMap {
                    $0["name"]?.text
                }
                #expect(!columns.isEmpty && !columns.contains(column))
            }
            for table in ["sync_field_clocks", "sync_messages"] {
                let kept = try sqlite.query("SELECT \"table\", \"column\" FROM \(table) WHERE row_id = 'row'").map {
                    "\($0["table"]?.text ?? "").\($0["column"]?.text ?? "")"
                }
                #expect(kept == ["accounts.name"])
            }
            let indexes = try sqlite.query("SELECT name FROM pragma_index_list('sync_field_clocks')").compactMap {
                $0["name"]?.text
            }
            #expect(indexes.contains("sync_field_clocks_clock"))
            #expect(try sqlite.query("PRAGMA user_version").first?["user_version"] == .integer(4))
        }
    }

    private static let version3Schedules = """
        ALTER TABLE scheduled_transactions DROP COLUMN repeat_unit;
        ALTER TABLE scheduled_transactions DROP COLUMN repeat_every;
        ALTER TABLE scheduled_transactions ADD COLUMN frequency;
        ALTER TABLE scheduled_transactions ADD COLUMN first_day;
        ALTER TABLE scheduled_transactions ADD COLUMN second_day;
        """

    @Test func aStoreOfVersion3RepeatsItsSchedulesByUnitAndCount() throws {
        let repeats: [(String, Repeat)] = [
            ("once", .once), ("daily", .every(1, .week)), ("weekly", .every(1, .week)),
            ("every_other_week", .every(2, .week)), ("every_4_weeks", .every(4, .week)),
            ("twice_a_month", .monthly), ("monthly", .monthly), ("every_other_month", .every(2, .month)),
            ("every_3_months", .every(3, .month)), ("every_4_months", .every(4, .month)),
            ("twice_a_year", .every(6, .month)), ("yearly", .yearly), ("every_other_year", .every(24, .month)),
        ]
        let fields = [("frequency", #""once""#), ("first_day", "null"), ("second_day", "null"), ("amount", "-100")]
        let pending = [("S3", #""every_other_week""#, 1), ("S4", #""every_4_weeks""#, 0)]
        try withTemporaryDatabase { url in
            let fixture = TestBudget()
            try BudgetDatabase(url: url).save(fixture.budget, over: nil, now: Date())
            let schedules = repeats.enumerated().map { index, entry in
                "INSERT INTO scheduled_transactions (id, account_id, next_date, frequency, first_day, second_day, "
                    + "amount, cleared) VALUES ('S\(index)', '\(fixture.girokonto)', '2026-12-01', '\(entry.0)', "
                    + (entry.0 == "twice_a_month" ? "1, 15" : "NULL, NULL") + ", -100, 'uncleared');"
            }
            let clocks = fields.enumerated().map { index, field in
                "INSERT INTO sync_field_clocks VALUES ('scheduled_transactions', 'S0', '\(field.0)', 'c\(index)');"
                    + "INSERT INTO sync_messages (\"table\", row_id, \"column\", value, clock, outbox) "
                    + "VALUES ('scheduled_transactions', 'S0', '\(field.0)', '\(field.1)', 'c\(index)', 1);"
            }
            let frequencies = pending.map { id, value, outbox in
                "INSERT INTO sync_messages (\"table\", row_id, \"column\", value, clock, outbox) "
                    + "VALUES ('scheduled_transactions', '\(id)', 'frequency', '\(value)', 'c-\(id)', \(outbox));"
            }
            try SQLite(path: url.path).execute(
                Self.version3Schedules + schedules.joined() + clocks.joined() + frequencies.joined()
                    + "PRAGMA user_version = 3;")

            let database = try BudgetDatabase(url: url)

            let loaded = try database.budget().scheduledTransactions.sorted {
                Int($0.id.dropFirst())! < Int($1.id.dropFirst())!
            }
            #expect(loaded.map(\.repeats) == repeats.map(\.1))
            let sqlite = try SQLite(path: url.path)
            let columns = try sqlite.query("SELECT name FROM pragma_table_info('scheduled_transactions')").compactMap {
                $0["name"]?.text
            }
            #expect(columns.contains("repeat_unit") && columns.contains("repeat_every"))
            #expect(!columns.contains { ["frequency", "first_day", "second_day"].contains($0) })
            for table in ["sync_field_clocks", "sync_messages"] {
                let kept = try sqlite.query("SELECT \"column\" FROM \(table) WHERE row_id = 'S0'").compactMap {
                    $0["column"]?.text
                }
                #expect(kept.sorted() == ["amount", "repeat_every", "repeat_unit"])
            }
            let resent = try database.outbox().filter { $0.column.hasPrefix("repeat_") }
            #expect(
                Set(resent) == [
                    SyncMessage(
                        table: "scheduled_transactions", rowId: "S0", column: "repeat_unit", value: .null, clock: "c0"),
                    SyncMessage(
                        table: "scheduled_transactions", rowId: "S0", column: "repeat_every", value: .null, clock: "c0"),
                    SyncMessage(
                        table: "scheduled_transactions", rowId: "S3", column: "repeat_unit", value: .text("week"),
                        clock: "c-S3"),
                    SyncMessage(
                        table: "scheduled_transactions", rowId: "S3", column: "repeat_every", value: .integer(2),
                        clock: "c-S3"),
                ])
            let fieldClocks = try database.fieldClocks()
            #expect(fieldClocks["scheduled_transactions/S3/repeat_unit"] == "c-S3")
            #expect(fieldClocks["scheduled_transactions/S3/repeat_every"] == "c-S3")
            #expect(fieldClocks["scheduled_transactions/S4/repeat_unit"] == nil)
            #expect(try sqlite.query("PRAGMA user_version").first?["user_version"] == .integer(4))
        }
    }

    @Test func aSecondInstanceCannotOpenTheSameBudget() throws {
        try withTemporaryDatabase { url in
            var first: BudgetDatabase? = try BudgetDatabase(url: url)
            #expect(throws: BudgetDatabaseError.inUse(path: url.path)) { try BudgetDatabase(url: url) }
            #expect(first != nil)
            first = nil
            _ = try BudgetDatabase(url: url)
        }
    }

    @Test func aFolderIsNoDatabase() throws {
        try withTemporaryDatabase { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            #expect(throws: BudgetDatabaseError.notAFile(path: url.path)) { try BudgetDatabase(url: url) }
        }
    }

    @Test func anUnreadableFileIsSetAsideAndAnEmptyBudgetOpens() throws {
        try withTemporaryDatabase { url in
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("not a database".utf8).write(to: url)

            let store = try BudgetStore.open(BudgetDatabase(url: url), today: { october23 })

            let aside = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.contains("unreadable") }
            #expect(aside.count == 1)
            let kept = try #require(aside.first)
            #expect(String(decoding: try Data(contentsOf: kept), as: UTF8.self) == "not a database")
            #expect(store.openNotice?.contains(kept.lastPathComponent) == true)
            #expect(store.openNotice?.hasSuffix("Melde dich an, um dein Budget vom Server zu laden.") == true)
            #expect(store.budget.accounts.isEmpty)
        }
    }

    @Test func theEnvironmentOverrideNeedsAPath() {
        #expect(BudgetDatabase.location(environment: [:]) == nil)
        #expect(BudgetDatabase.location(environment: ["ABAKUS_DATABASE": "  "]) == nil)
        #expect(BudgetDatabase.location(environment: ["ABAKUS_DATABASE": "/tmp/b.sqlite"])?.path == "/tmp/b.sqlite")
    }

    @Test func defaultLocationIsInApplicationSupport() {
        #expect(BudgetDatabase.defaultLocation.path.hasSuffix("Application Support/Abakus/budget.sqlite"))
    }
}
