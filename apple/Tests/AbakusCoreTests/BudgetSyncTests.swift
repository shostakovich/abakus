import Foundation
import Testing

@testable import AbakusCore

private final class FailingTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: SyncTokens?
    private var _fails = false

    var fails: Bool {
        get { lock.withLock { _fails } }
        set { lock.withLock { _fails = newValue } }
    }

    func load() -> SyncTokens? { lock.withLock { tokens } }

    func save(_ tokens: SyncTokens?) throws {
        if fails { throw KeychainError(status: errSecNotAvailable) }
        lock.withLock { self.tokens = tokens }
    }
}

@MainActor
@Suite struct BudgetSyncTests {
    let server = FakeAbakus()
    let tokens = MemoryTokenStore()
    let december = date("2026-12-01")
    let serverBudget = TestBudget(startingBalances: (400, 0, 0))

    init() {
        server.snapshot = SyncSnapshot(of: serverBudget.budget, cursor: 7)
    }

    private func opened(_ database: BudgetDatabase? = nil) throws -> (BudgetStore, BudgetSync) {
        let store = try BudgetStore.open(database ?? BudgetDatabase(), today: { october23 })
        let made = BudgetSync(store: store, tokens: tokens, transport: server, deviceName: "MacBook", sleep: { _ in })
        return (store, try #require(made))
    }

    private func confirm(_ url: URL) throws -> URL {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let state = try #require(items.first { $0.name == "state" }?.value)
        return URL(string: "local.abakus:/oauth/callback?code=CODE&state=\(state)&iss=https://abakus.test")!
    }

    private func signedIn(_ database: BudgetDatabase? = nil) async throws -> (BudgetStore, BudgetSync) {
        let (store, sync) = try opened(database)
        await sync.signIn(to: FakeAbakus.url) { try confirm($0) }
        try #require(sync.isSignedIn)
        return (store, sync)
    }

    private func restartedSync(_ store: BudgetStore) -> BudgetSync? {
        BudgetSync(store: store, tokens: tokens, transport: server, deviceName: "MacBook", sleep: { _ in })
    }

    private func readyToAssign(_ store: BudgetStore) -> Decimal? {
        store.budget.budgetSheet(today: october23, including: [december]).month(december)?.readyToAssign
    }

    private var grocery: String { serverBudget.groceries }

    @Test func theFirstSignInReplacesTheLocalBudgetAndKeepsItAsABackup() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AbakusTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("budget.sqlite")
        do {
            let (store, sync) = try await signedIn(BudgetDatabase(url: url))

            #expect(store.budget.accounts.map(\.name) == ["Girokonto", "Tagesgeld", "Depot"])
            #expect(store.budget.budgetName == "abakus.test")
            let backup = try BudgetDatabase(url: url.appendingPathExtension("before-sign-in")).budget()
            #expect(backup.budgetName == "Demo-Budget")
            let database = try #require(store.database)
            #expect(try database.deviceId == "mac-1")
            #expect(try database.cursor == 7)
            #expect(try database.outbox().isEmpty)
            #expect(sync.status == .inStep)
            #expect(tokens.load()?.deviceId == "mac-1")
        }
    }

    @Test func signingInAsksWithPKCEAndTheMacsName() async throws {
        let (_, sync) = try opened()
        var asked: URL?
        await sync.signIn(to: FakeAbakus.url) {
            asked = $0
            return try confirm($0)
        }
        let items = try #require(asked.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems)
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
        #expect(asked?.path() == "/oauth/authorize")
        #expect(query["client_id"] == "abakus-apple")
        #expect(query["redirect_uri"] == "local.abakus:/oauth/callback")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"]?.count == 43)
        #expect(query["device_name"] == "MacBook")
    }

    @Test func aCancelledSignInKeepsTheDemoBudget() async throws {
        let (store, sync) = try opened()
        await sync.signIn(to: FakeAbakus.url) { _ in throw SignInError.cancelled }
        #expect(store.budget.budgetName == "Demo-Budget")
        #expect(sync.status == .notSignedIn)
        #expect(sync.signInError == nil)
    }

    @Test func anOfflineAssignmentGoesOutLater() async throws {
        let (store, sync) = try await signedIn()
        #expect(readyToAssign(store) == 400)
        server.offline = true

        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))
        #expect(readyToAssign(store) == 350)
        #expect(await sync.syncOnce() == .failed)
        #expect(sync.status == .offline)
        #expect(sync.pendingChanges == 1)

        server.offline = false
        #expect(await sync.syncOnce() == .synced(quiet: false))
        let sent = server.messages(from: "mac-1")
        #expect(sent.contains { $0.table == "assignments" && $0.column == "amount" && $0.value == .integer(5000) })
        #expect(sync.pendingChanges == 0)
        #expect(sync.status == .inStep)
        #expect(try store.database?.outbox().isEmpty == true)
    }

    @Test func aWaitingRequestReturnsAChangeFromAnotherDevice() async throws {
        let (store, sync) = try await signedIn()
        let account = store.budget.accounts[0].id
        server.waits = true

        let waiting = Task { await sync.syncOnce() }
        try await Task.sleep(for: .milliseconds(30))
        server.write([
            SyncMessage(
                table: "accounts", rowId: account, column: "name", value: .text("Gemeinschaftskonto"),
                clock: "2026-10-23T10:00:00.000Z-0000-web")
        ])

        #expect(await waiting.value == .synced(quiet: false))
        #expect(store.budget.account(withId: account)?.name == "Gemeinschaftskonto")
        #expect(try store.database?.cursor == 8)
    }

    @Test func aFullAnswerIsFollowedByTheRest() async throws {
        let (store, sync) = try await signedIn()
        let accounts = store.budget.accounts.map(\.id)
        server.pageSize = 2
        server.write(
            accounts.map {
                SyncMessage(
                    table: "accounts", rowId: $0, column: "note", value: .text("Neu"),
                    clock: "2026-10-23T10:00:00.000Z-0000-web")
            })

        #expect(await sync.syncOnce() == .synced(quiet: false))
        #expect(store.budget.accounts.filter { $0.note == "Neu" }.count == 2)
        #expect(await sync.syncOnce() == .synced(quiet: false))

        #expect(store.budget.accounts.allSatisfy { $0.note == "Neu" })
        #expect(try store.database?.cursor == 10)
    }

    @Test func tokensAboutToRunOutAreRefreshedFirst() async throws {
        var wall = Date()
        let store = try BudgetStore.open(BudgetDatabase(), today: { october23 })
        let made = BudgetSync(
            store: store, tokens: tokens, transport: server, deviceName: "MacBook", now: { wall }, sleep: { _ in })
        let sync = try #require(made)
        await sync.signIn(to: FakeAbakus.url) { try confirm($0) }
        wall = wall.addingTimeInterval(3_550)

        #expect(await sync.syncOnce() == .synced(quiet: true))

        #expect(tokens.load()?.refreshToken == "refresh-2")
        #expect(server.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
    }

    @Test func aCommandInterruptsTheWaitingRequestAndGoesOut() async throws {
        let (store, sync) = try await signedIn()
        server.waits = true
        sync.start()
        try await Task.sleep(for: .milliseconds(30))

        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))

        try await eventually { !server.messages(from: "mac-1").isEmpty }
        sync.stop()
        #expect(server.messages(from: "mac-1").contains { $0.table == "assignments" })
    }

    @Test func aRefusedTokenSignsTheMacOutAndKeepsItsUnsentChanges() async throws {
        let (store, sync) = try await signedIn()
        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))
        server.refusesTokens = true

        #expect(await sync.syncOnce() == .signedOut)

        #expect(sync.status == .signedOutRemotely)
        #expect(!sync.isSignedIn)
        #expect(tokens.load() == nil)
        #expect(try store.database?.pendingChanges == 1)
        #expect(readyToAssign(store) == 350)
    }

    @Test func signingInAgainSendsTheUnsentChangesAsTheNewDevice() async throws {
        let (store, sync) = try await signedIn()
        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))
        server.refusesTokens = true
        await sync.syncOnce()
        server.refusesTokens = false
        server.deviceId = "mac-2"

        await sync.signIn(to: FakeAbakus.url) { try confirm($0) }
        #expect(readyToAssign(store) == 350)
        #expect(await sync.syncOnce() == .synced(quiet: false))

        #expect(server.messages(from: "mac-2").contains { $0.table == "assignments" && $0.clock.hasSuffix("-mac-2") })
    }

    @Test func anExpiredAccessTokenIsRefreshed() async throws {
        let (store, sync) = try await signedIn()
        server.expireAccessTokens()
        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))

        #expect(await sync.syncOnce() == .synced(quiet: false))
        #expect(tokens.load()?.refreshToken == "refresh-2")
        #expect(!server.messages(from: "mac-1").isEmpty)
    }

    @Test func aKeychainFailureKeepsTheRotatedTokensInMemory() async throws {
        let keychain = FailingTokenStore()
        let store = try BudgetStore.open(BudgetDatabase(), today: { october23 })
        let made = BudgetSync(store: store, tokens: keychain, transport: server, deviceName: "MacBook", sleep: { _ in })
        let sync = try #require(made)
        await sync.signIn(to: FakeAbakus.url) { try confirm($0) }
        keychain.fails = true
        server.expireAccessTokens()
        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))
        await sync.syncOnce()
        keychain.fails = false

        #expect(await sync.syncOnce() == .synced(quiet: false))
        #expect(sync.isSignedIn)
        #expect(server.messages(from: "mac-1").contains { $0.table == "assignments" })
    }

    @Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "CI runners have no login keychain"))
    func theKeychainKeepsTheLatestTokens() throws {
        let keychain = KeychainTokenStore(account: "AbakusTests-\(UUID().uuidString)")
        defer { try? keychain.save(nil) }
        let first = SyncTokens(accessToken: "a1", refreshToken: "r1", expiresAt: Date(), deviceId: "mac-1")
        var second = first
        second.refreshToken = "r2"

        try keychain.save(first)
        try keychain.save(second)
        #expect(keychain.load() == second)
        try keychain.save(nil)
        #expect(keychain.load() == nil)
    }

    @Test func signingOutDuringARefreshKeepsTheMacSignedOut() async throws {
        let (store, sync) = try await signedIn()
        server.expireAccessTokens()
        server.holdsRefreshes = true
        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))
        let syncing = Task { await sync.syncOnce() }
        try await eventually { server.refreshRequested }

        await sync.signOut()
        server.holdsRefreshes = false
        _ = await syncing.value

        #expect(!sync.isSignedIn)
        #expect(tokens.load() == nil)
        #expect(sync.status == .notSignedIn)
    }

    @Test func aCommandDuringARefreshGoesOutWithoutWaiting() async throws {
        let (store, sync) = try await signedIn()
        server.waits = true
        server.expireAccessTokens()
        server.holdsRefreshes = true
        let syncing = Task { await sync.syncOnce() }
        try await eventually { server.refreshRequested }

        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))
        server.holdsRefreshes = false

        try await eventually { server.messages(from: "mac-1").contains { $0.table == "assignments" } }
        sync.syncNow()
        _ = await syncing.value
    }

    @Test func aClockErrorAsksToCorrectTheTime() async throws {
        let (store, sync) = try await signedIn()
        server.clockAhead = true
        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))

        #expect(await sync.syncOnce() == .failed)
        #expect(sync.status == .error(.clockAhead("Die Uhr geht vor.")))
        #expect(sync.pendingChanges == 1)
    }

    @Test func aCorrectedClockLetsTheRefusedChangesGoOut() async throws {
        var wall = Date().addingTimeInterval(86_400)
        let database = try BudgetDatabase()
        let store = try BudgetStore.open(database, today: { october23 }, now: { wall })
        let made = BudgetSync(
            store: store, tokens: tokens, transport: server, deviceName: "MacBook", now: { wall }, sleep: { _ in })
        let sync = try #require(made)
        await sync.signIn(to: FakeAbakus.url) { try confirm($0) }
        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))
        #expect(await sync.syncOnce() == .failed)
        #expect(sync.status == .error(.clockAhead("Die Uhr geht vor.")))

        wall = Date()
        #expect(await sync.syncOnce() == .synced(quiet: false))

        #expect(server.messages(from: "mac-1").contains { $0.table == "assignments" })
        #expect(try database.outbox().isEmpty)
        #expect(try database.nextClock(now: wall).millis <= Int64(wall.timeIntervalSince1970 * 1000) + 1)
        #expect(sync.status == .inStep)
    }

    @Test func aRefusedPushStillPullsAndKeepsTheOutbox() async throws {
        let (store, sync) = try await signedIn()
        let account = store.budget.accounts[0].id
        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))
        server.refusesPushes = true
        server.write([
            SyncMessage(
                table: "accounts", rowId: account, column: "name", value: .text("Gemeinschaftskonto"),
                clock: "2026-10-23T10:00:00.000Z-0000-web")
        ])

        #expect(await sync.syncOnce() == .failed)

        #expect(store.budget.account(withId: account)?.name == "Gemeinschaftskonto")
        #expect(sync.pendingChanges == 1)
        #expect(sync.status == .error(.failed("foreign clock")))
    }

    @Test func aRefusedVersionAsksToUpdateTheApp() async throws {
        let (_, sync) = try await signedIn()
        server.speaksProtocol = false

        #expect(await sync.syncOnce() == .failed)
        #expect(sync.status == .error(.unsupportedProtocol("Bitte aktualisieren.")))
    }

    @Test func signingOutCountsTheUnsentChangesAndShowsTheDemoBudget() async throws {
        let (store, sync) = try await signedIn()
        server.offline = true
        for amount: Decimal in [10, 20, 30] {
            try store.perform(.setAssigned(month: december, categoryId: grocery, amount: amount))
        }
        #expect(sync.pendingChanges == 3)
        server.offline = false

        await sync.signOut()

        #expect(store.budget.budgetName == "Demo-Budget")
        #expect(sync.status == .notSignedIn)
        #expect(tokens.load() == nil)
        #expect(try store.database?.deviceId == BudgetDatabase.unsignedDevice)
        #expect(try store.database?.serverURL == FakeAbakus.url)
        #expect(server.requests.contains { $0.url?.path() == "/oauth/revoke" })
    }

    @Test func signingOutLeavesNoCopyOfTheServersBudget() async throws {
        var budget = serverBudget.budget
        budget.accounts[0].name = "Geheimkonto"
        server.snapshot = SyncSnapshot(of: budget, cursor: 7)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AbakusTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("budget.sqlite")
        let (store, sync) = try await signedIn(BudgetDatabase(url: url))
        let dailyBackup = url.appendingPathExtension("bak")
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: dailyBackup.path)
        try store.perform(.setAssigned(month: december, categoryId: grocery, amount: 50))
        server.refusesTokens = true
        await sync.syncOnce()
        server.refusesTokens = false
        await sync.signIn(to: FakeAbakus.url) { try confirm($0) }

        await sync.signOut()

        let beforeSignIn = url.appendingPathExtension("before-sign-in")
        for file in [url, dailyBackup, beforeSignIn]
        where FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            #expect(data.range(of: Data("Geheimkonto".utf8)) == nil, "\(file.lastPathComponent)")
        }
    }

    @Test func signingOutKeepsTheBudgetFromBeforeTheFirstSignIn() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AbakusTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("budget.sqlite")
        let (_, sync) = try await signedIn(BudgetDatabase(url: url))

        await sync.signOut()

        let backup = try BudgetDatabase(url: url.appendingPathExtension("before-sign-in")).budget()
        #expect(backup.budgetName == "Demo-Budget")
    }

    @Test func aSignedOutDeviceStaysSignedOutAfterARestart() async throws {
        let database = try BudgetDatabase()
        let (_, sync) = try await signedIn(database)
        server.refusesTokens = true
        await sync.syncOnce()

        let restarted = BudgetSync(
            store: BudgetStore(budget: Budget(budgetName: ""), database: database), tokens: tokens,
            transport: server, deviceName: "MacBook")
        #expect(restarted?.status == .signedOutRemotely)
    }

    @Test func aSignedInMacEntersDueSchedulesOnlyAfterItsFirstPull() async throws {
        var budget = serverBudget
        let schedule = Transaction(id: "S1", accountId: budget.girokonto, date: date("2026-10-30"), amount: -9)
        try budget.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: schedule, frequency: .monthly, payeeName: "Netflix", isNew: true)))
        server.snapshot = SyncSnapshot(of: budget.budget, cursor: 7)
        let database = try BudgetDatabase()
        _ = try await signedIn(database)
        let occurrence = EntityID.enteredTransaction(scheduledId: "S1", date: date("2026-10-30"))
        let clock = "2026-10-31T10:00:00.000Z-0000-server"
        let fields: [(String, SyncValue)] = [
            ("account_id", .text(budget.girokonto)), ("date", .text("2026-10-30")), ("amount", .integer(-900)),
            ("approved", .bool(true)), ("memo", .text("Vom Web")), ("scheduled_transaction_id", .text("S1")),
            ("scheduled_date", .text("2026-10-30")),
        ]
        server.write(
            fields.map { SyncMessage(table: "transactions", rowId: occurrence, column: $0, value: $1, clock: clock) }
                + [
                    SyncMessage(
                        table: "scheduled_transactions", rowId: "S1", column: "next_date", value: .text("2026-11-30"),
                        clock: clock)
                ], from: "server")

        let store = try BudgetStore.open(database, today: { date("2026-11-05") })
        #expect(try database.outbox().isEmpty)
        #expect(store.budget.transaction(withId: occurrence) == nil)
        let restarted = try #require(restartedSync(store))
        #expect(await restarted.syncOnce() == .synced(quiet: false))

        #expect(store.budget.transaction(withId: occurrence)?.memo == "Vom Web")
        #expect(store.budget.transaction(withId: occurrence)?.approved == true)
        #expect(try database.outbox().isEmpty)
    }

    @Test func dueSchedulesAreEnteredAfterAPull() async throws {
        var budget = serverBudget
        let schedule = Transaction(id: "S1", accountId: budget.girokonto, date: date("2026-10-30"), amount: -9)
        try budget.budget.apply(
            .saveScheduledTransaction(
                ScheduledSave(transaction: schedule, frequency: .monthly, payeeName: "Netflix", isNew: true)))
        server.snapshot = SyncSnapshot(of: budget.budget, cursor: 7)
        let database = try BudgetDatabase()
        _ = try await signedIn(database)

        let store = try BudgetStore.open(database, today: { date("2026-11-05") })
        let restarted = try #require(restartedSync(store))
        await restarted.syncOnce()

        let occurrence = EntityID.enteredTransaction(scheduledId: "S1", date: date("2026-10-30"))
        #expect(store.budget.transaction(withId: occurrence) != nil)
        #expect(try database.outbox().contains { $0.rowId == occurrence })
    }

    @Test func aSyncedBudgetInventsNoReadyToAssign() throws {
        var rows = serverBudget.budget.syncedRows
        let internalGroup = try #require(serverBudget.budget.categoryGroups.first { $0.isInternal })
        rows["category_groups"]?[internalGroup.id] = nil
        for category in internalGroup.categories { rows["categories"]?[category.id] = nil }

        let loaded = Budget(syncedRows: rows, local: LocalBudgetSettings(budgetName: ""))

        #expect(!loaded.categoryGroups.contains { $0.isInternal })
        #expect(loaded.readyToAssignCategoryId == "")
        let server = Budget(syncedRows: serverBudget.budget.syncedRows, local: LocalBudgetSettings(budgetName: ""))
        #expect(server.readyToAssignCategoryId == serverBudget.budget.readyToAssignCategoryId)
    }

    @Test func tokensOfAnotherDatabaseAreDropped() throws {
        try tokens.save(SyncTokens(accessToken: "a", refreshToken: "r", expiresAt: Date(), deviceId: "mac-1"))

        let (_, sync) = try opened()

        #expect(!sync.isSignedIn)
        #expect(sync.status == .notSignedIn)
        #expect(tokens.load() == nil)
    }

    @Test func theSnapshotsClocksDecideWhichLaterMessagesWin() throws {
        let database = try BudgetDatabase()
        let row = SyncSnapshot.Row(
            id: "giro", fields: ["name": .text("Giro"), "kind": .text("checking")],
            clocks: ["name": "2026-11-02T10:00:00.000Z-0000-server"])
        try database.adopt(
            SyncSnapshot(cursor: 3, tables: ["accounts": [row]]), deviceId: "mac-1", serverURL: FakeAbakus.url,
            settings: LocalBudgetSettings(budgetName: ""))

        try database.receive([
            SyncMessage(
                table: "accounts", rowId: "giro", column: "name", value: .text("Älter"),
                clock: "2026-11-01T10:00:00.000Z-0000-web"),
            SyncMessage(
                table: "accounts", rowId: "giro", column: "note", value: .text("Neu"),
                clock: "2026-11-01T10:00:00.000Z-0000-web"),
        ])

        let account = try database.budget().account(withId: "giro")
        #expect(account?.name == "Giro")
        #expect(account?.note == "Neu")
        #expect(
            try database.nextClock(now: Date(timeIntervalSince1970: 0)).description
                == "2026-11-02T10:00:00.000Z-0001-mac-1")
    }

    @Test func serverAddressesNeedAScheme() {
        #expect(
            BudgetSync.serverURL(from: " https://abakus.example.org/ ")?.absoluteString
                == "https://abakus.example.org")
        #expect(BudgetSync.serverURL(from: "abakus.example.org") == nil)
        #expect(BudgetSync.serverURL(from: "ftp://abakus.example.org") == nil)
    }

    @Test func plainHTTPIsOnlyForThisMac() {
        #expect(BudgetSync.serverURL(from: "http://abakus.example.org") == nil)
        #expect(BudgetSync.serverURL(from: "http://localhost:4000")?.absoluteString == "http://localhost:4000")
        #expect(BudgetSync.serverURL(from: "http://127.0.0.1:4000") != nil)
        #expect(BudgetSync.serverURL(from: "http://[::1]:4000") != nil)
    }

    @Test func anInsecureConnectionIsNoOfflineServer() async throws {
        let (_, sync) = try opened()
        server.failure = .serverCertificateUntrusted
        await sync.signIn(to: FakeAbakus.url) { try confirm($0) }
        #expect(sync.signInError?.contains("sicher") == true)

        server.failure = nil
        await sync.signIn(to: FakeAbakus.url) { try confirm($0) }
        server.failure = .appTransportSecurityRequiresSecureConnection
        #expect(await sync.syncOnce() == .failed)
        guard case .error(let problem) = sync.status else {
            Issue.record("\(sync.status) is no error")
            return
        }
        #expect(problem.message.contains("https://"))
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
