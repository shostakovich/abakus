defmodule Abakus.Ledger.UuidMigrationTest do
  use ExUnit.Case

  alias Abakus.{Budget, Categories, Ids, Ledger, Repo, TestMigrations}
  alias Abakus.Users.{Scope, User}

  @moduletag :tmp_dir
  @before 20_261_021_220_000
  @switch 20_261_031_100_000
  @now "'2026-10-01T10:00:00.000000Z'"
  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[57][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)
    insert_budget()
    %{repo: repo}
  end

  # Transfer sides point at each other, so the rows go in with foreign keys off.
  defp insert_budget do
    sql!("PRAGMA foreign_keys = OFF")
    sql!("DELETE FROM categories")
    sql!("DELETE FROM category_groups")

    sql!("""
    INSERT INTO users (id, email, passkey_handle, inserted_at, updated_at, budget_owner)
    VALUES (1, 'owner@example.com', x'01', #{@now}, #{@now}, 1)
    """)

    insert!("accounts", ~w(id name kind), [
      [1, "Giro", "checking"],
      [2, "Spar", "savings"],
      [3, "Depot", "tracking"]
    ])

    insert!("category_groups", ~w(id name internal position), [
      [1, "Intern", 1, 0],
      [2, "Alltag", 0, 1]
    ])

    insert!("categories", ~w(id category_group_id name lookup_key internal position), [
      [10, 1, "Zu verteilen", "zu verteilen", 1, 0],
      [11, 2, "Lebensmittel", "lebensmittel", 0, 0],
      [12, 2, "Miete", "miete", 0, 1]
    ])

    insert!("payees", ~w(id name lookup_key transfer_account_id last_category_id), [
      [1, "Transfer : Giro", "transfer : giro", 1, nil],
      [2, "Transfer : Spar", "transfer : spar", 2, nil],
      [3, "Transfer : Depot", "transfer : depot", 3, nil],
      [4, "Rewe", "rewe", nil, 11],
      [5, "Arbeitgeber", "arbeitgeber", nil, 10]
    ])

    insert!(
      "transactions",
      ~w(id account_id date amount payee_id category_id cleared approved source transfer_transaction_id
         transfer_subtransaction_id matched_transaction_id deleted_at),
      [
        [1, 1, "2026-10-01", 300_000, 5, 10, "cleared", 1, "manual", nil, nil, nil, nil],
        [2, 1, "2026-10-05", -4_210, 4, 11, "cleared", 1, "file", nil, nil, nil, nil],
        [3, 1, "2026-10-10", -100_000, nil, nil, "cleared", 1, "manual", nil, nil, nil, nil],
        [4, 2, "2026-10-10", 20_000, 1, nil, "cleared", 1, "manual", nil, 2, nil, nil],
        [5, 1, "2026-11-03", -5_000, 4, 11, "uncleared", 1, "manual", nil, nil, nil, nil],
        [6, 1, "2026-11-04", -999, 4, 11, "uncleared", 1, "manual", nil, nil, nil, "2026-11-04"],
        [7, 1, "2026-11-05", -5_000, 4, nil, "cleared", 0, "bank", nil, nil, 5, nil],
        [8, 1, "2026-11-06", -50_000, 3, 11, "uncleared", 1, "manual", 9, nil, nil, nil],
        [9, 3, "2026-11-06", 50_000, 1, nil, "uncleared", 1, "manual", 8, nil, nil, nil]
      ]
    )

    insert!(
      "subtransactions",
      ~w(id transaction_id position amount category_id payee_id transfer_transaction_id),
      [[1, 3, 0, -80_000, 12, nil, nil], [2, 3, 1, -20_000, nil, 2, 4]]
    )

    insert!("assignments", ~w(category_id month amount), [
      [11, "2026-10-01", 10_000],
      [12, "2026-10-01", 80_000],
      [11, "2026-11-01", 10_000]
    ])

    insert!("target_versions", ~w(category_id from_month cadence amount), [
      [11, "2026-10-01", "monthly", 10_000]
    ])

    insert!("target_snoozes", ~w(category_id month), [[11, "2026-12-01"]])

    insert!("transaction_origins", ~w(id transaction_id account_id source external_id), [
      [40, 7, 1, "bank", "ext-7"],
      [41, 2, 1, "file", "fitid-2"]
    ])

    insert!("bank_balances", ~w(account_id source date amount), [
      [1, "bank", "2026-11-06", 140_790]
    ])

    sql!("""
    INSERT INTO depot_portfolios (id, user_id, reference_account_id, name, inserted_at, updated_at)
    VALUES (1, 1, 3, 'Broker', #{@now}, #{@now})
    """)

    assert sql!("PRAGMA foreign_key_check") == []
    sql!("PRAGMA foreign_keys = ON")
  end

  defp insert!(table, columns, rows) do
    with_user = if table in ~w(subtransactions), do: columns, else: ["user_id" | columns]

    for row <- rows do
      values = if table in ~w(subtransactions), do: row, else: [1 | row]

      sql!(
        ~s|INSERT INTO "#{table}" (#{Enum.join(with_user, ", ")}, inserted_at, updated_at) | <>
          "VALUES (#{Enum.map_join(1..length(values), ", ", &"?#{&1}")}, #{@now}, #{@now})",
        values
      )
    end
  end

  defp sql!(sql, params \\ []), do: Repo.query!(sql, params).rows

  defp scope, do: Scope.for_user(Repo.get!(User, 1))

  defp ids(table), do: sql!(~s|SELECT id FROM "#{table}" ORDER BY id|) |> Enum.map(&hd/1)

  defp named(table, column) do
    sql!(~s|SELECT name, id FROM "#{table}" ORDER BY #{column}|) |> Map.new(&List.to_tuple/1)
  end

  test "keeps every account balance", %{repo: repo} do
    TestMigrations.run!(repo)
    accounts = named("accounts", "name")
    balances = Ledger.balances(scope())

    assert balances[accounts["Giro"]] == %{
             balance: 140_790,
             cleared: 195_790,
             uncleared: -55_000,
             unapproved: 1
           }

    assert balances[accounts["Spar"]] == %{
             balance: 20_000,
             cleared: 20_000,
             uncleared: 0,
             unapproved: 0
           }

    assert balances[accounts["Depot"]].balance == 50_000
    giro = Ledger.get_account!(scope(), accounts["Giro"])
    assert Ledger.latest_bank_balance(scope(), giro).amount == 140_790
  end

  test "keeps every month's figures", %{repo: repo} do
    TestMigrations.run!(repo)
    categories = named("categories", "name")
    months = scope() |> Categories.budget() |> Budget.months(~D[2026-11-15])
    month = &Enum.find(months, fn m -> m.month == &1 end)
    row = &Enum.find(month.(&1).categories, fn c -> c.category_id == categories[&2] end)

    assert %{income: 300_000, ready_to_assign: 210_000} = month.(~D[2026-10-01])

    assert %{assigned: 10_000, activity: -4_210, available: 5_790} =
             row.(~D[2026-10-01], "Lebensmittel")

    assert %{assigned: 80_000, activity: -80_000, available: 0} = row.(~D[2026-10-01], "Miete")

    assert %{ready_to_assign: 200_000} = month.(~D[2026-11-01])

    assert %{assigned: 10_000, activity: -55_000, available: -39_210, needed: 10_000} =
             row.(~D[2026-11-01], "Lebensmittel")

    assert %{snoozed: true} = row.(~D[2026-12-01], "Lebensmittel")
    assert %{ready_to_assign: 160_790} = month.(~D[2026-12-01])
  end

  test "gives every row a UUID in the order of its old id and points every reference at it", %{
    repo: repo
  } do
    TestMigrations.run!(repo)

    for table <-
          ~w(accounts payees transactions subtransactions category_groups categories assignments
                    target_versions target_snoozes),
        id <- ids(table),
        do: assert(id =~ @uuid, "#{table}: #{id}")

    amounts = sql!("SELECT amount FROM transactions ORDER BY id") |> Enum.map(&hd/1)
    assert amounts == [300_000, -4_210, -100_000, 20_000, -5_000, -999, -5_000, -50_000, 50_000]

    [_income, _rewe, split, saved, booked, _deleted, proposal, to_depot, in_depot] =
      ids("transactions")

    [_rent, part] = ids("subtransactions")

    assert sql!(
             "SELECT transfer_transaction_id FROM transactions WHERE id IN (?1, ?2) ORDER BY id",
             [
               to_depot,
               in_depot
             ]
           ) == [[in_depot], [to_depot]]

    assert sql!(
             "SELECT transaction_id, transfer_transaction_id FROM subtransactions WHERE id = ?1",
             [part]
           ) ==
             [[split, saved]]

    assert sql!("SELECT transfer_subtransaction_id FROM transactions WHERE id = ?1", [saved]) == [
             [part]
           ]

    assert sql!("SELECT matched_transaction_id FROM transactions WHERE id = ?1", [proposal]) == [
             [booked]
           ]

    accounts = named("accounts", "name")
    payees = named("payees", "name")
    categories = named("categories", "name")

    for {account, id} <- accounts,
        do: assert(payees["Transfer : #{account}"] == Ids.transfer_payee(id))

    assert sql!("SELECT last_category_id FROM payees WHERE id = ?1", [payees["Rewe"]]) == [
             [categories["Lebensmittel"]]
           ]

    assert sql!("SELECT id, category_id, month FROM assignments ORDER BY month, category_id") ==
             Enum.sort_by(
               [
                 [
                   Ids.assignment(categories["Lebensmittel"], ~D[2026-10-01]),
                   categories["Lebensmittel"],
                   "2026-10-01"
                 ],
                 [
                   Ids.assignment(categories["Miete"], ~D[2026-10-01]),
                   categories["Miete"],
                   "2026-10-01"
                 ],
                 [
                   Ids.assignment(categories["Lebensmittel"], ~D[2026-11-01]),
                   categories["Lebensmittel"],
                   "2026-11-01"
                 ]
               ],
               &{Enum.at(&1, 2), Enum.at(&1, 1)}
             )

    assert ids("target_versions") == [
             Ids.target_version(categories["Lebensmittel"], ~D[2026-10-01])
           ]

    assert ids("target_snoozes") == [
             Ids.target_snooze(categories["Lebensmittel"], ~D[2026-12-01])
           ]

    assert sql!("SELECT id, transaction_id, account_id FROM transaction_origins ORDER BY id") == [
             [40, proposal, accounts["Giro"]],
             [41, Enum.at(ids("transactions"), 1), accounts["Giro"]]
           ]

    assert sql!("SELECT reference_account_id FROM depot_portfolios") == [[accounts["Depot"]]]
    assert sql!("SELECT seq FROM sqlite_sequence WHERE name = 'transaction_origins'") == [[41]]
    assert sql!("SELECT 1 FROM sqlite_master WHERE name = 'uuid_ids'") == []
  end

  test "the Ledger works on the migrated rows", %{repo: repo} do
    TestMigrations.run!(repo)
    giro = Ledger.get_account!(scope(), named("accounts", "name")["Giro"])

    assert {:ok, transaction} =
             Ledger.create_transaction(scope(), %{
               account_id: giro.id,
               date: ~D[2026-11-10],
               amount: -1_000,
               payee_name: "Rewe"
             })

    assert transaction.id =~ @uuid
    assert transaction.id > List.last(ids("transactions") -- [transaction.id])
    assert transaction.payee_id == named("payees", "name")["Rewe"]
  end

  test "a reference to a missing row stops the switch and changes nothing", %{repo: repo} do
    sql!("PRAGMA foreign_keys = OFF")
    sql!("UPDATE transactions SET payee_id = 99 WHERE id = 2")

    assert_raise RuntimeError, ~r/transactions.payee_id points at rows that do not exist/, fn ->
      TestMigrations.run!(repo, to: @switch)
    end

    assert ids("transactions") == Enum.to_list(1..9)
    assert sql!("SELECT max(version) FROM schema_migrations") == [[@before]]
  end
end
