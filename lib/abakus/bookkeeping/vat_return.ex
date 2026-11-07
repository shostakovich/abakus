defmodule Abakus.Bookkeeping.VatReturn do
  @moduledoc """
  A VAT return under its form's Kennzahlen: the quarterly Umsatzsteuer-Voranmeldung or the annual
  Umsatzsteuererklärung, computed from the entries of its period (`Abakus.Bookkeeping.VatReturns`). Each entry is a
  tax line with its category, treatment, signed amount and date, or a fixed asset's disposal (category
  `:disposal`), which counts like income; one in a private category counts for none, and income at 0 % for none
  either.

  A line's base is whole euros, rounded down in the owner's favour, its tax cents; where the form takes only the base
  (19 % and 7 %), the tax is the base at that rate. `due` is the VAT the period comes to (negative: a surplus); the
  annual return also has the quarters' dues as `prepaid` and the `balance` left after them.
  """

  alias Abakus.Bookkeeping.{Category, Vat}

  defstruct [:year, :quarter, :first, :last, :lines, :totals, :due, :prepaid, :balance]

  @type entry :: %{
          date: Date.t(),
          category: Category.t() | :disposal,
          vat: atom(),
          amount: integer()
        }

  @forms %{
    quarter: %{
      sales_19: {81, nil},
      sales_7: {86, nil},
      sales_other: {35, 36},
      reverse_charge_eu: {46, 47},
      reverse_charge_other: {84, 85},
      input: {nil, 66},
      input_reverse_charge: {nil, 67},
      due: 83
    },
    year: %{
      sales_19: {177, nil},
      sales_7: {275, nil},
      sales_other: {155, 156},
      reverse_charge_eu: {846, 847},
      reverse_charge_other: {877, 878},
      input: {nil, 320},
      input_reverse_charge: {nil, 467},
      due: 816,
      balance: 820
    }
  }

  @lines [
    sales_19: "Umsätze zu 19 %",
    sales_7: "Umsätze zu 7 %",
    sales_other: "Umsätze zu anderen Steuersätzen",
    reverse_charge_eu:
      "Sonstige Leistungen eines im übrigen Gemeinschaftsgebiet ansässigen Unternehmers (§ 13b Abs. 1 UStG)",
    reverse_charge_other: "Andere Leistungen (§ 13b Abs. 2 Nr. 1, 2, 4 bis 12 UStG)",
    input: "Vorsteuer aus Rechnungen von anderen Unternehmern",
    input_reverse_charge: "Vorsteuer aus Leistungen im Sinne des § 13b UStG"
  ]

  @rates %{sales_19: 19, sales_7: 7}

  @doc "The Voranmeldung of `quarter` (1 to 4) of `year` from its entries."
  def quarter(year, quarter, entries) do
    {first, last} = quarter_span(year, quarter)
    lines = lines(:quarter, entries)
    due = due(lines)

    %__MODULE__{
      year: year,
      quarter: quarter,
      first: first,
      last: last,
      lines: lines,
      due: due,
      totals: [total(:due, "Verbleibende Umsatzsteuer-Vorauszahlung", @forms.quarter.due, due)]
    }
  end

  @doc "The Umsatzsteuererklärung of `year` from the entries of the whole year."
  def year(year, entries) do
    lines = lines(:year, entries)
    due = due(lines)

    prepaid =
      Enum.sum_by(1..4, fn quarter ->
        {first, last} = quarter_span(year, quarter)
        quarter(year, quarter, Enum.filter(entries, &(&1.date in Date.range(first, last)))).due
      end)

    %__MODULE__{
      year: year,
      first: Date.new!(year, 1, 1),
      last: Date.new!(year, 12, 31),
      lines: lines,
      due: due,
      prepaid: prepaid,
      balance: due - prepaid,
      totals: [
        total(:due, "Umsatzsteuer", @forms.year.due, due),
        total(:prepaid, "Vorauszahlungssoll", nil, prepaid),
        total(:balance, "Abschlusszahlung / Erstattung", @forms.year.balance, due - prepaid)
      ]
    }
  end

  @doc "The first and last day of `quarter` of `year`."
  def quarter_span(year, quarter) when quarter in 1..4 do
    first = Date.new!(year, quarter * 3 - 2, 1)
    {first, first |> Date.shift(month: 2) |> Date.end_of_month()}
  end

  @doc """
  The return's values by Kennzahl: every line's base and tax that are not zero, and the totals, which always count.
  """
  def kennzahlen(%__MODULE__{lines: lines, totals: totals}) do
    values =
      for line <- lines,
          {kennzahl, value} <- [{line.base_kennzahl, line.base}, {line.tax_kennzahl, line.tax}],
          kennzahl != nil and value != 0,
          do: {kennzahl, value}

    Map.new(values ++ for(t <- totals, t.kennzahl != nil, do: {t.kennzahl, t.tax}))
  end

  defp lines(form, entries) do
    sums = sums(entries)
    kennzahlen = Map.fetch!(@forms, form)

    for {key, label} <- @lines do
      {base_kennzahl, tax_kennzahl} = Map.fetch!(kennzahlen, key)
      %{net: net, vat: vat} = Map.get(sums, key, %{net: 0, vat: 0})
      base = if base_kennzahl, do: Integer.floor_div(net, 100)

      %{
        key: key,
        label: label,
        kind: if(base_kennzahl, do: :output, else: :input),
        base_kennzahl: base_kennzahl,
        base: base,
        tax_kennzahl: tax_kennzahl,
        tax: if(rate = @rates[key], do: base * rate, else: vat)
      }
    end
  end

  defp sums(entries) do
    entries
    |> Enum.flat_map(&shares/1)
    |> Enum.reduce(%{}, fn {key, net, vat}, sums ->
      Map.update(sums, key, %{net: net, vat: vat}, &%{net: &1.net + net, vat: &1.vat + vat})
    end)
  end

  defp shares(%{category: :disposal, vat: treatment} = entry),
    do: income_shares(treatment, Vat.amounts(entry.amount, treatment, entry.date))

  defp shares(%{category: %Category{euer: nil}}), do: []

  defp shares(%{category: %Category{} = category, vat: treatment} = entry) do
    %{net: net, vat: vat} = amounts = Vat.amounts(entry.amount, treatment, entry.date)

    case {category.kind, treatment} do
      {:expense, :reverse_charge} ->
        [{reverse_charge_line(category), -net, -vat}, {:input_reverse_charge, 0, -vat}]

      {:expense, _rate} ->
        [{:input, 0, -vat}]

      {:income, treatment} ->
        income_shares(treatment, amounts)
    end
  end

  defp income_shares(:rate_19, %{net: net, vat: vat}), do: [{:sales_19, net, vat}]
  defp income_shares(:rate_7, %{net: net, vat: vat}), do: [{:sales_7, net, vat}]

  defp income_shares(rate, %{net: net, vat: vat}) when rate in [:rate_16, :rate_5],
    do: [{:sales_other, net, vat}]

  defp income_shares(_untaxed, _amounts), do: []

  defp reverse_charge_line(%Category{vat_return: 46}), do: :reverse_charge_eu
  defp reverse_charge_line(%Category{}), do: :reverse_charge_other

  defp due(lines) do
    Enum.sum_by(lines, fn
      %{kind: :output, tax: tax} -> tax
      %{kind: :input, tax: tax} -> -tax
    end)
  end

  defp total(key, label, kennzahl, tax),
    do: %{key: key, label: label, kennzahl: kennzahl, tax: tax}
end
