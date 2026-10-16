defmodule Abakus.Depot.Receipts.Correction do
  @moduledoc """
  What the model hears when its answer fails the checks it can pass by reading the receipt again,
  and how the screen names a recognised value: in German, numbers in German notation.
  """

  alias Abakus.Depot.Receipts.{Check, Checks, Fields, Matching}

  @labels %{
    date: "Datum",
    isin: "ISIN",
    shares: "Stück",
    price: "Kurs",
    fees: "Gebühren",
    taxes: "Steuern",
    amount: "Betrag",
    depot_number: "Depot",
    bank_reference: "Referenz"
  }
  @money [:price, :fees, :taxes, :amount]

  @doc """
  The user's message naming the failed `checks` of `fields`, the values not found last, and
  asking for a new answer.
  """
  def message(checks, %Fields{} = fields) do
    checks
    |> Enum.filter(&(&1.result == :failed or match?(%Check{name: :amount, result: :missing}, &1)))
    |> Enum.sort_by(&(&1.name == :found))
    |> Enum.map(&problem(&1, fields))
    |> Enum.concat(["Antworte erneut im selben Schema."])
    |> Enum.join(" ")
  end

  defp problem(%Check{name: :amount, result: :missing}, fields) do
    missing =
      for {field, label} <- [shares: "Stück", price: price_label(fields), amount: "Betrag"],
          is_nil(Map.fetch!(fields, field)),
          do: label

    "Du nennst keine Angabe zu #{enumerate(missing)}. Jeder #{kind_label(fields)} hat sie; " <>
      "Stück stehen etwa bei „Stück“, „St.“, „Stk.“, „STK“, „Anzahl“ oder „Nominale“. " <>
      "Suche sie im Beleg."
  end

  defp problem(%Check{name: :amount, computed: computed}, fields) do
    "#{Checks.formula(fields)} ergibt #{money(computed)}, du nennst #{money(fields.amount)}. " <>
      "Prüfe Betrag, Kurs, Gebühren und Steuern im Beleg."
  end

  defp problem(%Check{name: :isin}, fields),
    do: "Die ISIN #{fields.isin} hat eine falsche Prüfziffer. Prüfe die ISIN im Beleg."

  defp problem(%Check{name: :found} = check, fields),
    do: "#{not_found(check, fields)}. Übernimm nur Werte, die im Beleg stehen."

  @doc "The values of a failed `:found` check, e.g. „Kurs 145,76 € steht nicht im Beleg“."
  def not_found(%Check{name: :found, not_found: missing}, %Fields{} = fields) do
    verb = if length(missing) == 1, do: "steht", else: "stehen"
    "#{enumerate(Enum.map(missing, &value(&1, fields)))} #{verb} nicht im Beleg"
  end

  defp price_label(%Fields{kind: :dividend}), do: "Dividende pro Stück"
  defp price_label(_fields), do: "Kurs"

  defp kind_label(%Fields{kind: :purchase}), do: "Kauf"
  defp kind_label(%Fields{kind: :sale}), do: "Verkauf"
  defp kind_label(%Fields{kind: :dividend}), do: "Dividendenbeleg"

  defp enumerate([one]), do: one

  defp enumerate(values),
    do: Enum.join(Enum.drop(values, -1), ", ") <> " und " <> List.last(values)

  # A recognised value with its name, e.g. „Kurs 145,76 €“.
  defp value(:price, %Fields{kind: :dividend, price: price}), do: "Dividende #{money(price)}"
  defp value(:date, %Fields{date: date}), do: "Datum #{Calendar.strftime(date, "%d.%m.%Y")}"

  defp value(field, fields) when field in @money,
    do: "#{@labels[field]} #{money(Map.fetch!(fields, field))}"

  defp value(:shares, %Fields{shares: shares}) do
    normalized = Decimal.normalize(shares)
    "Stück #{Matching.german(normalized, max(-normalized.exp, 0))}"
  end

  defp value(field, fields), do: "#{@labels[field]} #{Map.fetch!(fields, field)}"

  defp money(number) do
    normalized = Decimal.normalize(number)
    Matching.german(normalized, max(-normalized.exp, 2)) <> " €"
  end
end
