defmodule Abakus.FileImport.OFX do
  @moduledoc """
  Reads the statements of an OFX/QFX file: SGML OFX 1.x, whose elements need no end tags, and XML OFX 2.x. Only
  what the file import needs: the account (`BANKACCTFROM`, or `CCACCTFROM` without a bank id), the transactions
  (`STMTTRN`: `DTPOSTED`, `TRNAMT`, `FITID`, `NAME`, `MEMO`) and the ledger balance (`LEDGERBAL`). Amounts become
  cents, timestamps the day as written. A file that is not UTF-8 is read as Latin-1.

  Aggregates end with their end tag in both versions, so each is found as the text between its tags; an element's
  value runs up to the next tag.
  """

  @type transaction :: %{
          fitid: String.t(),
          date: Date.t(),
          amount: integer(),
          name: String.t() | nil,
          memo: String.t() | nil
        }

  @type statement :: %{
          bank_id: String.t() | nil,
          acct_id: String.t(),
          transactions: [transaction()],
          ledger_balance: %{amount: integer(), date: Date.t()} | nil
        }

  @spec parse(binary()) :: {:ok, [statement()]} | {:error, String.t()}
  def parse(content) when is_binary(content) do
    with {:ok, body} <- body(utf8(content)) do
      case aggregates(body, "STMTRS") ++ aggregates(body, "CCSTMTRS") do
        [] -> {:error, "Die Datei enthält keine Kontoumsätze."}
        statements -> collect(statements, &statement/1)
      end
    end
  end

  defp utf8(content) do
    if String.valid?(content), do: content, else: :unicode.characters_to_binary(content, :latin1)
  end

  defp body(text) do
    case Regex.run(~r/<OFX>/i, text, return: :index) do
      [{start, _length}] -> {:ok, binary_part(text, start, byte_size(text) - start)}
      nil -> {:error, "Die Datei ist keine OFX- oder QFX-Datei."}
    end
  end

  defp statement(text) do
    with :ok <- check_currency(element(text, "CURDEF")),
         {:ok, bank_id, acct_id} <- account(text),
         {:ok, transactions} <- transactions(text),
         {:ok, ledger_balance} <- ledger_balance(text) do
      {:ok,
       %{
         bank_id: bank_id,
         acct_id: acct_id,
         transactions: transactions,
         ledger_balance: ledger_balance
       }}
    end
  end

  defp check_currency(currency) when currency in [nil, "EUR"], do: :ok

  defp check_currency(currency),
    do: {:error, "Die Datei ist in #{currency}, Abakus kennt nur Euro."}

  defp account(text) do
    {bank_id, acct_id} =
      case {aggregate(text, "BANKACCTFROM"), aggregate(text, "CCACCTFROM")} do
        {nil, nil} -> {nil, nil}
        {nil, card} -> {nil, element(card, "ACCTID")}
        {bank, _card} -> {element(bank, "BANKID"), element(bank, "ACCTID")}
      end

    if acct_id,
      do: {:ok, bank_id, acct_id},
      else: {:error, "Die Datei nennt kein Konto (ACCTID)."}
  end

  defp transactions(text) do
    text
    |> aggregates("STMTTRN")
    |> Enum.with_index(1)
    |> collect(fn {text, number} -> transaction(text, number) end)
  end

  defp transaction(text, number) do
    with {:ok, fitid} <- required(element(text, "FITID"), "hat keine FITID"),
         {:ok, date} <-
           required(date(element(text, "DTPOSTED")), "hat kein gültiges Datum (DTPOSTED)"),
         {:ok, amount} <-
           required(amount(element(text, "TRNAMT")), "hat keinen gültigen Betrag (TRNAMT)") do
      {:ok,
       %{
         fitid: fitid,
         date: date,
         amount: amount,
         name: element(text, "NAME"),
         memo: element(text, "MEMO")
       }}
    else
      {:error, problem} -> {:error, "Buchung #{number} #{problem}."}
    end
  end

  defp required(nil, problem), do: {:error, problem}
  defp required(value, _problem), do: {:ok, value}

  defp ledger_balance(text) do
    case aggregate(text, "LEDGERBAL") do
      nil ->
        {:ok, nil}

      balance ->
        case {amount(element(balance, "BALAMT")), date(element(balance, "DTASOF"))} do
          {amount, %Date{} = date} when is_integer(amount) -> {:ok, %{amount: amount, date: date}}
          _unreadable -> {:error, "Der Kontostand (LEDGERBAL) ist nicht lesbar."}
        end
    end
  end

  defp date(nil), do: nil

  defp date(value) do
    with [year, month, day] <-
           Regex.run(~r/^(\d{4})(\d{2})(\d{2})/, value, capture: :all_but_first),
         {:ok, date} <-
           Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
      date
    else
      _invalid -> nil
    end
  end

  # Whole cents with a decimal point or comma, up to 12 digits of euros; more decimals only as zeros.
  defp amount(nil), do: nil

  defp amount(value) do
    with true <- value =~ ~r/\d/,
         [sign, euros | decimals] <-
           Regex.run(~r/^([+-]?)(\d{0,12})(?:[.,](\d*))?$/, value, capture: :all_but_first),
         {cents, rest} =
           decimals |> Enum.join() |> String.pad_trailing(2, "0") |> String.split_at(2),
         true <- rest =~ ~r/^0*$/ do
      amount = String.to_integer("0" <> euros) * 100 + String.to_integer(cents)
      if sign == "-", do: -amount, else: amount
    else
      _no_amount -> nil
    end
  end

  # The text inside each aggregate `tag`, which always has an end tag; an opener without one is left out.
  defp aggregates(text, tag) do
    pair(text, offsets(text, ~r/<#{tag}>/i), offsets(text, ~r/<\/#{tag}>/i))
  end

  defp offsets(text, regex), do: regex |> Regex.scan(text, return: :index) |> Enum.map(&hd/1)

  defp pair(text, [{start, length} | openers], closers) do
    from = start + length

    case Enum.drop_while(closers, fn {close, _length} -> close < from end) do
      [{close, close_length} | closers] ->
        openers =
          Enum.drop_while(openers, fn {start, _length} -> start < close + close_length end)

        [binary_part(text, from, close - from) | pair(text, openers, closers)]

      [] ->
        []
    end
  end

  defp pair(_text, [], _closers), do: []

  defp aggregate(text, tag), do: text |> aggregates(tag) |> List.first()

  # An element's value, up to the next tag (its end tag in XML); blank is nil.
  defp element(text, tag) do
    case Regex.run(~r/<#{tag}>([^<]*)/i, text, capture: :all_but_first) do
      [value] -> value |> decode() |> String.trim() |> blank_to_nil()
      nil -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " "
  }

  defp decode(value) do
    Regex.replace(~r/&(?:#(\d{1,7})|#x([0-9a-f]{1,6})|(\w+));/i, value, fn
      whole, "", "", name -> Map.get(@entities, String.downcase(name), whole)
      whole, "", hex, _name -> codepoint(String.to_integer(hex, 16), whole)
      whole, decimal, _hex, _name -> codepoint(String.to_integer(decimal), whole)
    end)
  end

  defp codepoint(code, whole) do
    case :unicode.characters_to_binary([code]) do
      binary when is_binary(binary) -> binary
      _invalid -> whole
    end
  end

  defp collect(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, done} ->
      case fun.(item) do
        {:ok, result} -> {:cont, {:ok, [result | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end
end
