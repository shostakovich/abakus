import Foundation
import SQLite3

public struct SQLiteError: Error, Equatable, LocalizedError {
    public let code: Int32
    public let message: String

    public var errorDescription: String? { "SQLite \(code): \(message)" }

    var isNoDatabase: Bool { code == SQLITE_NOTADB || code == SQLITE_CORRUPT }
}

/// The system's SQLite, one connection, used from one thread.
final class SQLite {
    enum Value: Hashable {
        case null
        case integer(Int64)
        case text(String)

        var text: String? {
            if case .text(let text) = self { text } else { nil }
        }

        var integer: Int64? {
            if case .integer(let number) = self { number } else { nil }
        }
    }

    private let handle: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]

    init(path: String) throws {
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(result))
            sqlite3_close_v2(opened)
            throw SQLiteError(code: result, message: message)
        }
        handle = opened
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        try check(sqlite3_exec(handle, sql, nil, nil, nil))
    }

    func run(_ sql: String, _ values: [Value] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_reset(statement) }
        try check(sqlite3_step(statement), expected: SQLITE_DONE)
    }

    var changes: Int { Int(sqlite3_changes(handle)) }

    func query(_ sql: String, _ values: [Value] = []) throws -> [[String: Value]] {
        let statement = try prepare(sql, values)
        defer { sqlite3_reset(statement) }
        let names = (0..<sqlite3_column_count(statement)).map { String(cString: sqlite3_column_name(statement, $0)) }
        var rows: [[String: Value]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            try check(result, expected: SQLITE_ROW)
            var row: [String: Value] = [:]
            for (index, name) in names.enumerated() { row[name] = column(statement, Int32(index)) }
            rows.append(row)
        }
    }

    func transaction<Result>(_ body: () throws -> Result) throws -> Result {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        let statement = try statements[sql] ?? compile(sql)
        sqlite3_clear_bindings(statement)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case .null: result = sqlite3_bind_null(statement, position)
            case .integer(let number): result = sqlite3_bind_int64(statement, position, number)
            case .text(let text): result = sqlite3_bind_text(statement, position, text, -1, Self.transient)
            }
            if result != SQLITE_OK { try check(result) }
        }
        return statement
    }

    private func compile(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, sql, -1, &statement, nil))
        guard let statement else { throw SQLiteError(code: SQLITE_MISUSE, message: "Empty statement: \(sql)") }
        statements[sql] = statement
        return statement
    }

    private func column(_ statement: OpaquePointer, _ index: Int32) -> Value {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL: .null
        case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, index))
        default: .text(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "")
        }
    }

    private func check(_ result: Int32, expected: Int32 = SQLITE_OK) throws {
        guard result != expected else { return }
        throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(handle)))
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
