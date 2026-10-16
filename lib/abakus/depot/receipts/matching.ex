defmodule Abakus.Depot.Receipts.Matching do
  @moduledoc """
  Where a receipt's text has the values the model recognised, for the check against invented
  values and the marks on the screen. Numbers match with their natural, two, three or four
  decimal places, in German notation with or without thousands dots, or in English notation as
  some banks print it in English, as magnitudes, so that `879,28-` and `-879,28` have 879.28;
  never inside a longer number or word. A lone digit matches only as shares beside „Stück“,
  „Stk.“, „St.“ or „Anzahl“, anywhere else it would be a page number. The date matches as
  `01.10.2026`, `01.10.26` or `2026-10-01`; ISIN, depot number and reference as they are,
  blanks aside. Fees and taxes the text lists in lines of their own also count as found as the
  sum of consecutive amounts.
  """

  alias Abakus.Depot.Receipts.Fields

  @values [:date, :isin, :shares, :price, :fees, :taxes, :amount, :depot_number, :bank_reference]
  @numbers [:shares, :price, :fees, :taxes, :amount]
  @texts [:isin, :depot_number, :bank_reference]

  # Not inside a word or a number: no letter or digit around, no digit after a separator.
  @left_bound "(?<![\\p{L}\\d])(?<!\\d[.,])"
  @right_bound "(?![\\p{L}\\d]|[.,]\\d)"
  @shares_word "(?i:stück|stk\\.?|st\\.|anzahl|pcs?\\.)"

  # An amount of money in German or English notation, such as 1.125,00 or 1,125.00, not a
  # percentage.
  @money ~r/(?<![\p{L}\d])(?<!\d[.,])(?:(?:\d{1,3}(?:\.\d{3})+|\d+),\d{2}|(?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2})(?![\p{L}\d]|[.,]\d|\s*%)/u
  @longest_run 5

  @doc "The values checked against the text, in the order the check names them."
  def values, do: @values

  @doc """
  The regex matching each of the recognised values where `fields` has one, longest first; nil
  when there is none to match.
  """
  def regex(%Fields{} = fields) do
    case Enum.flat_map(@values, &patterns(&1, Map.fetch!(fields, &1))) do
      [] -> nil
      patterns -> compile(patterns)
    end
  end

  @doc """
  The recognised values of `fields` that `text` does not have, in the order of `values/0`; no
  fees or taxes need not be found.
  """
  def missing(text, %Fields{} = fields) do
    for field <- @values,
        value = Map.fetch!(fields, field),
        not zero?(field, value),
        not found?(text, field, value),
        do: field
  end

  defp zero?(field, value) when field in [:fees, :taxes], do: Decimal.eq?(value, 0)
  defp zero?(_field, _value), do: false

  defp found?(text, field, value) do
    case patterns(field, value) do
      [] -> false
      patterns -> Regex.match?(compile(patterns), text)
    end || (field in [:fees, :taxes] and sum_of_consecutive_amounts?(text, value))
  end

  defp compile(patterns) do
    patterns
    |> Enum.uniq()
    |> Enum.sort_by(&(-String.length(&1)))
    |> Enum.join("|")
    |> Regex.compile!("u")
  end

  defp patterns(_field, nil), do: []

  defp patterns(:date, date) do
    [
      Calendar.strftime(date, "%d.%m.%Y"),
      Calendar.strftime(date, "%d.%m.%y"),
      Date.to_iso8601(date)
    ]
    |> Enum.map(&bounded(Regex.escape(&1)))
  end

  defp patterns(field, text) when field in @texts do
    case String.replace(text, ~r/\s/u, "") do
      "" ->
        []

      blankless ->
        source = blankless |> String.graphemes() |> Enum.map_join(" *", &Regex.escape/1)
        [bounded(source)]
    end
  end

  defp patterns(field, number) when field in @numbers do
    {lone, longer} = number |> notations() |> Enum.split_with(&(String.length(&1) == 1))
    longer = Enum.map(longer, &bounded(Regex.escape(&1)))
    if field == :shares, do: longer ++ Enum.map(lone, &beside_shares_word/1), else: longer
  end

  defp bounded(source), do: @left_bound <> "(?:" <> source <> ")" <> @right_bound

  # `\K` keeps the word out of the match, so that only the digit is marked.
  defp beside_shares_word(digit),
    do:
      "#{@shares_word}\\s*\\K#{digit}#{@right_bound}|#{@left_bound}#{digit}(?=\\s*#{@shares_word})"

  @doc "A number in German notation with `places` decimal places, e.g. `1.125,00`."
  def german(%Decimal{} = number, places) do
    [whole | fraction] =
      number
      |> Decimal.abs()
      |> Decimal.round(places)
      |> Decimal.to_string(:normal)
      |> String.split(".")

    thousands(whole) <> Enum.map_join(fraction, &("," <> &1))
  end

  defp thousands(digits) do
    digits
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(".", &Enum.join/1)
    |> String.reverse()
  end

  defp notations(number) do
    normalized = Decimal.normalize(number)

    if Decimal.eq?(normalized, 0),
      do: [],
      else: notations(normalized, max(-normalized.exp, 0))
  end

  defp notations(number, natural) do
    for places <- Enum.uniq(Enum.map([natural, 2, 3, 4], &max(&1, natural))),
        formatted = german(number, places),
        german <- [formatted, String.replace(formatted, ".", "")],
        notation <- [german, english(german)],
        uniq: true,
        do: notation
  end

  defp english(german),
    do: german |> String.to_charlist() |> Enum.map(&swap/1) |> List.to_string()

  defp swap(?.), do: ?,
  defp swap(?,), do: ?.
  defp swap(char), do: char

  defp sum_of_consecutive_amounts?(text, value) do
    amounts =
      for [amount] <- Regex.scan(@money, text), do: decimal(amount)

    amounts
    |> Stream.unfold(fn
      [] -> nil
      [_first | rest] = amounts -> {amounts, rest}
    end)
    |> Enum.any?(&run_sums_to?(&1, value))
  end

  # The separator before the two decimal places tells the notation.
  defp decimal(amount) do
    {whole, <<_separator, cents::binary>>} = String.split_at(amount, -3)
    Decimal.new(String.replace(whole, ~r/[.,]/, "") <> "." <> cents)
  end

  defp run_sums_to?(amounts, value) do
    amounts
    |> Enum.take(@longest_run)
    |> Enum.scan(&Decimal.add/2)
    |> Enum.drop(1)
    |> Enum.any?(&Decimal.eq?(&1, value))
  end
end
