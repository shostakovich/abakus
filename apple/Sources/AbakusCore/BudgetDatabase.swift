import Foundation

public enum BudgetDatabaseError: Error, Equatable, Sendable, LocalizedError {
    case notAFile(path: String)
    case unreadable(path: String, reason: String)
    case inUse(path: String)

    public var errorDescription: String? {
        switch self {
        case .inUse(let path):
            "Das Budget \(path) ist schon in einem anderen Abakus geöffnet. Beende zuerst dieses."
        case .notAFile(let path): "Das Budget \(path) ist ein Ordner, keine Datei."
        case .unreadable(let path, let reason): "Das Budget \(path) ließ sich nicht öffnen. \(reason)"
        }
    }
}

public final class BudgetDatabase {
    public static let unsignedDevice = "local"

    public let url: URL?
    /// Says where a file that was no budget went.
    public let openNotice: String?
    private let sqlite: SQLite
    private let lock: BudgetLock?

    public static func location(environment: [String: String]) -> URL? {
        guard let path = environment["ABAKUS_DATABASE"]?.trimmingCharacters(in: .whitespaces), !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    public static var defaultLocation: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Abakus/budget.sqlite")
    }

    public init(url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw BudgetDatabaseError.notAFile(path: url.path)
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw BudgetDatabaseError.unreadable(path: url.path, reason: error.localizedDescription)
        }
        guard let lock = try BudgetLock(url: url.appendingPathExtension("lock")) else {
            throw BudgetDatabaseError.inUse(path: url.path)
        }
        do {
            sqlite = try Self.opened(url)
            openNotice = nil
        } catch let error as SQLiteError where error.isNoDatabase {
            let aside: URL
            do {
                aside = try Self.setAside(url)
                sqlite = try Self.opened(url)
            } catch {
                throw BudgetDatabaseError.unreadable(path: url.path, reason: error.localizedDescription)
            }
            openNotice =
                "Dein Budget ließ sich nicht lesen (\(error.message)). Es liegt jetzt als „\(aside.lastPathComponent)“ "
                + "in \(aside.deletingLastPathComponent().path), stattdessen ist das Demo-Budget geöffnet."
        } catch {
            throw BudgetDatabaseError.unreadable(path: url.path, reason: error.localizedDescription)
        }
        self.url = url
        self.lock = lock
    }

    public init() throws {
        sqlite = try SQLite(path: ":memory:")
        try Self.createSchema(in: sqlite)
        url = nil
        openNotice = nil
        lock = nil
    }

    private static func opened(_ url: URL) throws -> SQLite {
        let sqlite = try SQLite(path: url.path)
        try createSchema(in: sqlite)
        return sqlite
    }

    private static func setAside(_ url: URL) throws -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        let base = url.deletingPathExtension()
        var aside = base.appendingPathExtension("unreadable-\(stamp).sqlite")
        var counter = 2
        while FileManager.default.fileExists(atPath: aside.path) {
            aside = base.appendingPathExtension("unreadable-\(stamp)-\(counter).sqlite")
            counter += 1
        }
        try FileManager.default.moveItem(at: url, to: aside)
        let journal = URL(fileURLWithPath: url.path + "-journal")
        if FileManager.default.fileExists(atPath: journal.path) {
            try FileManager.default.moveItem(at: journal, to: URL(fileURLWithPath: aside.path + "-journal"))
        }
        return aside
    }

    public var backupURL: URL? { url?.appendingPathExtension("bak") }

    private static let schemaVersion = 2

    private static func createSchema(in sqlite: SQLite) throws {
        let version = try sqlite.query("PRAGMA user_version").first?["user_version"]
        if version == .integer(1) {
            try sqlite.execute(
                "CREATE INDEX sync_field_clocks_clock ON sync_field_clocks (clock); PRAGMA user_version = 2;")
        }
        guard version == .integer(0) else { return }
        let tables = SyncTable.all.map { table in
            let columns = table.columns.map { quoted($0.name) }.joined(separator: ", ")
            return "CREATE TABLE \(quoted(table.name)) (id TEXT PRIMARY KEY, \(columns));"
        }
        try sqlite.transaction {
            try sqlite.execute(
                tables.joined(separator: "\n") + """
                    CREATE TABLE sync_messages (
                      id INTEGER PRIMARY KEY AUTOINCREMENT, "table" TEXT NOT NULL, row_id TEXT NOT NULL,
                      "column" TEXT NOT NULL, value TEXT NOT NULL, clock TEXT NOT NULL,
                      outbox INTEGER NOT NULL DEFAULT 0);
                    CREATE UNIQUE INDEX sync_messages_field_clock ON sync_messages (clock, "table", row_id, "column");
                    CREATE INDEX sync_messages_outbox ON sync_messages (id) WHERE outbox = 1;
                    CREATE TABLE sync_field_clocks (
                      "table" TEXT NOT NULL, row_id TEXT NOT NULL, "column" TEXT NOT NULL, clock TEXT NOT NULL,
                      PRIMARY KEY ("table", row_id, "column")) WITHOUT ROWID;
                    CREATE INDEX sync_field_clocks_clock ON sync_field_clocks (clock);
                    CREATE TABLE sync_state (
                      id INTEGER PRIMARY KEY CHECK (id = 1), device_id TEXT NOT NULL, cursor INTEGER NOT NULL,
                      server_url TEXT);
                    INSERT INTO sync_state (id, device_id, cursor) VALUES (1, '\(unsignedDevice)', 0);
                    CREATE TABLE local_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                    PRAGMA user_version = \(schemaVersion);
                    """)
        }
    }

    private static func quoted(_ name: String) -> String { "\"\(name)\"" }

    public var isEmpty: Bool {
        get throws {
            try SyncTable.all.allSatisfy { table in
                try sqlite.query("SELECT 1 FROM \(Self.quoted(table.name)) LIMIT 1").isEmpty
            }
        }
    }

    public func rows() throws -> SyncRows {
        var rows: SyncRows = [:]
        for table in SyncTable.all {
            rows[table.name] = Dictionary(
                uniqueKeysWithValues: try sqlite.query("SELECT * FROM \(Self.quoted(table.name))").compactMap {
                    Self.row($0, in: table)
                })
        }
        return rows
    }

    public func transactionIds() throws -> Set<String> {
        Set(try sqlite.query("SELECT id FROM transactions").compactMap { $0["id"]?.text })
    }

    func row(_ key: RowKey) throws -> SyncRow? {
        guard let table = SyncTable.named(key.table) else { return nil }
        let found = try sqlite.query("SELECT * FROM \(Self.quoted(table.name)) WHERE id = ?", [.text(key.id)])
        return found.first.flatMap { Self.row($0, in: table)?.value }
    }

    private static func row(_ values: [String: SQLite.Value], in table: SyncTable) -> (key: String, value: SyncRow)? {
        guard let id = values["id"]?.text else { return nil }
        var row: SyncRow = [:]
        for column in table.columns { row[column.name] = syncValue(values[column.name] ?? .null, as: column.kind) }
        return (id, row)
    }

    private static func syncValue(_ value: SQLite.Value, as kind: SyncTable.Kind) -> SyncValue {
        switch (value, kind) {
        case (.null, _): .null
        case (.integer(let number), .boolean): .bool(number != 0)
        case (.integer(let number), _): .integer(Int(number))
        case (.text(let text), _): .text(text)
        }
    }

    private static func sqliteValue(_ value: SyncValue) -> SQLite.Value {
        switch value {
        case .null: .null
        case .bool(let flag): .integer(flag ? 1 : 0)
        case .integer(let number): .integer(Int64(number))
        case .text(let text): .text(text)
        }
    }

    public func budget() throws -> Budget {
        Budget(syncedRows: try rows(), local: try localSettings())
    }

    /// All messages of one save share one clock.
    @discardableResult
    public func save(_ budget: Budget, over previous: Budget?, now: Date) throws -> Bool {
        let (old, new) = previous.map(budget.changedRows(since:)) ?? ([:], budget.syncedRows)
        var stored: [RowKey: SyncRow] = [:]
        for key in BudgetDiff.addedRows(from: old, to: new) { stored[key] = try row(key) }
        let changes = BudgetDiff.changes(
            from: old, to: new, stored: stored, successors: budget.successorIds, deletedAt: .moment(now))
        try sqlite.transaction {
            if !changes.isEmpty {
                let clock = try nextClock(now: now).description
                try store(
                    changes.map {
                        SyncMessage(table: $0.table, rowId: $0.rowId, column: $0.column, value: $0.value, clock: clock)
                    }, outbox: true)
            }
            try write(budget.localSettings)
        }
        return !changes.isEmpty
    }

    public func receive(_ messages: [SyncMessage]) throws {
        try sqlite.transaction { try store(messages, outbox: false) }
    }

    public func markSent(_ messages: [SyncMessage]) throws {
        try sqlite.transaction {
            for message in messages {
                try sqlite.run(
                    #"UPDATE sync_messages SET outbox = 0 WHERE clock = ? AND "table" = ? AND row_id = ? AND "column" = ?"#,
                    [.text(message.clock), .text(message.table), .text(message.rowId), .text(message.column)])
            }
        }
    }

    /// The changes not yet sent; all messages of one change share a clock.
    public var pendingChanges: Int {
        get throws {
            let found = try sqlite.query("SELECT count(DISTINCT clock) AS count FROM sync_messages WHERE outbox = 1")
            return Int(found.first?["count"]?.integer ?? 0)
        }
    }

    /// The server's rows replace the budget, and `pending` goes out again as this device's.
    public func adopt(
        _ snapshot: SyncSnapshot, deviceId: String, serverURL: URL, settings: LocalBudgetSettings,
        pending: [SyncMessage] = []
    ) throws {
        try sqlite.transaction {
            try clear()
            for table in SyncTable.all {
                for row in snapshot.tables[table.name] ?? [] { try insert(row, into: table) }
            }
            try sqlite.run(
                "UPDATE sync_state SET device_id = ?, cursor = ?, server_url = ?",
                [.text(deviceId), .integer(Int64(snapshot.cursor)), .text(serverURL.absoluteString)])
            try write(settings)
            try store(pending.compactMap { $0.restamped(for: deviceId) }, outbox: true)
        }
    }

    /// Leaves no copy of a server's budget, neither in free pages nor in a backup; the address stays.
    public func reset() throws {
        try sqlite.transaction {
            try clear()
            try sqlite.run("UPDATE sync_state SET device_id = ?, cursor = 0", [.text(Self.unsignedDevice)])
        }
        try sqlite.execute("VACUUM")
        for backup in [backupURL, beforeSignInURL].compactMap(\.self) where Self.holdsServerBudget(backup) {
            try? FileManager.default.removeItem(at: backup)
        }
    }

    private static func holdsServerBudget(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path), let backup = try? SQLite(path: url.path) else {
            return false
        }
        let device = try? backup.query("SELECT device_id FROM sync_state WHERE id = 1").first?["device_id"]?.text
        return device.map { $0 != unsignedDevice } ?? false
    }

    private func clear() throws {
        for table in SyncTable.all { try sqlite.run("DELETE FROM \(Self.quoted(table.name))") }
        try sqlite.run("DELETE FROM sync_messages")
        try sqlite.run("DELETE FROM sync_field_clocks")
        try sqlite.run("DELETE FROM local_settings")
    }

    private func insert(_ row: SyncSnapshot.Row, into table: SyncTable) throws {
        let columns = table.columns.map { Self.quoted($0.name) }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: table.columns.count + 1).joined(separator: ", ")
        let id = row.id
        try sqlite.run(
            "INSERT OR REPLACE INTO \(Self.quoted(table.name)) (id, \(columns)) VALUES (\(placeholders))",
            [.text(id)] + table.columns.map { Self.sqliteValue(row.fields[$0.name] ?? $0.defaultValue) })
        for (column, clock) in row.clocks where table.column(named: column) != nil {
            try sqlite.run(
                #"INSERT OR REPLACE INTO sync_field_clocks ("table", row_id, "column", clock) VALUES (?, ?, ?, ?)"#,
                [.text(table.name), .text(id), .text(column), .text(clock)])
        }
    }

    private var beforeSignInURL: URL? { url?.appendingPathExtension("before-sign-in") }

    public func backUpBeforeSignIn() throws {
        guard let beforeSignInURL else { return }
        try copy(to: beforeSignInURL)
    }

    /// An older message is still stored, so a repeated push is recognised.
    private func store(_ messages: [SyncMessage], outbox: Bool) throws {
        for message in messages {
            guard let table = SyncTable.named(message.table), table.column(named: message.column) != nil else {
                continue
            }
            try sqlite.run(
                """
                INSERT OR IGNORE INTO sync_messages ("table", row_id, "column", value, clock, outbox)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(message.table), .text(message.rowId), .text(message.column), .text(Self.json(message.value)),
                    .text(message.clock), .integer(outbox ? 1 : 0),
                ])
            guard sqlite.changes > 0, try isNewer(message) else { continue }
            try put(message, in: table)
        }
    }

    private func isNewer(_ message: SyncMessage) throws -> Bool {
        let current = try sqlite.query(
            #"SELECT clock FROM sync_field_clocks WHERE "table" = ? AND row_id = ? AND "column" = ?"#,
            [.text(message.table), .text(message.rowId), .text(message.column)]
        ).first?["clock"]?.text
        return current.map { message.clock > $0 } ?? true
    }

    private func put(_ message: SyncMessage, in table: SyncTable) throws {
        let name = Self.quoted(table.name)
        let columns = table.columns.map { Self.quoted($0.name) }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: table.columns.count + 1).joined(separator: ", ")
        try sqlite.run(
            "INSERT OR IGNORE INTO \(name) (id, \(columns)) VALUES (\(placeholders))",
            [.text(message.rowId)] + table.columns.map { Self.sqliteValue($0.defaultValue) })
        try sqlite.run(
            "UPDATE \(name) SET \(Self.quoted(message.column)) = ? WHERE id = ?",
            [Self.sqliteValue(message.value), .text(message.rowId)])
        try sqlite.run(
            """
            INSERT INTO sync_field_clocks ("table", row_id, "column", clock) VALUES (?, ?, ?, ?)
            ON CONFLICT ("table", row_id, "column") DO UPDATE SET clock = excluded.clock
            """,
            [.text(message.table), .text(message.rowId), .text(message.column), .text(message.clock)])
    }

    private static func json(_ value: SyncValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    private static func value(json: String) -> SyncValue {
        (try? JSONDecoder().decode(SyncValue.self, from: Data(json.utf8))) ?? .null
    }

    /// The device's newest clock is the newest of every field's, so receiving a newer one moves it past that.
    func nextClock(now: Date) throws -> SyncClock {
        let newest = try sqlite.query("SELECT max(clock) AS clock FROM sync_field_clocks").first?["clock"]?.text
        let last = newest.flatMap(SyncClock.init)
        return SyncClock.tick(after: last, now: now, device: try deviceId)
    }

    /// The outbox's clocks a wrong wall time put ahead, and the fields holding them, get fresh ones in their order.
    public func restampFutureClocks(now: Date) throws {
        let device = try deviceId
        let wall = SyncClock.tick(after: nil, now: now, device: device).millis
        let limit = SyncClock(millis: wall, counter: 0xffff, device: "~").description
        let later = try sqlite.query(
            #"SELECT DISTINCT clock FROM sync_messages WHERE outbox = 1 AND clock > ? ORDER BY clock"#, [.text(limit)]
        ).compactMap { $0["clock"]?.text.flatMap(SyncClock.init) }.filter { $0.device == device }
        guard !later.isEmpty else { return }
        let restamped = Set(later.map(\.description))
        try sqlite.transaction {
            let kept = try sqlite.query(
                #"SELECT DISTINCT clock FROM sync_field_clocks WHERE clock > ?"#, [.text(limit)]
            )
            .compactMap { $0["clock"]?.text }.filter { !restamped.contains($0) }
            let past = try sqlite.query(
                "SELECT max(clock) AS clock FROM sync_field_clocks WHERE clock <= ?", [.text(limit)]
            )
            .first?["clock"]?.text
            var last = ([past].compactMap(\.self) + kept).max().flatMap(SyncClock.init)
            for old in later {
                let fresh = SyncClock.tick(after: last, now: now, device: device)
                last = fresh
                let values: [SQLite.Value] = [.text(fresh.description), .text(old.description)]
                try sqlite.run("UPDATE sync_messages SET clock = ? WHERE clock = ? AND outbox = 1", values)
                try sqlite.run("UPDATE sync_field_clocks SET clock = ? WHERE clock = ?", values)
            }
        }
    }

    public var deviceId: String {
        get throws { try state("device_id")?.text ?? Self.unsignedDevice }
    }

    public var cursor: Int {
        get throws { try state("cursor")?.integer.map(Int.init) ?? 0 }
    }

    public func setCursor(_ cursor: Int) throws {
        try sqlite.run("UPDATE sync_state SET cursor = ?", [.integer(Int64(cursor))])
    }

    public var serverURL: URL? {
        get throws { try state("server_url")?.text.flatMap(URL.init(string:)) }
    }

    private func state(_ column: String) throws -> SQLite.Value? {
        try sqlite.query("SELECT \(column) FROM sync_state WHERE id = 1").first?[column]
    }

    public func outbox() throws -> [SyncMessage] {
        try sqlite.query(
            #"SELECT "table", row_id, "column", value, clock FROM sync_messages WHERE outbox = 1 ORDER BY id"#
        )
        .compactMap { row in
            guard let table = row["table"]?.text, let rowId = row["row_id"]?.text,
                let column = row["column"]?.text, let value = row["value"]?.text, let clock = row["clock"]?.text
            else { return nil }
            return SyncMessage(
                table: table, rowId: rowId, column: column, value: Self.value(json: value), clock: clock)
        }
    }

    public func localSettings() throws -> LocalBudgetSettings {
        let pairs = try sqlite.query("SELECT key, value FROM local_settings").compactMap { row -> (String, String)? in
            guard let key = row["key"]?.text, let value = row["value"]?.text else { return nil }
            return (key, value)
        }
        let values = Dictionary(pairs) { first, _ in first }
        let defaults = BudgetMetaData()
        let collapsed = values["collapsed_category_group_ids"].flatMap {
            try? JSONDecoder().decode([String].self, from: Data($0.utf8))
        }
        return LocalBudgetSettings(
            budgetName: values["budget_name"] ?? "",
            budgetMetaData: BudgetMetaData(
                budgetType: values["budget_type"].flatMap(BudgetType.init(rawValue:)) ?? defaults.budgetType,
                currencyISOSymbol: values["currency_iso_symbol"] ?? defaults.currencyISOSymbol,
                currencyLocale: values["currency_locale"] ?? defaults.currencyLocale,
                dateLocale: values["date_locale"] ?? defaults.dateLocale,
                strictBudget: values["strict_budget"].map { $0 == "true" } ?? defaults.strictBudget),
            collapsedCategoryGroupIds: Set(collapsed ?? []))
    }

    private func write(_ settings: LocalBudgetSettings) throws {
        let collapsed =
            (try? JSONEncoder().encode(settings.collapsedCategoryGroupIds.sorted()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let values = [
            "budget_name": settings.budgetName,
            "budget_type": settings.budgetMetaData.budgetType.rawValue,
            "currency_iso_symbol": settings.budgetMetaData.currencyISOSymbol,
            "currency_locale": settings.budgetMetaData.currencyLocale,
            "date_locale": settings.budgetMetaData.dateLocale,
            "strict_budget": settings.budgetMetaData.strictBudget ? "true" : "false",
            "collapsed_category_group_ids": collapsed,
        ]
        for (key, value) in values {
            try sqlite.run(
                "INSERT INTO local_settings (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value",
                [.text(key), .text(value)])
        }
    }

    public func backUpOncePerDay(today: DateWithoutTime) throws {
        guard let backupURL else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: backupURL.path)
        if let modified = attributes?[.modificationDate] as? Date, DateWithoutTime.today(now: modified) >= today {
            return
        }
        try copy(to: backupURL)
    }

    private func copy(to destination: URL) throws {
        let fresh = destination.appendingPathExtension("new")
        try? FileManager.default.removeItem(at: fresh)
        try sqlite.run("VACUUM INTO ?", [.text(fresh.path)])
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: fresh)
    }

    func fieldClocks() throws -> [String: String] {
        let rows = try sqlite.query(#"SELECT "table", row_id, "column", clock FROM sync_field_clocks"#)
        return Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                guard let table = row["table"]?.text, let id = row["row_id"]?.text, let column = row["column"]?.text,
                    let clock = row["clock"]?.text
                else { return nil }
                return ("\(table)/\(id)/\(column)", clock)
            })
    }

    func execute(_ sql: String) throws {
        try sqlite.execute(sql)
    }
}
