import CryptoKit
import Foundation

/// Ids as `sync/PROTOCOL.md` makes them: UUIDv7 for new rows, name-based UUIDv5 for rows with a natural key.
public enum EntityID {
    public static let allAccounts = "Account/__ALL__"

    /// Keys of budget and list rows that are no category of their own.
    public static let incomeMasterCategory = "MasterCategory/__Income__"
    public static let uncategorizedMasterCategory = "MasterCategory/__Uncategorized__"
    public static let uncategorizedCategory = "Category/__UncategorizedSub__"
    /// The editor's split before it has parts; a stored split has no category.
    public static let splitCategory = "Category/__Split__"

    public static func isCategorized(_ categoryId: String?) -> Bool {
        categoryId != nil && categoryId != uncategorizedCategory && categoryId != splitCategory
    }

    public static func createUID(now: Date = Date()) -> String {
        let millis = UInt64(max(now.timeIntervalSince1970 * 1000, 0))
        var bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        for index in 0..<6 { bytes[index] = UInt8(truncatingIfNeeded: millis >> (8 * (5 - index))) }
        bytes[6] = bytes[6] & 0x0F | 0x70
        bytes[8] = bytes[8] & 0x3F | 0x80
        return text(of: bytes)
    }

    public static func assignment(categoryId: String, month: DateWithoutTime) -> String {
        named("assignment", categoryId, month.firstOfMonth.description)
    }

    public static func targetSnooze(categoryId: String, month: DateWithoutTime) -> String {
        named("target_snooze", categoryId, month.firstOfMonth.description)
    }

    public static func targetVersion(categoryId: String, fromMonth: DateWithoutTime) -> String {
        named("target_version", categoryId, fromMonth.firstOfMonth.description)
    }

    public static func transferPayee(accountId: String) -> String {
        named("transfer_payee", accountId)
    }

    public static func enteredTransaction(scheduledId: String, date: DateWithoutTime) -> String {
        named("entered_transaction", scheduledId, date.description)
    }

    public static func enteredSubtransaction(transactionId: String, position: Int) -> String {
        named("entered_subtransaction", transactionId, String(position))
    }

    public static func transferCounterpart(of sideId: String) -> String {
        named("transfer_counterpart", sideId)
    }

    private static let namespace: [UInt8] = [
        0x1d, 0x70, 0xd9, 0x5f, 0x10, 0x2c, 0x41, 0x15, 0x96, 0x6f, 0x5d, 0xb7, 0x32, 0x10, 0xe3, 0x7c,
    ]

    private static func named(_ parts: String...) -> String {
        let name = parts.map { $0.lowercased() }.joined(separator: "/")
        var bytes = Array(Insecure.SHA1.hash(data: namespace + Array(name.utf8)).prefix(16))
        bytes[6] = bytes[6] & 0x0F | 0x50
        bytes[8] = bytes[8] & 0x3F | 0x80
        return text(of: bytes)
    }

    private static func text(of bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let cuts = [8, 12, 16, 20]
        var result = ""
        for (index, character) in hex.enumerated() {
            if cuts.contains(index) { result.append("-") }
            result.append(character)
        }
        return result
    }
}
