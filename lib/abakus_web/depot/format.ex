defmodule AbakusWeb.Depot.Format do
  @moduledoc """
  What only the Depot shows: prices and shares × 10⁸, currencies, fund sizes, TERs, portfolio
  names and transaction types. Dates and other numbers are `Abakus.Format`'s, amounts in euros `Abakus.Money`'s.
  """

  alias Abakus.Depot.Portfolios.{Portfolio, Transaction}
  alias Abakus.Format

  @doc """
  A price × 10⁸ with two to four decimal places and its currency as `currency/1` names it, e.g.
  `1.234,5678 USD` or `166,66 €`; the currency never wraps onto a line of its own.
  """
  def price(nil, _currency), do: "–"
  def price(close, currency), do: price(close, currency, price_places(close))

  @doc "A price × 10⁸ with `places` decimal places."
  def price(nil, _currency, _places), do: "–"

  def price(close, currency, places) do
    [Format.number(price_amount(close), places), currency(currency)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\u00A0")
  end

  @doc "The decimal places a price × 10⁸ shows: those it has, from two to four."
  def price_places(close), do: -Decimal.normalize(price_amount(close)).exp |> max(2) |> min(4)

  defp price_amount(close),
    do: close |> Decimal.new() |> Decimal.div(100_000_000) |> Decimal.round(4)

  @doc "A currency as prices name it: `€` for euros, otherwise its code."
  def currency("EUR"), do: "€"
  def currency(code), do: code

  @doc "How setzkasten's `<.amount>` names a currency, as `currency/1` does."
  def currency_display("EUR"), do: :symbol
  def currency_display(_code), do: :code

  @doc "A change of a price × 10⁸ with its sign, e.g. `−1,06 €`; none when it rounds to zero."
  def signed_price(change, currency) do
    unchanged = price(0, currency)

    case price(abs(change), currency) do
      ^unchanged -> unchanged
      shown when change > 0 -> "+" <> shown
      shown -> "−" <> shown
    end
  end

  defdelegate shares(shares), to: Format

  @doc """
  A fund size in cents in billions with one decimal place, e.g. `17,8 Mrd. €`, below 100 million
  in whole millions, e.g. `85 Mio. €`; it never wraps.
  """
  def fund_size(nil, _currency), do: "–"

  def fund_size(cents, currency) do
    amount =
      if cents >= 10_000_000_000,
        do: Format.number(Decimal.div(cents, 100_000_000_000), 1) <> "\u00A0Mrd.",
        else: Format.number(Decimal.div(cents, 100_000_000), 0) <> "\u00A0Mio."

    amount <> "\u00A0" <> currency(currency)
  end

  @doc "A TER, a fraction, in percent with two decimal places, e.g. `0,22 %`."
  def ter(nil), do: "–"
  def ter(%Decimal{} = ter), do: ter |> Decimal.mult(100) |> Format.percent(2)

  @doc "A portfolio's name or its `name`; „Ohne Namen“ for an empty one."
  def portfolio_name(%{name: name}), do: portfolio_name(name)
  def portfolio_name(name) when name in [nil, ""], do: "Ohne Namen"
  def portfolio_name(name) when is_binary(name), do: name

  @doc "The name of a transaction's type, e.g. „Depotwechsel“."
  def transaction_type(type), do: Transaction.label(type)

  @doc "A depot or account number by its last four digits, e.g. „…4471“."
  def masked(number),
    do: "…" <> (number |> Portfolio.digits() |> String.slice(-4, 4))
end
