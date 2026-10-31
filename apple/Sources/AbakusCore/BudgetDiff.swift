import Foundation

struct BudgetChange: Hashable, Sendable {
    var table: String
    var rowId: String
    var column: String
    var value: SyncValue
}

struct RowKey: Hashable, Sendable {
    var table: String
    var id: String
}

enum BudgetDiff {
    /// The rows `new` adds; the store may hold them as tombstones to compare against.
    static func addedRows(from old: SyncRows, to new: SyncRows) -> [RowKey] {
        new.flatMap { table, rows in
            rows.keys.filter { old[table]?[$0] == nil }.map { RowKey(table: table, id: $0) }
        }
    }

    /// A removed row becomes a tombstone, with its successor where it has one; a part goes with its deleted parent.
    static func changes(
        from old: SyncRows, to new: SyncRows, stored: [RowKey: SyncRow], successors: [String: String],
        deletedAt: SyncValue
    ) -> [BudgetChange] {
        SyncTable.all.flatMap { table in
            let before = old[table.name] ?? [:]
            let after = new[table.name] ?? [:]
            let changed = after.keys.sorted().flatMap { id in
                fields(of: table, id: id, from: before[id] ?? stored[RowKey(table: table.name, id: id)], to: after[id]!)
            }
            let removed = before.keys.filter { after[$0] == nil }.sorted().flatMap { id in
                partOfRemovedParent(before[id]!, in: table, old: old, new: new)
                    ? [] : tombstone(of: table, id: id, successor: successors[id], deletedAt: deletedAt)
            }
            return changed + removed
        }
    }

    private static func fields(of table: SyncTable, id: String, from before: SyncRow?, to after: SyncRow)
        -> [BudgetChange]
    {
        table.columns.compactMap { column in
            let value = after[column.name] ?? .null
            let changed = before.map { ($0[column.name] ?? .null) != value } ?? !value.isNull
            return changed ? BudgetChange(table: table.name, rowId: id, column: column.name, value: value) : nil
        }
    }

    private static func tombstone(of table: SyncTable, id: String, successor: String?, deletedAt: SyncValue)
        -> [BudgetChange]
    {
        guard table.column(named: "deleted_at") != nil else { return [] }
        var changes = [BudgetChange(table: table.name, rowId: id, column: "deleted_at", value: deletedAt)]
        if let successor, table.column(named: "successor_id") != nil {
            changes.append(BudgetChange(table: table.name, rowId: id, column: "successor_id", value: .text(successor)))
        }
        return changes
    }

    private static func partOfRemovedParent(_ row: SyncRow, in table: SyncTable, old: SyncRows, new: SyncRows)
        -> Bool
    {
        guard let parent = table.parent, let parentId = row.text(parent.column) else { return false }
        return old[parent.table]?[parentId] != nil && new[parent.table]?[parentId] == nil
    }
}
