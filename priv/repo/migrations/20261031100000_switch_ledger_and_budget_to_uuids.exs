defmodule Abakus.Repo.Migrations.SwitchLedgerAndBudgetToUuids do
  use Ecto.Migration

  # SQLite changes a column's type only by rebuilding its table, with foreign keys off so a drop deletes nothing.
  @disable_ddl_transaction true
  @disable_migration_lock true

  # The UUIDv5 namespace of Abakus.Ids, copied: a migration must not change with the app.
  @namespace "1d70d95f-102c-4115-966f-5db73210e37c"

  @uuid_tables ~w(accounts payees transactions subtransactions category_groups categories assignments
                  target_versions target_snoozes)

  @references [
    {"accounts", id: "accounts"},
    {"payees", id: "payees", transfer_account_id: "accounts", last_category_id: "categories"},
    {"transactions",
     id: "transactions",
     account_id: "accounts",
     payee_id: "payees",
     category_id: "categories",
     transfer_transaction_id: "transactions",
     transfer_subtransaction_id: "subtransactions",
     matched_transaction_id: "transactions"},
    {"subtransactions",
     id: "subtransactions",
     transaction_id: "transactions",
     category_id: "categories",
     payee_id: "payees",
     transfer_transaction_id: "transactions"},
    {"category_groups", id: "category_groups"},
    {"categories", id: "categories", category_group_id: "category_groups"},
    {"assignments", id: "assignments", category_id: "categories"},
    {"target_versions", id: "target_versions", category_id: "categories"},
    {"target_snoozes", id: "target_snoozes", category_id: "categories"},
    {"transaction_origins", transaction_id: "transactions", account_id: "accounts"},
    {"bank_balances", account_id: "accounts"},
    {"bank_linked_accounts", account_id: "accounts"},
    {"kasse_budget_links", account_id: "accounts"},
    {"kasse_budget_category_mappings", budget_category_id: "categories"},
    {"depot_budget_links", category_id: "categories"},
    {"depot_transactions", account_id: "accounts", other_account_id: "accounts"},
    {"depot_portfolios", reference_account_id: "accounts"},
    {"depot_assignments", account_id: "accounts"}
  ]

  def up do
    with_foreign_keys_off(fn ->
      map_ids()
      before = figures(&new_id/2)
      for {table, columns} <- @references, do: rebuild(table, columns)
      check_figures!(before, figures(fn _table, column -> column end))
      query!("DROP TABLE uuid_ids")
    end)
  end

  def down, do: raise(Ecto.MigrationError, "switching the ids to UUIDs is irreversible")

  defp map_ids do
    query!(
      "CREATE TEMP TABLE uuid_ids (tbl TEXT NOT NULL, old INTEGER NOT NULL, new TEXT NOT NULL, PRIMARY KEY (tbl, old)) WITHOUT ROWID"
    )

    for table <- ~w(accounts transactions subtransactions category_groups categories) do
      ids = rows(~s|SELECT id FROM "#{table}" ORDER BY id|)
      put_ids(table, Enum.map(ids, fn [id] -> {id, v7()} end))
    end

    payees =
      rows("""
      SELECT p.id, (SELECT new FROM uuid_ids WHERE tbl = 'accounts' AND old = p.transfer_account_id)
      FROM payees p ORDER BY p.id
      """)

    put_ids("payees", Enum.map(payees, fn [id, account_id] -> {id, payee_id(account_id)} end))

    put_named_ids("assignments", "assignment", "month")
    put_named_ids("target_versions", "target_version", "from_month")
    put_named_ids("target_snoozes", "target_snooze", "month")
  end

  defp put_named_ids(table, kind, month) do
    keys =
      rows("""
      SELECT t.id, (SELECT new FROM uuid_ids WHERE tbl = 'categories' AND old = t.category_id), t."#{month}"
      FROM "#{table}" t ORDER BY t.id
      """)

    put_ids(
      table,
      Enum.map(keys, fn [id, category_id, month] -> {id, v5([kind, category_id, month])} end)
    )
  end

  defp payee_id(nil = _transfer_account_id), do: v7()
  defp payee_id(account_id), do: v5(["transfer_payee", account_id])

  defp put_ids(table, ids) do
    for chunk <- Enum.chunk_every(ids, 300) do
      values = Enum.map_join(1..length(chunk), ", ", &"(?1, ?#{2 * &1}, ?#{2 * &1 + 1})")

      query!("INSERT INTO uuid_ids VALUES #{values}", [
        table | Enum.flat_map(chunk, &Tuple.to_list/1)
      ])
    end
  end

  defp new_id(table, column),
    do: "(SELECT new FROM uuid_ids WHERE tbl = '#{table}' AND old = #{column})"

  defp rebuild(table, columns) do
    [[sql]] = rows("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", [table])

    indexes =
      rows(
        "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL",
        [table]
      )

    sequence = rows("SELECT seq FROM sqlite_sequence WHERE name = ?", [table])
    new = table <> "_new"

    columns
    |> Enum.reduce(
      replace!(sql, ~s|CREATE TABLE "#{table}"|, ~s|CREATE TABLE "#{new}"|),
      &uuid_column/2
    )
    |> query!()

    names = Enum.map(rows("SELECT name FROM pragma_table_info(?)", [new]), &hd/1)
    mapped = Map.new(columns, fn {column, target} -> {Atom.to_string(column), target} end)

    values =
      Enum.map_join(names, ", ", fn name ->
        case mapped do
          %{^name => target} -> new_id(target, ~s|t."#{name}"|)
          _unmapped -> ~s|t."#{name}"|
        end
      end)

    query!(
      ~s|INSERT INTO "#{new}" (#{Enum.map_join(names, ", ", &~s|"#{&1}"|)}) SELECT #{values} FROM "#{table}" t|
    )

    check_mapped!(table, new, Map.keys(mapped))
    query!(~s|DROP TABLE "#{table}"|)
    query!(~s|ALTER TABLE "#{new}" RENAME TO "#{table}"|)
    for [index] <- indexes, do: query!(index)

    # Keeps AUTOINCREMENT of the tables with integer ids from reusing the ids of deleted rows.
    for [seq] <- sequence,
        table not in @uuid_tables,
        do: query!("UPDATE sqlite_sequence SET seq = ? WHERE name = ?", [seq, table])
  end

  defp uuid_column({:id, _table}, sql),
    do:
      replace!(
        sql,
        ~s|"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT|,
        ~s|"id" TEXT NOT NULL PRIMARY KEY|
      )

  defp uuid_column({column, _table}, sql),
    do: replace!(sql, ~s|"#{column}" INTEGER|, ~s|"#{column}" TEXT|)

  # An id without a row to map it to would become NULL.
  defp check_mapped!(table, new, columns) do
    for column <- columns do
      count = ~s|SELECT count("#{column}") FROM|

      if rows(~s|#{count} "#{table}"|) != rows(~s|#{count} "#{new}"|),
        do: raise("#{table}.#{column} points at rows that do not exist")
    end
  end

  # What the budget's figures are made of, by the new ids: balances, activity, assignments and targets.
  defp figures(id) do
    register = "t.deleted_at IS NULL AND t.matched_transaction_id IS NULL"

    %{
      balances:
        rows("""
        SELECT #{id.("accounts", "t.account_id")}, count(*), sum(t.amount),
          sum(CASE WHEN t.cleared != 'uncleared' THEN t.amount ELSE 0 END)
        FROM transactions t WHERE #{register} GROUP BY t.account_id
        """),
      activity:
        rows("""
        SELECT #{id.("categories", "a.category_id")}, a.month, sum(a.amount) FROM (
          SELECT t.category_id, substr(t.date, 1, 7) AS month, t.amount FROM transactions t
          WHERE #{register} AND t.category_id IS NOT NULL
          UNION ALL
          SELECT s.category_id, substr(t.date, 1, 7), s.amount FROM subtransactions s
          JOIN transactions t ON t.id = s.transaction_id WHERE #{register} AND s.category_id IS NOT NULL
        ) a GROUP BY a.category_id, a.month
        """),
      assignments:
        rows("SELECT #{id.("categories", "category_id")}, month, amount FROM assignments"),
      targets:
        rows("""
        SELECT #{id.("categories", "category_id")}, from_month, cadence, amount, due_on, repeats_yearly, set_aside
        FROM target_versions
        """),
      snoozes: rows("SELECT #{id.("categories", "category_id")}, month FROM target_snoozes"),
      categories:
        rows("""
        SELECT #{id.("categories", "id")}, #{id.("category_groups", "category_group_id")}, hidden, internal, position
        FROM categories
        """)
    }
    |> Map.new(fn {name, rows} -> {name, Enum.sort(rows)} end)
  end

  defp check_figures!(before, now) do
    for {name, rows} <- before,
        rows != now[name],
        do: raise("The #{name} differ after switching to UUIDs; nothing was changed")
  end

  # Copies of Abakus.Ids.
  defp v7, do: Ecto.UUID.generate(version: 7, precision: :monotonic)

  defp v5(parts) do
    {:ok, namespace} = Ecto.UUID.dump(@namespace)

    <<a::48, _version::4, b::12, _variant::2, c::62, _rest::32>> =
      :crypto.hash(:sha, namespace <> Enum.join(parts, "/"))

    Ecto.UUID.cast!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end

  defp with_foreign_keys_off(fun) do
    repo().checkout(fn ->
      query!("PRAGMA foreign_keys = OFF")

      try do
        repo().transaction(fn ->
          fun.()

          with [_ | _] = broken <- rows("PRAGMA foreign_key_check"),
               do: raise("Broken foreign keys: #{inspect(broken)}")
        end)
      after
        query!("PRAGMA foreign_keys = ON")
      end
    end)
  end

  defp replace!(string, pattern, replacement) do
    if String.contains?(string, pattern),
      do: String.replace(string, pattern, replacement),
      else: raise("#{inspect(pattern)} not found in #{string}")
  end

  defp rows(sql, params \\ []), do: query!(sql, params).rows

  defp query!(sql, params \\ []), do: repo().query!(sql, params, log: false)
end
