defmodule Abakus.Repo.Migrations.RebookKasseLinkedTransactions do
  use Ecto.Migration

  @paid_minus_share """
  (CASE WHEN e.paid_by_id = ?1 THEN e.amount_cents ELSE 0 END) -
    coalesce((SELECT s.amount_cents FROM kasse_expense_shares s WHERE s.expense_id = e.id AND s.participant_id = ?1), 0)
  """

  @minus_share "-coalesce((SELECT s.amount_cents FROM kasse_expense_shares s WHERE s.expense_id = e.id AND s.participant_id = ?1), 0)"

  def up, do: rebook(@paid_minus_share)

  def down, do: rebook(@minus_share)

  defp rebook(amount) do
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

      rewrite_linked(link, amount)
      book_missing(link, amount)
    end
  end

  # Transactions deleted beside the Kasse stay deleted; the Kasse books them anew on the expense's next change.
  defp rewrite_linked(link, amount) do
    linked =
      rows(
        """
        SELECT t.id, t.amount, #{amount}
        FROM kasse_linked_transactions l
        JOIN transactions t ON t.id = l.transaction_id
        JOIN kasse_expenses e ON e.id = l.expense_id
        WHERE l.participant_id = ?1 AND e.deleted_at IS NULL AND t.deleted_at IS NULL
        """,
        [link.participant]
      )

    for [id, written, wanted] <- linked, written != wanted do
      if wanted == 0 do
        query!("UPDATE transactions SET deleted_at = ?2, updated_at = ?2 WHERE id = ?1", [
          id,
          link.now
        ])

        query!("DELETE FROM kasse_linked_transactions WHERE transaction_id = ?", [id])
      else
        query!("UPDATE transactions SET amount = ?2, updated_at = ?3 WHERE id = ?1", [
          id,
          wanted,
          link.now
        ])
      end
    end
  end

  defp book_missing(link, amount) do
    missing =
      rows(
        """
        SELECT e.id, e.date, e.title, e.amount_cents, e.original_amount, e.original_currency, p.name,
          m.budget_category_id, #{amount}
        FROM kasse_expenses e
        JOIN kasse_participants p ON p.id = e.paid_by_id
        LEFT JOIN kasse_budget_category_mappings m ON m.category_id = e.category_id
        WHERE e.deleted_at IS NULL AND NOT e.reimbursement AND (?2 IS NULL OR e.date >= ?2)
          AND NOT EXISTS
            (SELECT 1 FROM kasse_linked_transactions l WHERE l.expense_id = e.id AND l.participant_id = ?1)
        ORDER BY e.date, e.id
        """,
        [link.participant, link.start]
      )

    for [id, date, title, cents, original, currency, payer, category_id, wanted] <- missing,
        wanted != 0 do
      memo = memo(cents, original, currency, payer)

      [[transaction_id]] =
        rows(
          """
          INSERT INTO transactions (user_id, account_id, date, amount, payee_id, category_id, memo, cleared,
            approved, source, inserted_at, updated_at)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'cleared', 0, 'kasse', ?8, ?8)
          RETURNING id
          """,
          [
            link.user,
            link.account,
            date,
            wanted,
            payee(link, title, category_id),
            category_id,
            memo,
            link.now
          ]
        )

      query!(
        """
        INSERT INTO kasse_linked_transactions (expense_id, participant_id, transaction_id, written_category_id,
          written_memo, inserted_at, updated_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)
        """,
        [id, link.participant, transaction_id, category_id, memo, link.now]
      )
    end
  end

  defp memo(cents, original, currency, payer) do
    total = "Gesamt " <> plain(cents, "EUR")

    total =
      if eur?(currency), do: total, else: total <> " (#{plain(original, currency)})"

    total <> " · bezahlt von " <> payer
  end

  defp payee(link, name, category_id) do
    key = lookup_key(name)

    id =
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

    if category_id,
      do:
        query!("UPDATE payees SET last_category_id = ?2, updated_at = ?3 WHERE id = ?1", [
          id,
          category_id,
          link.now
        ])

    id
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
