defmodule Abakus.Repo.Migrations.BookDepotCashInTheLedger do
  use Ecto.Migration

  @budget_kinds ~w(checking savings cash)
  @budget_types ~w(buy sell dividend cash_transfer)
  @credits ~w(deposit sell dividend interest tax_refund fee_refund)
  @debits ~w(removal buy interest_charge tax fee)
  @match_days 10

  @labels %{
    "buy" => "Kauf",
    "sell" => "Verkauf",
    "cash_transfer" => "Umbuchung",
    "deposit" => "Einlage",
    "removal" => "Entnahme",
    "dividend" => "Dividende",
    "interest" => "Zinsen",
    "interest_charge" => "Zinsbelastung",
    "tax" => "Steuern",
    "tax_refund" => "Steuerrückerstattung",
    "fee" => "Gebühren",
    "fee_refund" => "Gebührenerstattung"
  }

  def up do
    alter table(:depot_accounts) do
      add :ledger_account_id, references(:accounts, on_delete: :nilify_all)
    end

    create unique_index(:depot_accounts, [:ledger_account_id])

    flush()

    now = DateTime.to_iso8601(DateTime.utc_now())

    for [user_id] <- rows("SELECT DISTINCT user_id FROM depot_accounts ORDER BY user_id") do
      user = %{id: user_id, now: now}
      book(user, open_accounts(user))
    end
  end

  def down,
    do: raise(Ecto.MigrationError, "booking the Depot's cash in the Ledger is irreversible")

  defp open_accounts(user) do
    rows(
      """
      SELECT a.id, a.name, a.budget_account_id, a.retired OR coalesce(p.retired, 0)
      FROM depot_accounts a LEFT JOIN depot_portfolios p ON p.id = a.cash_of_portfolio_id
      WHERE a.user_id = ?1 ORDER BY a.id
      """,
      [user.id]
    )
    |> Map.new(fn [id, name, budget_account_id, closed] ->
      ledger_account_id = budget_account_id || open_tracking_account(user, name, closed)

      query!("UPDATE depot_accounts SET ledger_account_id = ?2 WHERE id = ?1", [
        id,
        ledger_account_id
      ])

      {id, ledger_account(ledger_account_id)}
    end)
  end

  defp open_tracking_account(user, name, closed) do
    [[id]] =
      rows(
        """
        INSERT INTO accounts (user_id, name, kind, closed, position, inserted_at, updated_at)
        VALUES (?1, ?2, 'tracking', ?3, (SELECT coalesce(max(position) + 1, 0) FROM accounts WHERE user_id = ?1), ?4, ?4)
        RETURNING id
        """,
        [user.id, name, closed, user.now]
      )

    payee = "Transfer : " <> name

    query!(
      """
      INSERT INTO payees (user_id, name, lookup_key, transfer_account_id, inserted_at, updated_at)
      VALUES (?1, ?2, ?3, ?4, ?5, ?5)
      """,
      [user.id, payee, lookup_key(payee), id, user.now]
    )

    id
  end

  defp ledger_account(id) do
    [[name, kind, transfer_payee_id]] =
      rows(
        """
        SELECT a.name, a.kind, p.id FROM accounts a JOIN payees p ON p.transfer_account_id = a.id WHERE a.id = ?1
        """,
        [id]
      )

    %{id: id, name: name, budget?: kind in @budget_kinds, transfer_payee_id: transfer_payee_id}
  end

  defp book(user, accounts) do
    context = context(user, accounts)
    wanted = wanted_by_depot_transaction(context)
    led = led(user)

    for {depot_id, unwanted} <- led,
        not Map.has_key?(wanted, depot_id),
        do: delete(context, unwanted)

    missing =
      for {depot_id, wanted} <- Enum.sort(wanted), reduce: [] do
        missing ->
          case led[depot_id] do
            nil ->
              [{depot_id, wanted} | missing]

            led ->
              take_over(context, led, wanted)
              missing
          end
      end

    {budget, tracking} = Enum.split_with(missing, fn {_id, wanted} -> wanted.account.budget? end)
    {pairs, unpaired} = pair(budget, candidates(budget))

    for {{depot_id, wanted}, candidate} <- pairs,
        do: take_over_bank_line(context, candidate, depot_id, wanted)

    for {depot_id, wanted} <- unpaired ++ tracking, do: insert(context, depot_id, wanted)
  end

  defp context(user, accounts) do
    link =
      case rows("SELECT category_id, start_date FROM depot_budget_links WHERE user_id = ?1", [
             user.id
           ]) do
        [[category_id, start_date]] ->
          %{category_id: category_id, start: Date.from_iso8601!(start_date)}

        [] ->
          nil
      end

    %{
      user: user,
      accounts: accounts,
      link: link,
      ready_to_assign_id: link && ready_to_assign_id(user),
      portfolios:
        Map.new(
          rows("SELECT id, name FROM depot_portfolios WHERE user_id = ?1", [user.id]),
          &List.to_tuple/1
        )
    }
  end

  defp ready_to_assign_id(user) do
    case rows("SELECT id FROM categories WHERE user_id = ?1 AND internal", [user.id]) do
      [[id]] -> id
      [] -> nil
    end
  end

  defp wanted_by_depot_transaction(context) do
    rows(
      """
      SELECT t.id, t.type, t.date_time, t.account_id, t.other_account_id, t.portfolio_id, t.amount, s.name
      FROM depot_transactions t LEFT JOIN depot_securities s ON s.id = t.security_id
      WHERE t.user_id = ?1 AND t.account_id IS NOT NULL
      """,
      [context.user.id]
    )
    |> Enum.flat_map(fn [
                          id,
                          type,
                          date_time,
                          account_id,
                          other_account_id,
                          portfolio_id,
                          amount,
                          security
                        ] ->
      transaction = %{
        type: type,
        date: date_time |> String.slice(0, 10) |> Date.from_iso8601!(),
        account_id: account_id,
        other_account_id: other_account_id,
        portfolio_id: portfolio_id,
        amount: amount,
        security: security
      }

      case wanted(transaction, context) do
        nil -> []
        wanted -> [{id, wanted}]
      end
    end)
    |> Map.new()
  end

  defp wanted(t, context) do
    sides =
      for {account_id, amount} <- cash_moved(t),
          amount != 0,
          account = context.accounts[account_id],
          written?(context, t, account),
          do: {account_id, account, amount}

    with %{} = wanted <- sides(t, sides, context),
         do: Map.merge(wanted, %{date: t.date, memo: memo(t)})
  end

  defp cash_moved(%{type: "cash_transfer"} = t),
    do: [{t.account_id, -t.amount}, {t.other_account_id, t.amount}]

  defp cash_moved(%{type: type} = t) when type in @credits, do: [{t.account_id, t.amount}]
  defp cash_moved(%{type: type} = t) when type in @debits, do: [{t.account_id, -t.amount}]
  defp cash_moved(_t), do: []

  defp written?(_context, _t, %{budget?: false}), do: true

  defp written?(%{link: %{start: start}}, t, _account),
    do: t.type in @budget_types and not Date.before?(t.date, start)

  defp written?(_context, _t, _account), do: false

  defp sides(_t, [], _context), do: nil

  defp sides(t, [{account_id, account, amount}], context),
    do: side(context, account, amount, nil, payee(t, account_id, context))

  defp sides(_t, [{_from_id, from, from_amount}, {_to_id, to, to_amount}], context) do
    if to.budget? and not from.budget?,
      do: side(context, to, to_amount, from, {:transfer, from}),
      else: side(context, from, from_amount, to, {:transfer, to})
  end

  defp side(context, account, amount, other, payee) do
    %{
      account: account,
      amount: amount,
      other: other,
      payee: payee,
      category_id: category_id(context, account, amount, other),
      cleared: if(account.budget?, do: "uncleared", else: "cleared"),
      approved: if(account.budget?, do: 0, else: 1)
    }
  end

  defp category_id(context, account, amount, other) do
    cond do
      not account.budget? or (other && other.budget?) -> nil
      amount < 0 -> context.link.category_id
      true -> context.ready_to_assign_id
    end
  end

  defp payee(%{type: type, portfolio_id: id}, _account_id, context) when type in ~w(buy sell),
    do: {:name, context.portfolios[id]}

  defp payee(%{type: "cash_transfer"} = t, account_id, context) do
    other_id = if account_id == t.account_id, do: t.other_account_id, else: t.account_id
    {:name, context.accounts[other_id] && context.accounts[other_id].name}
  end

  defp payee(%{security: name}, _account_id, _context) when is_binary(name), do: {:name, name}
  defp payee(%{portfolio_id: id}, _account_id, context), do: {:name, context.portfolios[id]}

  defp memo(%{type: type, security: name}) when is_binary(name), do: "#{@labels[type]} #{name}"
  defp memo(%{type: type}), do: @labels[type]

  defp led(user) do
    rows(
      """
      SELECT depot_transaction_id, id, account_id, transfer_transaction_id, memo
      FROM transactions WHERE user_id = ?1 AND depot_transaction_id IS NOT NULL AND deleted_at IS NULL
      """,
      [user.id]
    )
    |> Map.new(fn [depot_id, id, account_id, counterpart_id, memo] ->
      {depot_id, %{id: id, account_id: account_id, counterpart_id: counterpart_id, memo: memo}}
    end)
  end

  defp delete(context, led),
    do: soft_delete(context, Enum.reject([led.id, led.counterpart_id], &is_nil/1))

  # A linked transaction transferred to a portfolio's account keeps its id, so its bank line stays matched.
  defp take_over(context, led, wanted) do
    counterpart_id =
      case {wanted.other, led.counterpart_id} do
        {nil, nil} ->
          nil

        {nil, old} ->
          release(context, old)
          nil

        {_other, nil} ->
          nil

        {other, old} ->
          move_counterpart(context, old, other, wanted, led.memo)
          old
      end

    category =
      if led.account_id == wanted.account.id, do: "category_id", else: "?6"

    query!(
      """
      UPDATE transactions
      SET account_id = ?2, amount = ?3, date = ?4, payee_id = ?5, category_id = #{category},
        transfer_transaction_id = ?7, updated_at = ?8
      WHERE id = ?1
      """,
      [
        led.id,
        wanted.account.id,
        wanted.amount,
        Date.to_iso8601(wanted.date),
        payee_id(context, wanted.payee),
        wanted.category_id,
        counterpart_id,
        context.user.now
      ]
    )

    if wanted.other && is_nil(counterpart_id),
      do: insert_counterpart(context, led.id, wanted, led.memo)
  end

  defp move_counterpart(context, id, other, wanted, memo) do
    {cleared, approved} = if other.budget?, do: {"cleared", "approved"}, else: {"'cleared'", "1"}

    query!(
      """
      UPDATE transactions
      SET account_id = ?2, payee_id = ?3, amount = ?4, date = ?5, memo = ?6, category_id = NULL,
        cleared = #{cleared}, approved = #{approved}, updated_at = ?7
      WHERE id = ?1
      """,
      [
        id,
        other.id,
        wanted.account.transfer_payee_id,
        -wanted.amount,
        Date.to_iso8601(wanted.date),
        memo,
        context.user.now
      ]
    )
  end

  defp candidates(missing) do
    for account_id <-
          missing |> Enum.map(fn {_id, wanted} -> wanted.account.id end) |> Enum.uniq(),
        [id, date, amount, category_id, memo] <-
          rows(
            """
            SELECT t.id, t.date, t.amount, t.category_id, t.memo FROM transactions t
            WHERE t.account_id = ?1 AND t.deleted_at IS NULL AND t.matched_transaction_id IS NULL
              AND t.transfer_transaction_id IS NULL AND t.transfer_subtransaction_id IS NULL
              AND t.kasse_expense_id IS NULL AND t.depot_transaction_id IS NULL
              AND NOT EXISTS (SELECT 1 FROM subtransactions s WHERE s.transaction_id = t.id)
            """,
            [account_id]
          ),
        do: %{
          id: id,
          account_id: account_id,
          date: Date.from_iso8601!(date),
          amount: amount,
          category_id: category_id,
          memo: memo
        }
  end

  # Depot transactions since the link's start date the link did not write yet are in the bank import already.
  defp pair(missing, candidates) do
    ordered =
      for {depot_id, wanted} = item <- missing,
          candidate <- candidates,
          candidate.account_id == wanted.account.id and candidate.amount == wanted.amount,
          distance = abs(Date.diff(candidate.date, wanted.date)),
          distance <= @match_days do
        {{distance, Date.to_gregorian_days(candidate.date), candidate.id, depot_id}, item,
         candidate}
      end

    {pairs, _taken} =
      ordered
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({[], MapSet.new()}, fn {_order, {depot_id, _wanted} = item, candidate},
                                            {pairs, taken} ->
        if {:depot, depot_id} in taken or {:candidate, candidate.id} in taken,
          do: {pairs, taken},
          else:
            {[{item, candidate} | pairs],
             taken |> MapSet.put({:depot, depot_id}) |> MapSet.put({:candidate, candidate.id})}
      end)

    paired = MapSet.new(pairs, fn {{depot_id, _wanted}, _candidate} -> depot_id end)
    {pairs, Enum.reject(missing, fn {depot_id, _wanted} -> depot_id in paired end)}
  end

  defp take_over_bank_line(context, candidate, depot_id, wanted) do
    category_id = if wanted.category_id, do: candidate.category_id || wanted.category_id

    query!(
      """
      UPDATE transactions SET depot_transaction_id = ?2, date = ?3, payee_id = ?4, category_id = ?5, updated_at = ?6
      WHERE id = ?1
      """,
      [
        candidate.id,
        depot_id,
        Date.to_iso8601(wanted.date),
        payee_id(context, wanted.payee),
        category_id,
        context.user.now
      ]
    )

    if wanted.other, do: insert_counterpart(context, candidate.id, wanted, candidate.memo)
  end

  defp insert(context, depot_id, wanted) do
    [[id]] =
      rows(
        """
        INSERT INTO transactions (user_id, account_id, date, amount, payee_id, category_id, memo, cleared, approved,
          source, depot_transaction_id, inserted_at, updated_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 'depot', ?10, ?11, ?11)
        RETURNING id
        """,
        [
          context.user.id,
          wanted.account.id,
          Date.to_iso8601(wanted.date),
          wanted.amount,
          payee_id(context, wanted.payee),
          wanted.category_id,
          wanted.memo,
          wanted.cleared,
          wanted.approved,
          depot_id,
          context.user.now
        ]
      )

    if wanted.other, do: insert_counterpart(context, id, wanted, wanted.memo)
  end

  defp insert_counterpart(context, side_id, wanted, memo) do
    other = wanted.other

    {cleared, approved} =
      if other.budget?, do: {"uncleared", wanted.approved}, else: {"cleared", 1}

    [[id]] =
      rows(
        """
        INSERT INTO transactions (user_id, account_id, date, amount, payee_id, memo, cleared, approved, source,
          transfer_transaction_id, inserted_at, updated_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 'depot', ?9, ?10, ?10)
        RETURNING id
        """,
        [
          context.user.id,
          other.id,
          Date.to_iso8601(wanted.date),
          -wanted.amount,
          wanted.account.transfer_payee_id,
          memo,
          cleared,
          approved,
          side_id,
          context.user.now
        ]
      )

    query!("UPDATE transactions SET transfer_transaction_id = ?2 WHERE id = ?1", [side_id, id])
  end

  defp release(context, id) do
    soft_delete(context, [id])

    query!(
      "UPDATE transactions SET transfer_transaction_id = NULL, updated_at = ?2 WHERE id = ?1",
      [
        id,
        context.user.now
      ]
    )
  end

  defp soft_delete(context, ids) do
    marks = Enum.map_join(ids, ", ", fn _id -> "?" end)

    query!(
      "UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE deleted_at IS NULL AND id IN (#{marks})",
      [context.user.now, context.user.now | ids]
    )

    query!(
      "UPDATE transactions SET matched_transaction_id = NULL, updated_at = ? WHERE matched_transaction_id IN (#{marks})",
      [context.user.now | ids]
    )
  end

  defp payee_id(_context, {:transfer, account}), do: account.transfer_payee_id
  defp payee_id(_context, {:name, nil}), do: nil

  defp payee_id(context, {:name, name}) do
    key = lookup_key(name)

    case rows(
           "SELECT id FROM payees WHERE user_id = ?1 AND lookup_key = ?2 AND transfer_account_id IS NULL",
           [context.user.id, key]
         ) do
      [[id]] ->
        id

      [] ->
        [[id]] =
          rows(
            """
            INSERT INTO payees (user_id, name, lookup_key, inserted_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)
            RETURNING id
            """,
            [context.user.id, name, key, context.user.now]
          )

        id
    end
  end

  # Copies of Abakus.Names: a migration must not change with the app.
  defp lookup_key(name) do
    name = :unicode.characters_to_nfc_binary(name)

    with "" <- normalize(Regex.replace(emoji(), name, " ")),
         "" <- normalize(Regex.replace(~r/[\x{FE0E}\x{FE0F}\x{1F3FB}-\x{1F3FF}]/u, name, "")) do
      normalize(name)
    end
  end

  defp normalize(name) do
    ~r/\s+/u
    |> Regex.replace(name, " ")
    |> String.trim()
    |> String.downcase()
    |> String.replace("ß", "ss")
  end

  defp emoji do
    ~r/
      [0-9#*]\x{FE0F}?\x{20E3}
      | [\p{So}\p{Extended_Pictographic}\p{Emoji_Modifier}\p{Regional_Indicator}]
      | [\x{200D}\x{FE0E}\x{FE0F}\x{20E3}\x{E0020}-\x{E007F}]
    /ux
  end

  defp rows(sql, params \\ []), do: query!(sql, params).rows

  defp query!(sql, params), do: repo().query!(sql, params, log: false)
end
