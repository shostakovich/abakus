defmodule Abakus.Bookkeeping.IncomeStatement do
  @moduledoc """
  The EÜR of a year under the Kennzahlen of the Anlage EÜR, in cents, computed from the year's tax lines (entries as
  `Abakus.Bookkeeping.VatReturn` takes them) and the fixed assets with their disposals.

  A tax line counts its net amount on its category's line and its VAT as VAT received or input VAT paid; under
  reverse charge the VAT owed and deducted cancels out and counts for neither. A purchase in a category of the
  Anlagevermögen counts only its input VAT, since the asset register writes it off (`Abakus.Bookkeeping.Depreciation`):
  a low-value asset at once, any other by its depreciation. A disposal counts the book value it leaves as an expense
  and its amount as income, with its VAT as VAT received.

  `assets` is the year's asset register as the Anlage AVEÜR lists it: every depreciated asset with a book value at
  the start of the year or bought in it, with that book value, the year's depreciation, the book value a disposal
  leaves and the book value at the end of the year.
  """

  alias Abakus.Bookkeeping.{Category, Depreciation, Vat}

  defstruct [:year, :income, :expenses, :totals, :assets]

  @income [
    {112, "Umsatzsteuerpflichtige Betriebseinnahmen"},
    {140, "Vereinnahmte Umsatzsteuer sowie Umsatzsteuer auf unentgeltliche Wertabgaben"},
    {141, "Vom Finanzamt erstattete und ggf. verrechnete Umsatzsteuer"},
    {102, "Veräußerung oder Entnahme von Anlagevermögen"}
  ]

  @expenses [
    {110, "Bezogene Fremdleistungen"},
    {130, "AfA auf bewegliche Wirtschaftsgüter"},
    {132, "Aufwendungen für geringwertige Wirtschaftsgüter"},
    {135, "Restbuchwert der ausgeschiedenen Anlagegüter"},
    {280, "Aufwendungen für Telekommunikation"},
    {221, "Übernachtungs- und Reisenebenkosten bei Geschäftsreisen"},
    {281, "Fortbildungskosten"},
    {194, "Rechts- und Steuerberatung, Buchführung"},
    {223, "Beiträge, Gebühren, Abgaben und Versicherungen"},
    {224, "Werbekosten"},
    {183, "Übrige unbeschränkt abziehbare Betriebsausgaben"},
    {145, "Kraftfahrzeugkosten: Steuern, Versicherungen und Mitgliedsbeiträge"},
    {146, "Sonstige tatsächliche Fahrtkosten"},
    {185, "Gezahlte Vorsteuerbeträge"},
    {186, "An das Finanzamt gezahlte und ggf. verrechnete Umsatzsteuer"}
  ]

  @vat_received 140
  @input_vat 185
  @disposals 102
  @depreciation 130
  @low_value 132
  @remaining 135

  @doc "The Kennzahlen of the income lines, in the form's order."
  def income_kennzahlen, do: Enum.map(@income, &elem(&1, 0))

  @doc "The Kennzahlen of the expense lines, in the form's order."
  def expense_kennzahlen, do: Enum.map(@expenses, &elem(&1, 0))

  @doc "The EÜR of `year` from its entries and the fixed assets, each with its disposal loaded."
  def year(year, entries, assets) do
    sums =
      by_kennzahl(
        Enum.flat_map(entries, &shares/1) ++ Enum.flat_map(assets, &asset_shares(&1, year))
      )

    income = lines(@income, sums)
    expenses = lines(@expenses, sums)
    total_income = Enum.sum_by(income, & &1.amount)
    total_expenses = Enum.sum_by(expenses, & &1.amount)

    %__MODULE__{
      year: year,
      income: income,
      expenses: expenses,
      totals: [
        %{key: :income, label: "Summe Betriebseinnahmen", kennzahl: 159, amount: total_income},
        %{key: :expenses, label: "Summe Betriebsausgaben", kennzahl: 199, amount: total_expenses},
        %{
          key: :profit,
          label: "Gewinn/Verlust",
          kennzahl: nil,
          amount: total_income - total_expenses
        }
      ],
      assets: register(assets, year)
    }
  end

  @doc "What the asset, with its disposal loaded, counts for in the EÜR of `year`, by Kennzahl: none when nothing."
  def asset_kennzahlen(asset, year) do
    asset
    |> asset_shares(year)
    |> Enum.reject(fn {_kennzahl, cents} -> cents == 0 end)
    |> by_kennzahl()
  end

  defp by_kennzahl(shares) do
    Enum.reduce(shares, %{}, fn {kennzahl, cents}, sums ->
      Map.update(sums, kennzahl, cents, &(&1 + cents))
    end)
  end

  defp register(assets, year) do
    last_year = Date.new!(year - 1, 12, 31)
    year_end = Date.new!(year, 12, 31)

    for asset <- Enum.sort_by(assets, & &1.purchased_on, Date),
        not Depreciation.low_value?(asset.net),
        asset.purchased_on.year <= year,
        start = Depreciation.current_value(asset, last_year),
        start > 0 or asset.purchased_on.year == year do
      counted = Depreciation.year(asset, year)

      %{
        name: asset.name,
        purchased_on: asset.purchased_on,
        net: asset.net,
        start: start,
        write_off: counted.write_off,
        remaining: counted.remaining,
        end: Depreciation.current_value(asset, year_end)
      }
    end
  end

  @doc "The statement's amounts by Kennzahl: every line that is not zero, and the totals."
  def kennzahlen(%__MODULE__{} = statement) do
    lines = for line <- statement.income ++ statement.expenses, do: {line.kennzahl, line.amount}
    totals = for total <- statement.totals, total.kennzahl, do: {total.kennzahl, total.amount}
    Map.new(lines ++ totals)
  end

  defp lines(form, sums) do
    for {kennzahl, label} <- form,
        amount = Map.get(sums, kennzahl, 0),
        amount != 0,
        do: %{kennzahl: kennzahl, label: label, amount: amount}
  end

  defp shares(%{category: %Category{euer: nil}}), do: []

  defp shares(%{category: %Category{} = category, vat: treatment} = entry) do
    %{net: net, vat: vat} = Vat.amounts(entry.amount, treatment, entry.date)

    case {category.kind, treatment, Category.fixed_asset?(category)} do
      {:income, _treatment, _asset} -> [{category.euer, net}, {@vat_received, vat}]
      {:expense, :reverse_charge, _asset} -> [{category.euer, -net}]
      {:expense, _rate, true} -> [{@input_vat, -vat}]
      {:expense, _rate, false} -> [{category.euer, -net}, {@input_vat, -vat}]
    end
  end

  defp asset_shares(asset, year) do
    counted = Depreciation.year(asset, year)
    write_off = {if(counted.low_value?, do: @low_value, else: @depreciation), counted.write_off}
    [write_off | disposal_shares(counted)]
  end

  defp disposal_shares(%{disposal: nil}), do: []

  defp disposal_shares(%{disposal: disposal, remaining: remaining}) do
    %{net: net, vat: vat} = Vat.amounts(disposal.amount, disposal.vat, disposal.date)
    [{@remaining, remaining}, {@disposals, net}, {@vat_received, vat}]
  end
end
