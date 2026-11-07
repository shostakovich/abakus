defmodule Abakus.FileImport.Kontist do
  @moduledoc """
  Reads Kontist's CSV export as one statement in the shape of `Abakus.FileImport.OFX`: the columns `Buchungsdatum`,
  `Betrag`, `Empfänger` and `Verwendungszweck`, separated by semicolons (or commas), quoted or not. Dates are ISO or
  German, amounts go through `Abakus.Money`. Pending bookings (`Buchungsstatus` "Vorgemerkt") are left out, since
  they change until booked. A file that is not UTF-8 is read as Latin-1.

  The export names neither the account nor a transaction id, so the statement's account is `"Kontist"` and a
  transaction's id is its date, amount and payee, numbered from the second on that repeats it (" 2"), like bank
  sync's key (`Abakus.BankSync.entries/1`).
  """

  alias Abakus.FileImport.OFX
  alias Abakus.{Import, Money, Names}

  @account "Kontist"
  @columns %{
    date: "Buchungsdatum",
    amount: "Betrag",
    name: "Empfänger",
    memo: "Verwendungszweck",
    status: "Buchungsstatus"
  }
  @required [:date, :amount, :name, :memo]
  @date_formats [
    ~r/^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})$/,
    ~r/^(?<day>\d{2})\.(?<month>\d{2})\.(?<year>\d{4})$/
  ]

  @doc "Whether the content is a Kontist export: its header names the columns the import needs."
  def export?(content) when is_binary(content) do
    content |> text() |> header_line() |> records() |> List.first([]) |> columns() |> complete?()
  end

  @spec parse(binary()) :: {:ok, [OFX.statement()]} | {:error, String.t()}
  def parse(content) when is_binary(content) do
    {header, rows} =
      case content |> text() |> records() do
        [header | rows] -> {header, rows}
        [] -> {[], []}
      end

    columns = columns(header)

    if complete?(columns) do
      with {:ok, transactions} <- transactions(rows, columns) do
        {:ok,
         [%{bank_id: nil, acct_id: @account, transactions: transactions, ledger_balance: nil}]}
      end
    else
      {:error, "Die Datei ist kein CSV-Export von Kontist."}
    end
  end

  defp text(content) do
    content = String.replace_prefix(content, "\uFEFF", "")
    if String.valid?(content), do: content, else: :unicode.characters_to_binary(content, :latin1)
  end

  defp header_line(text), do: text |> String.split(["\r\n", "\n"], parts: 2) |> hd()

  defp records(text) do
    separator = if text |> header_line() |> String.contains?(";"), do: ";", else: ","
    records(text, separator, [], [], "")
  end

  defp columns(header) do
    keys = Map.new(@columns, fn {key, name} -> {name, key} end)

    header
    |> Enum.with_index()
    |> Enum.flat_map(fn {name, at} ->
      if key = keys[String.trim(name)], do: [{key, at}], else: []
    end)
    |> Map.new()
  end

  defp complete?(columns), do: Enum.all?(@required, &Map.has_key?(columns, &1))

  defp transactions(rows, columns) do
    rows
    |> Enum.reject(&(&1 |> Enum.join() |> String.trim() == ""))
    |> Enum.with_index(1)
    |> Enum.map(fn {row, number} ->
      {Map.new(columns, fn {key, at} -> {key, field(row, at)} end), number}
    end)
    |> Enum.reject(fn {row, _number} -> row[:status] == "Vorgemerkt" end)
    |> Import.collect(fn {row, number} -> transaction(row, number) end)
    |> case do
      {:ok, transactions} -> {:ok, number_repeats(transactions)}
      error -> error
    end
  end

  defp field(row, at), do: row |> Enum.at(at, "") |> String.trim() |> blank_to_nil()

  defp transaction(row, number) do
    with {:ok, date} <- required(date(row.date), "hat kein gültiges Buchungsdatum"),
         {:ok, amount} <- required(amount(row.amount), "hat keinen gültigen Betrag") do
      {:ok, %{date: date, amount: amount, name: row.name, memo: row.memo}}
    else
      {:error, problem} -> {:error, "Buchung #{number} #{problem}."}
    end
  end

  defp required(nil, problem), do: {:error, problem}
  defp required(value, _problem), do: {:ok, value}

  defp date(nil), do: nil

  defp date(value) do
    with %{"year" => year, "month" => month, "day" => day} <-
           Enum.find_value(@date_formats, &Regex.named_captures(&1, value)),
         {:ok, date} <-
           Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
      date
    else
      _invalid -> nil
    end
  end

  defp amount(nil), do: nil

  defp amount(value) do
    case Money.parse(value, 2) do
      {:ok, cents} -> cents
      {:error, _message} -> nil
    end
  end

  defp number_repeats(transactions) do
    {numbered, _counts} =
      Enum.map_reduce(transactions, %{}, fn transaction, counts ->
        key = key(transaction)
        count = Map.get(counts, key, 0) + 1
        fitid = if count == 1, do: key, else: "#{key} #{count}"
        {Map.put(transaction, :fitid, fitid), Map.put(counts, key, count)}
      end)

    numbered
  end

  defp key(transaction),
    do:
      "#{Date.to_iso8601(transaction.date)} #{transaction.amount} #{Names.lookup_key(transaction.name || "")}"

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # RFC 4180: a quoted field may hold the separator, line breaks and doubled quotes.
  defp records("", _separator, [], [], ""), do: []

  defp records("", _separator, record, records, field),
    do: Enum.reverse([finish(record, field) | records])

  defp records(<<"\"", rest::binary>>, separator, record, records, "") do
    {field, rest} = quoted(rest, "")
    records(rest, separator, record, records, {:quoted, field})
  end

  defp records(<<"\r\n", rest::binary>>, separator, record, records, field),
    do: records(rest, separator, [], [finish(record, field) | records], "")

  defp records(<<"\n", rest::binary>>, separator, record, records, field),
    do: records(rest, separator, [], [finish(record, field) | records], "")

  defp records(<<char::utf8, rest::binary>>, separator, record, records, field) do
    if <<char::utf8>> == separator,
      do: records(rest, separator, [value(field) | record], records, ""),
      else: records(rest, separator, record, records, append(field, <<char::utf8>>))
  end

  defp quoted(<<"\"\"", rest::binary>>, field), do: quoted(rest, field <> "\"")
  defp quoted(<<"\"", rest::binary>>, field), do: {field, rest}
  defp quoted(<<char::utf8, rest::binary>>, field), do: quoted(rest, field <> <<char::utf8>>)
  defp quoted("", field), do: {field, ""}

  defp append({:quoted, field}, _char), do: {:quoted, field}
  defp append(field, char), do: field <> char

  defp value({:quoted, field}), do: field
  defp value(field), do: field

  defp finish(record, field), do: Enum.reverse([value(field) | record])
end
