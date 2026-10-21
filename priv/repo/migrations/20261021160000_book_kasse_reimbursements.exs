defmodule Abakus.Repo.Migrations.BookKasseReimbursements do
  use Ecto.Migration

  require Logger

  @change """
  (CASE WHEN e.paid_by_id = ?1 THEN e.amount_cents ELSE 0 END) -
    coalesce((SELECT s.amount_cents FROM kasse_expense_shares s WHERE s.expense_id = e.id AND s.participant_id = ?1), 0)
  """

  def up do
    now = DateTime.to_iso8601(DateTime.utc_now())

    links =
      rows("""
      SELECT l.participant_id, l.start_date, l.account_id, a.user_id
      FROM kasse_budget_links l JOIN accounts a ON a.id = l.account_id
      """)

    for [participant_id, start_date, account_id, user_id] <- links do
      link = %{
        participant: participant_id,
        start: start_date,
        account: account_id,
        user: user_id,
        now: now
      }

      {pairs, unpaired} = pair(reimbursements(link), transfers(link))

      for {reimbursement, transfer} <- pairs do
        query!("UPDATE transactions SET kasse_expense_id = ?2, updated_at = ?3 WHERE id = ?1", [
          transfer.id,
          reimbursement.id,
          now
        ])
      end

      for reimbursement <- unpaired, do: book_open(link, reimbursement)
      report(link, unpaired, unled_transfers(link))
    end
  end

  def down,
    do: raise(Ecto.MigrationError, "booking the Kasse's reimbursements is irreversible")

  defp reimbursements(link) do
    rows(
      """
      SELECT e.id, e.date, e.title, e.amount_cents, e.original_amount, e.original_currency, p.name, #{@change}
      FROM kasse_expenses e JOIN kasse_participants p ON p.id = e.paid_by_id
      WHERE e.deleted_at IS NULL AND e.reimbursement AND (?2 IS NULL OR e.date >= ?2)
        AND NOT EXISTS
          (SELECT 1 FROM transactions t WHERE t.kasse_expense_id = e.id AND t.user_id = ?3 AND t.deleted_at IS NULL)
      ORDER BY e.date, e.id
      """,
      [link.participant, link.start, link.user]
    )
    |> Enum.map(fn [id, date, title, cents, original, currency, payer, change] ->
      %{
        id: id,
        date: Date.from_iso8601!(date),
        title: title,
        memo: memo(cents, original, currency, payer),
        amount: change
      }
    end)
    |> Enum.reject(&(&1.amount == 0))
  end

  # The owner booked reimbursements by hand as transfers with a budget account, which the Kasse leads from now on.
  defp transfers(link) do
    rows(
      """
      SELECT t.id, t.date, t.amount
      FROM transactions t
      JOIN transactions c ON c.id = t.transfer_transaction_id
      JOIN accounts a ON a.id = c.account_id
      WHERE t.account_id = ?1 AND (?2 IS NULL OR t.date >= ?2) AND t.deleted_at IS NULL
        AND t.matched_transaction_id IS NULL AND t.transfer_subtransaction_id IS NULL
        AND t.kasse_expense_id IS NULL AND t.depot_transaction_id IS NULL
        AND c.deleted_at IS NULL AND c.kasse_expense_id IS NULL AND c.depot_transaction_id IS NULL
        AND a.kind IN ('checking', 'savings', 'cash')
        AND NOT EXISTS (SELECT 1 FROM subtransactions s WHERE s.transaction_id = t.id)
      """,
      [link.account, link.start]
    )
    |> Enum.map(fn [id, date, amount] ->
      %{id: id, date: Date.from_iso8601!(date), amount: amount}
    end)
  end

  defp pair(reimbursements, transfers) do
    candidates =
      for r <- reimbursements, t <- transfers, r.amount == t.amount do
        {{abs(Date.diff(r.date, t.date)), Date.to_gregorian_days(t.date), t.id, r.id}, r, t}
      end

    {pairs, _taken} =
      candidates
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({[], MapSet.new()}, fn {_order, r, t}, {pairs, taken} ->
        if {:r, r.id} in taken or {:t, t.id} in taken,
          do: {pairs, taken},
          else: {[{r, t} | pairs], taken |> MapSet.put({:r, r.id}) |> MapSet.put({:t, t.id})}
      end)

    paired = MapSet.new(pairs, fn {r, _t} -> r.id end)
    {pairs, Enum.reject(reimbursements, &(&1.id in paired))}
  end

  defp unled_transfers(link) do
    rows(
      """
      SELECT id, date FROM transactions
      WHERE account_id = ?1 AND (?2 IS NULL OR date >= ?2) AND deleted_at IS NULL AND matched_transaction_id IS NULL
        AND kasse_expense_id IS NULL AND depot_transaction_id IS NULL
        AND (transfer_transaction_id IS NOT NULL OR transfer_subtransaction_id IS NOT NULL)
      ORDER BY date, id
      """,
      [link.account, link.start]
    )
  end

  defp report(_link, [], []), do: :ok

  defp report(link, open, transfers) do
    Logger.warning(
      "Kasse reimbursements in account #{link.account}, to check by hand: " <>
        "booked as open transactions, no transfer of their amount found: " <>
        listed(for r <- open, do: "Kasse expense #{r.id} (#{r.date})") <>
        "; transfers left without a Kasse reimbursement: " <>
        listed(for [id, date] <- transfers, do: "transaction #{id} (#{date})")
    )
  end

  defp listed([]), do: "none"
  defp listed(items), do: Enum.join(items, ", ")

  defp book_open(link, reimbursement) do
    query!(
      """
      INSERT INTO transactions (user_id, account_id, date, amount, payee_id, memo, cleared, approved, source,
        kasse_expense_id, inserted_at, updated_at)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'cleared', 0, 'kasse', ?7, ?8, ?8)
      """,
      [
        link.user,
        link.account,
        Date.to_iso8601(reimbursement.date),
        reimbursement.amount,
        payee(link, reimbursement.title),
        reimbursement.memo,
        reimbursement.id,
        link.now
      ]
    )
  end

  defp memo(cents, original, currency, payer) do
    total = "Gesamt " <> plain(cents, "EUR")

    total =
      if eur?(currency), do: total, else: total <> " (#{plain(original, currency)})"

    total <> " · bezahlt von " <> payer
  end

  defp payee(link, name) do
    key = lookup_key(name)

    case rows(
           "SELECT id FROM payees WHERE user_id = ? AND lookup_key = ? AND transfer_account_id IS NULL",
           [link.user, key]
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
            [link.user, name, key, link.now]
          )

        id
    end
  end

  # Copies of Abakus.Names and Abakus.Money: a migration must not change with the app.
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

  defp plain(minor, currency) do
    code = currency |> String.trim() |> String.upcase()

    places =
      cond do
        code in ~w(JPY KRW ISK HUF CLP VND XAF XOF PYG UGX IDR) -> 0
        code in ~w(KWD BHD OMR JOD TND LYD IQD) -> 3
        true -> 2
      end

    digits = minor |> abs() |> Integer.to_string() |> String.pad_leading(places + 1, "0")
    {int, fraction} = String.split_at(digits, byte_size(digits) - places)
    int = int |> String.reverse() |> String.replace(~r/\d{3}(?=\d)/, "\\0.") |> String.reverse()
    fraction = if places == 0, do: "", else: "," <> fraction
    sign = if minor < 0, do: "−", else: ""
    unit = if eur?(code), do: "€", else: code
    sign <> int <> fraction <> " " <> unit
  end

  defp eur?(currency), do: String.upcase(String.trim(currency)) in ["", "EUR"]

  defp rows(sql, params \\ []), do: query!(sql, params).rows

  defp query!(sql, params), do: repo().query!(sql, params, log: false)
end
