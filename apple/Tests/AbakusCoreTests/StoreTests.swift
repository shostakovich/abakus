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

    @Test func openSeedsTheDemoBudgetIntoAnEmptyDatabase() throws {
        let database = try BudgetDatabase()
        let store = try BudgetStore.open(database, today: { october23 })
        #expect(store.budget.budgetName == "Demo-Budget")
        #expect(try database.budget().syncedRows == store.budget.syncedRows)
    }

    @Test func anEmptyBudgetOfAServerGetsNoDemoBudget() throws {
        let database = try BudgetDatabase()
        try database.adopt(
            SyncSnapshot(cursor: 3, tables: [:]), deviceId: "mac-1", serverURL: URL(string: "https://abakus.test")!,
            settings: LocalBudgetSettings(budgetName: "abakus.test"))

        let store = try BudgetStore.open(database, today: { october23 })

        #expect(store.budget.accounts.isEmpty)
        #expect(try database.outbox().isEmpty)
        #expect(try database.isEmpty)
    }

    @Test func openingABudgetEntersDueSchedules() throws {
        var fixture = TestBudget()
        let transaction = Transaction(id: "S1", accountId: fixture.girokonto, date: date("2026-11-02"), amount: -9)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, frequency: .monthly, payeeName: "Netflix", isNew: true)))
        let (store, database) = try opened(fixture.budget, today: date("2026-12-05"))
        #expect(store.budget.transactions.filter { $0.scheduledTransactionId == "S1" }.count == 2)
        #expect(try database.budget().scheduledTransactions.first?.nextDate == date("2027-01-02"))
    }

    @Test func aDeletedOccurrenceIsNotEnteredAgain() throws {
        var fixture = TestBudget()
        let transaction = Transaction(id: "S1", accountId: fixture.girokonto, date: date("2026-11-02"), amount: -9)
        try fixture.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: transaction, frequency: .monthly, payeeName: "Netflix", isNew: true)))
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

        let store = try BudgetStore.open(database, today: { date("2026-11-05") })

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

    @Test func anUnreadableFileIsSetAsideAndTheDemoBudgetOpens() throws {
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
            #expect(store.budget.budgetName == "Demo-Budget")
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

    @Test func theDemoBudgetRoundTripsThroughTheDatabase() throws {
        let budget = DemoBudget.make(today: october23)
        #expect(try savedAndLoaded(budget).syncedRows == budget.syncedRows)
    }
}
