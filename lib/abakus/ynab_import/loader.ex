defmodule Abakus.YnabImport.Loader do
  @moduledoc """
  Replaces the budget with a YNAB plan, inside the caller's database transaction: `wipe/0` deletes it, `load/1`
  writes the plan through the contexts, so their rules hold as for any other entry. Transactions go in by date
  through the Ledger, which creates the counterparts of transfers; each counterpart then takes its own cleared
  state, approval and flag from YNAB, and every side gets its YNAB id as an origin.
  """

  import Ecto.Query

  alias Abakus.{Categories, Ledger, Names, Repo}
  alias Abakus.Categories.{Assignment, Category, CategoryGroup, TargetSnooze, TargetVersion}
  alias Abakus.Ledger.{Account, Payee, Subtransaction, Transaction, TransactionOrigin}
  alias Abakus.YnabImport.{Plan, Targets}

  @kinds %{"checking" => :checking, "savings" => :savings, "cash" => :cash}

  defmodule WriteError do
    @moduledoc "A context refused part of the plan; raised to roll the import's transaction back."
    defexception [:message]
  end

  @doc "Deletes the whole budget but the internal Ready to Assign; users stay."
  def wipe do
    Repo.update_all(Transaction,
      set: [
        transfer_transaction_id: nil,
        transfer_subtransaction_id: nil,
        matched_transaction_id: nil
      ]
    )

    Repo.update_all(Subtransaction, set: [transfer_transaction_id: nil])

    for schema <-
          [TransactionOrigin, Subtransaction, Transaction, Payee, Account] ++
            [Assignment, TargetSnooze, TargetVersion],
        do: Repo.delete_all(schema)

    Repo.delete_all(from c in Category, where: not c.internal)
    Repo.delete_all(from g in CategoryGroup, where: not g.internal)
    :ok
  end

  @doc """
  Writes the plan into an empty budget. Returns the Abakus ids by YNAB id (`accounts`, and `categories`, where
  Uncategorized is nil), the `counts` and the `merged_payees` as `{name, other_names}`.
  """
  def load(plan) do
    accounts = load_accounts(plan)
    {payees, merged} = load_payees(plan, accounts)
    categories = load_categories(plan)
    regular = Map.new(Plan.regular_categories(plan), &{&1["id"], categories[&1["id"]]})
    load_assignments(plan, regular)
    load_targets(plan, regular)
    load_transactions(plan, %{accounts: accounts, payees: payees, categories: categories})

    %{
      accounts: Map.new(accounts, fn {id, account} -> {id, account.id} end),
      categories: categories,
      merged_payees: merged,
      counts: %{
        accounts: map_size(accounts),
        categories: map_size(regular),
        payees: Repo.aggregate(from(p in Payee, where: is_nil(p.transfer_account_id)), :count),
        transactions: length(Plan.transactions(plan))
      }
    }
  end

  defp load_accounts(plan) do
    plan
    |> Plan.accounts()
    |> Enum.with_index()
    |> Map.new(fn {account, position} ->
      attrs = %{
        name: account["name"],
        kind: kind(account),
        closed: account["closed"],
        note: account["note"],
        position: position,
        last_reconciled_at: timestamp(account["last_reconciled_at"])
      }

      {account["id"], ok!(Ledger.create_account(attrs), "account #{account["name"]}")}
    end)
  end

  defp kind(%{"on_budget" => true, "type" => type}), do: Map.fetch!(@kinds, type)
  defp kind(_off_budget), do: :tracking

  defp timestamp(nil), do: nil

  # YNAB writes some timestamps without an offset; they are UTC.
  defp timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, :missing_offset} ->
        value |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
    end
  end

  # Payees with the same lookup key become one, under the first one's name.
  defp load_payees(plan, accounts) do
    {transfer, regular} = Enum.split_with(Plan.payees(plan), & &1["transfer_account_id"])

    transfer_ids =
      for payee <- transfer, account = accounts[payee["transfer_account_id"]], into: %{} do
        {payee["id"], account.transfer_payee.id}
      end

    regular
    |> group_in_order(&Names.lookup_key(&1["name"]))
    |> Enum.reduce({transfer_ids, []}, fn [first | others] = same, {ids, merged} ->
      payee = ok!(Ledger.create_payee(%{name: first["name"]}), "payee #{first["name"]}")
      ids = Enum.reduce(same, ids, &Map.put(&2, &1["id"], payee.id))
      names = others |> Enum.map(& &1["name"]) |> Enum.uniq()
      {ids, if(names == [], do: merged, else: merged ++ [{first["name"], names}])}
    end)
  end

  defp group_in_order(records, key) do
    groups = Enum.group_by(records, key)
    records |> Enum.map(key) |> Enum.uniq() |> Enum.map(&Map.fetch!(groups, &1))
  end

  # Groups only where categories land: YNAB marks every group internal and lists its own empty ones. A hidden
  # category sits in YNAB's hidden group but keeps its original group.
  defp load_categories(plan) do
    by_group =
      plan
      |> Plan.regular_categories()
      |> Enum.group_by(&(&1["original_category_group_id"] || &1["category_group_id"]))

    plan
    |> Plan.category_groups()
    |> Enum.filter(&Map.has_key?(by_group, &1["id"]))
    |> Enum.with_index()
    |> Enum.reduce(special_categories(plan), fn {group, position}, ids ->
      attrs = %{name: group["name"], hidden: group["hidden"], position: position}
      saved = ok!(Categories.create_category_group(attrs), "group #{group["name"]}")

      by_group
      |> Map.fetch!(group["id"])
      |> Enum.with_index()
      |> Enum.reduce(ids, fn {category, position}, ids ->
        Map.put(ids, category["id"], create_category(category, saved, position).id)
      end)
    end)
  end

  defp special_categories(plan) do
    ready_to_assign = Categories.ready_to_assign!().id

    for category <- Plan.categories(plan),
        role = Plan.role(category),
        role in [:ready_to_assign, :uncategorised],
        into: %{},
        do: {category["id"], if(role == :ready_to_assign, do: ready_to_assign)}
  end

  defp create_category(category, group, position) do
    %{
      name: category["name"],
      hidden: category["hidden"],
      note: category["note"],
      position: position,
      category_group_id: group.id
    }
    |> Categories.create_category()
    |> ok!("category #{category["name"]}")
  end

  defp load_assignments(plan, regular) do
    for {month, %{"budgeted" => budgeted} = category} <- Plan.regular_category_months(plan),
        budgeted != 0 do
      %Category{id: regular[category["id"]]}
      |> Categories.assign(month, Plan.cents(budgeted))
      |> ok!("assignment")
    end
  end

  defp load_targets(plan, regular) do
    for {category_id, versions} <- Targets.versions(plan), version <- versions do
      ok!(Categories.set_target(%Category{id: regular[category_id]}, version), "target")
    end

    for {category_id, month} <- Targets.snoozes(plan) do
      ok!(Categories.snooze_target(%Category{id: regular[category_id]}, month), "snooze")
    end
  end

  # A split's transfer part has no id of its counterpart, so counterparts of parts wait until their split is in
  # and are paired with its parts by account, date and amount.
  defp load_transactions(plan, ids) do
    {part_counterparts, transactions} =
      Enum.split_with(Plan.transactions(plan), &Plan.part_counterpart?/1)

    context =
      Map.merge(ids, %{
        by_id: Map.new(Plan.transactions(plan), &{&1["id"], &1}),
        parts: Plan.subtransactions(plan),
        waiting: part_counterparts,
        counterparts: %{}
      })

    _booked = Enum.reduce(transactions ++ part_counterparts, context, &book/2)
    :ok
  end

  defp book(transaction, context) do
    case Map.fetch(context.counterparts, transaction["id"]) do
      {:ok, counterpart_id} ->
        take_own_fields(counterpart_id, transaction)
        context

      :error ->
        create(transaction, context)
    end
  end

  defp create(transaction, context) do
    account = transaction["account_id"]

    {parts, context} =
      pair_parts(transaction, Map.get(context.parts, transaction["id"], []), context)

    counterpart = Map.get(context.by_id, transaction["transfer_transaction_id"])

    attrs =
      transaction
      |> side_attrs(account, counterpart, context)
      |> Map.merge(%{
        account_id: context.accounts[account].id,
        date: transaction["date"],
        cleared: transaction["cleared"],
        approved: transaction["approved"],
        flag: transaction["flag_color"],
        source: :ynab,
        subtransactions:
          Enum.map(parts, fn {part, other} -> side_attrs(part, account, other, context) end)
      })
      |> without_split_category()

    created = ok!(Ledger.create_transaction(attrs), "transaction #{transaction["id"]}")
    ok!(Ledger.add_origin(created, :ynab, transaction["id"]), "origin")

    pairs =
      [{counterpart, created.transfer_transaction_id}] ++
        Enum.zip_with(parts, created.subtransactions, fn {_part, other}, saved ->
          {other, saved.transfer_transaction_id}
        end)

    %{context | counterparts: Enum.reduce(pairs, context.counterparts, &put_counterpart/2)}
  end

  # A split's own category is YNAB's internal "Split".
  defp without_split_category(%{subtransactions: []} = attrs), do: attrs

  defp without_split_category(attrs),
    do: %{attrs | category_id: nil, counterpart_category_id: nil}

  defp put_counterpart({%{"id" => ynab_id}, abakus_id}, counterparts) when is_integer(abakus_id),
    do: Map.put(counterparts, ynab_id, abakus_id)

  defp put_counterpart(_pair, counterparts), do: counterparts

  defp pair_parts(split, parts, context) do
    Enum.map_reduce(parts, context, fn part, context ->
      case Enum.find(context.waiting, &counterpart_of_part?(&1, part, split)) do
        nil -> {{part, nil}, context}
        other -> {{part, other}, %{context | waiting: List.delete(context.waiting, other)}}
      end
    end)
  end

  defp counterpart_of_part?(candidate, part, split) do
    candidate["account_id"] == part["transfer_account_id"] and
      candidate["transfer_account_id"] == split["account_id"] and
      candidate["date"] == split["date"] and candidate["amount"] == -part["amount"]
  end

  # A transaction or a split's part in `account`; for a transfer from a tracking account, the YNAB counterpart
  # gives the budget side's category.
  defp side_attrs(side, account, counterpart, context) do
    %{
      amount: Plan.cents(side["amount"]),
      payee_id: context.payees[side["payee_id"]],
      category_id: context.categories[side["category_id"]],
      memo: side["memo"],
      counterpart_category_id: counterpart_category(account, side, counterpart, context)
    }
  end

  defp counterpart_category(account, side, %{} = counterpart, context) do
    other = context.accounts[side["transfer_account_id"]]

    if (other && Account.budget_account?(other)) and
         not Account.budget_account?(context.accounts[account]),
       do: context.categories[counterpart["category_id"]]
  end

  defp counterpart_category(_account, _side, nil, _context), do: nil

  defp take_own_fields(counterpart_id, transaction) do
    attrs = %{
      cleared: transaction["cleared"],
      approved: transaction["approved"],
      flag: transaction["flag_color"]
    }

    counterpart =
      ok!(Ledger.update_transaction(%Transaction{id: counterpart_id}, attrs), "counterpart")

    ok!(Ledger.add_origin(counterpart, :ynab, transaction["id"]), "origin")
  end

  defp ok!({:ok, value}, _what), do: value

  defp ok!({:error, %Ecto.Changeset{} = changeset}, what) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    raise WriteError, "#{what}: #{inspect(errors)}"
  end

  defp ok!({:error, error}, what), do: raise(WriteError, "#{what}: #{inspect(error)}")
end
