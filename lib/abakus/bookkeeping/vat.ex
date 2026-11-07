defmodule Abakus.Bookkeeping.Vat do
  @moduledoc """
  The VAT treatments of a tax line: a rate the amount includes, or reverse charge under §13b, where the amount is
  net and the owner owes the VAT and deducts it again.
  """

  @rates [rate_19: 19, rate_16: 16, rate_7: 7, rate_5: 5, rate_0: 0]
  @treatments Keyword.keys(@rates) ++ [:reverse_charge]
  @reduced_standard Date.range(~D[2020-07-01], ~D[2020-12-31])

  @doc "Every treatment, in the order the form offers them."
  def treatments, do: @treatments

  @doc "How each treatment is stored."
  def stored,
    do:
      Enum.map(@rates, fn {t, rate} -> {t, to_string(rate)} end) ++
        [reverse_charge: "reverse_charge"]

  def label(:reverse_charge), do: "§13b Reverse Charge"
  def label(treatment), do: "#{Keyword.fetch!(@rates, treatment)} %"

  @doc """
  The net and VAT amount (cents, signed like `amount`) of a transaction's `amount` on `date`; under reverse charge the
  standard rate of that date applies to the whole amount.
  """
  def amounts(amount, :reverse_charge, %Date{} = date) do
    %{net: amount, vat: share(amount * standard_rate(date), 100)}
  end

  def amounts(amount, treatment, _date) do
    rate = Keyword.fetch!(@rates, treatment)
    vat = share(amount * rate, 100 + rate)
    %{net: amount - vat, vat: vat}
  end

  defp standard_rate(date), do: if(date in @reduced_standard, do: 16, else: 19)

  defp share(numerator, denominator) when numerator < 0, do: -share(-numerator, denominator)
  defp share(numerator, denominator), do: div(2 * numerator + denominator, 2 * denominator)
end
