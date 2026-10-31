/// Parents before their parts; a row made from messages starts with the defaults.
public struct SyncTable: Sendable {
    public enum Kind: Sendable {
        case text, integer, boolean
    }

    public struct Column: Sendable {
        public let name: String
        public let kind: Kind
        public let defaultValue: SyncValue
    }

    public let name: String
    public let columns: [Column]
    /// The parent table of a part and the column pointing at it; a deleted parent stands for its parts.
    public let parent: (table: String, column: String)?

    init(_ name: String, parent: (table: String, column: String)? = nil, _ columns: [Column]) {
        self.name = name
        self.parent = parent
        self.columns = columns
    }

    public func column(named name: String) -> Column? {
        columns.first { $0.name == name }
    }

    public static let all: [SyncTable] = [
        SyncTable(
            "accounts",
            [
                text("name"), text("kind"), boolean("shared_expenses", false), boolean("closed", false), text("note"),
                integer("position", 0), text("last_reconciled_at"),
            ]),
        SyncTable(
            "payees",
            [
                text("name"), boolean("hidden", false), text("deleted_at"), text("transfer_account_id"),
                text("last_category_id"), text("successor_id"),
            ]),
        SyncTable(
            "payee_rename_conditions",
            [text("payee_id"), integer("position", 0), text("operator"), text("text"), text("deleted_at")]),
        SyncTable(
            "category_groups",
            [
                text("name"), boolean("hidden", false), boolean("internal", false), integer("position", 0),
                text("note"), text("deleted_at"),
            ]),
        SyncTable(
            "categories",
            [
                text("category_group_id"), text("name"), boolean("hidden", false), boolean("internal", false),
                integer("position", 0), text("note"), text("deleted_at"), text("successor_id"),
            ]),
        SyncTable("assignments", [text("category_id"), text("month"), integer("amount"), text("deleted_at")]),
        SyncTable(
            "target_versions",
            [
                text("category_id"), text("from_month"), text("cadence"), integer("amount"), text("due_on"),
                boolean("repeats_yearly", false), boolean("set_aside", true), text("deleted_at"),
            ]),
        SyncTable("target_snoozes", [text("category_id"), text("month"), text("deleted_at")]),
        SyncTable(
            "scheduled_transactions",
            [
                text("account_id"), text("next_date"), text("frequency"), integer("first_day"), integer("second_day"),
                integer("amount"), text("memo"), text("cleared", "uncleared"), text("deleted_at"), text("payee_id"),
                text("category_id"),
            ]),
        SyncTable(
            "scheduled_subtransactions", parent: ("scheduled_transactions", "scheduled_transaction_id"),
            [
                text("scheduled_transaction_id"), integer("position", 0), integer("amount"), text("memo"),
                text("deleted_at"), text("payee_id"), text("category_id"),
            ]),
        SyncTable(
            "transactions",
            [
                text("account_id"), text("date"), integer("amount"), text("memo"), text("cleared", "uncleared"),
                boolean("approved", false), text("source", "manual"), text("deleted_at"), text("scheduled_date"),
                text("led_by"), text("payee_id"), text("category_id"), text("transfer_transaction_id"),
                text("transfer_subtransaction_id"), text("matched_transaction_id"), text("scheduled_transaction_id"),
            ]),
        SyncTable(
            "subtransactions", parent: ("transactions", "transaction_id"),
            [
                text("transaction_id"), integer("position", 0), integer("amount"), text("memo"), text("deleted_at"),
                text("category_id"), text("payee_id"), text("transfer_transaction_id"),
            ]),
    ]

    public static func named(_ name: String) -> SyncTable? {
        all.first { $0.name == name }
    }

    private static func text(_ name: String, _ defaultValue: String? = nil) -> Column {
        Column(name: name, kind: .text, defaultValue: .of(defaultValue))
    }

    private static func integer(_ name: String, _ defaultValue: Int? = nil) -> Column {
        Column(name: name, kind: .integer, defaultValue: .of(defaultValue))
    }

    private static func boolean(_ name: String, _ defaultValue: Bool) -> Column {
        Column(name: name, kind: .boolean, defaultValue: .bool(defaultValue))
    }
}
