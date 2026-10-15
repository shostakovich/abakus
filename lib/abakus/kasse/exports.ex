defmodule Abakus.Kasse.Exports do
  @moduledoc """
  Downloads of the expenses, oldest first and without deleted ones, for a period (both ends
  inclusive, either open): a CSV for German Excel and a JSON file of everything.

  Each export returns `%{filename, content_type, body}`; options `:now` (UTC) and `:today` (the
  local date of the file name).
  """

  alias Abakus.LocalTime

  alias Abakus.Kasse.{Dates, Expenses, Money}
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Kasse.{OrderedJSON, Participants, Settings, Split}

  @bom "﻿"
  @csv_header ~w(ID Datum Titel Kategorie) ++
                [
                  "Bezahlt von",
                  "Betrag (EUR)",
                  "Originalbetrag",
                  "Währung",
                  "Kurs",
                  "Art",
                  "Aufteilung",
                  "Notiz"
                ]

  @type period :: %{from: Date.t() | nil, to: Date.t() | nil}

  @doc """
  The period of the params `"from"` and `"to"`. Only an empty value means open; anything else
  must be a date.
  """
  @spec period(map()) :: {:ok, period()} | {:error, String.t()}
  def period(params) do
    with {:ok, from} <- date_param(params["from"]),
         {:ok, to} <- date_param(params["to"]) do
      if from && to && Date.before?(to, from),
        do: {:error, "„Bis“ liegt vor „Von“."},
        else: {:ok, %{from: from, to: to}}
    end
  end

  defp date_param(value) when value in [nil, ""], do: {:ok, nil}
  defp date_param(value) when is_binary(value), do: Dates.parse(value)
  defp date_param(_value), do: {:error, "Bitte ein Datum angeben."}

  @doc "Every expense with the shares of the people involved, for German Excel."
  def expenses_csv(period, opts \\ []) do
    expenses = expenses(period)
    people = involved(expenses)

    rows =
      for expense <- expenses do
        [
          Integer.to_string(expense.id),
          Dates.format(expense.date),
          cell(expense.title),
          cell(if(expense.category, do: expense.category.name, else: "")),
          cell(expense.paid_by.name),
          Money.format_minor(expense.amount_cents, 2),
          Money.format_minor(expense.original_amount, Money.decimals(expense.original_currency)),
          expense.original_currency,
          if(Expense.foreign?(expense), do: Money.format_rate(expense.fx_rate), else: ""),
          if(expense.reimbursement, do: Expense.reimbursement_title(), else: "Ausgabe"),
          Split.label(expense.split_mode),
          cell(expense.notes)
        ] ++ Enum.map(people, &share_cell(expense, &1.id))
      end

    body = @bom <> csv([@csv_header ++ Enum.map(people, &"Anteil #{&1.name}") | rows], ";")
    download("ausgaben", period, "csv", "text/csv; charset=utf-8", body, opts)
  end

  defp share_cell(expense, participant_id) do
    if Enum.any?(expense.shares, &(&1.participant_id == participant_id)),
      do: Money.format_minor(Expense.share_of(expense, participant_id), 2),
      else: ""
  end

  defp involved(expenses) do
    ids =
      for expense <- expenses,
          id <- [expense.paid_by_id | Enum.map(expense.shares, & &1.participant_id)],
          into: MapSet.new(),
          do: id

    Enum.filter(Participants.list_participants(:all), &MapSet.member?(ids, &1.id))
  end

  @doc "Everything about the expenses, with all people, as JSON."
  def expenses_json(period, opts \\ []) do
    people = Participants.list_participants(:all)
    names = Map.new(people, &{&1.id, &1.name})

    document =
      [group: Settings.group_name(), exported_at: timestamp(now(opts))] ++
        period_dates(period) ++
        [
          currency: "EUR",
          participants:
            Enum.map(people, &[id: &1.id, name: &1.name, archived: not is_nil(&1.archived_at)]),
          expenses: Enum.map(expenses(period), &json_expense(&1, names))
        ]

    body = OrderedJSON.format!(document)
    download("ausgaben", period, "json", "application/json; charset=utf-8", body, opts)
  end

  defp period_dates(period) do
    for {key, date} <- [from: period.from, to: period.to], date, do: {key, Date.to_iso8601(date)}
  end

  defp json_expense(expense, names) do
    [
      id: expense.id,
      date: Date.to_iso8601(expense.date),
      title: expense.title,
      category_id: expense.category_id,
      category: if(expense.category, do: expense.category.name, else: ""),
      paid_by: expense.paid_by_id,
      paid_by_name: expense.paid_by.name,
      amount_cents: expense.amount_cents,
      is_reimbursement: expense.reimbursement,
      split_mode: Atom.to_string(expense.split_mode),
      original_amount_minor: expense.original_amount,
      original_currency: expense.original_currency,
      fx_rate: expense.fx_rate,
      fx_source: fx_source(expense.fx_source),
      notes: expense.notes,
      recurring_id: expense.recurring_expense_id,
      shares:
        Enum.map(expense.shares, fn share ->
          [
            participant_id: share.participant_id,
            name: Map.get(names, share.participant_id, ""),
            weight: share.weight,
            amount_cents: share.amount_cents
          ]
        end),
      created_at: timestamp(expense.inserted_at),
      updated_at: timestamp(expense.updated_at)
    ]
  end

  # The values of the file format, as people's scripts read them.
  defp fx_source(:ecb), do: "ezb"
  defp fx_source(:manual), do: "manuell"
  defp fx_source(nil), do: ""

  @doc "A cell a spreadsheet does not take for a formula: =, +, -, @, tab or CR first get a quote."
  def cell(<<first, _rest::binary>> = text) when first in ~c"=+-@\t\r", do: "'" <> text
  def cell(text), do: text

  defp csv(rows, separator) do
    Enum.map_join(rows, fn row ->
      Enum.map_join(row, separator, &csv_field(&1, separator)) <> "\n"
    end)
  end

  defp csv_field(field, separator) do
    if String.contains?(field, [separator, "\"", "\n", "\r"]),
      do: "\"" <> String.replace(field, "\"", "\"\"") <> "\"",
      else: field
  end

  defp expenses(period),
    do: Expenses.list_expenses([from: period.from, to: period.to], sort: :date_asc)

  defp download(kind, period, extension, content_type, body, opts) do
    today = Keyword.get_lazy(opts, :today, fn -> LocalTime.date(now(opts)) end)

    %{
      filename: "kasse-#{kind}-#{suffix(period, today)}.#{extension}",
      content_type: content_type,
      body: body
    }
  end

  defp suffix(%{from: nil, to: nil}, today), do: Date.to_iso8601(today)
  defp suffix(%{from: from, to: nil}, _today), do: "ab-" <> Date.to_iso8601(from)
  defp suffix(%{from: nil, to: to}, _today), do: "bis-" <> Date.to_iso8601(to)

  defp suffix(%{from: from, to: to}, _today),
    do: Date.to_iso8601(from) <> "_" <> Date.to_iso8601(to)

  defp now(opts), do: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

  defp timestamp(moment), do: moment |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
