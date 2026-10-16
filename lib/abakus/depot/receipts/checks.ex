defmodule Abakus.Depot.Receipts.Checks do
  @moduledoc """
  The checks of a receipt's recognised fields, in code rather than in the model: the amount
  against shares × price with fees and taxes, within the transaction form's tolerance; whether
  the receipt's text has every recognised value, against values the model invented; the ISIN's
  check digit and whether the security is known; whether the depot number belongs to one of the
  user's portfolios, comparing digits only; and whether a receipt with the same bank reference
  was booked already.
  """

  alias Abakus.Depot.Portfolios.{Portfolio, TransactionForm}
  alias Abakus.Depot.Receipts.{Check, Fields, Matching}
  alias Abakus.Depot.Securities.ISIN

  @doc """
  The checks of `fields` recognised in `text`; `known_isins` is a set of the ISINs of the
  securities, `portfolios` maps the digits of the user's depot numbers to their portfolios,
  `booked_on` is a function giving the day of the transaction booked from a receipt with a
  reference, nil if there is none.
  """
  def run(%Fields{} = fields, text, known_isins, portfolios, booked_on) do
    [
      amount(fields),
      found(fields, text),
      isin(fields.isin, known_isins),
      depot_number(Portfolio.digits(fields.depot_number), portfolios),
      reference(fields.bank_reference, booked_on)
    ]
  end

  @doc """
  The checks a model can pass by reading the receipt again: the amount, the values found in
  `text` and the ISIN's check digit, where an unknown security passes; none for a receipt of
  kind `:other`, which is not booked.
  """
  def correctable(%Fields{kind: :other}, _text), do: []

  def correctable(%Fields{} = fields, text) do
    [amount(fields), found(fields, text), isin(fields.isin, :any)]
  end

  @doc """
  Whether the model is asked to read the receipt again: its amount does not add up, misses
  shares, price or amount, or its ISIN's check digit is wrong. Values not found alone do not
  ask, as fees spread over the text may be right all the same.
  """
  def correction_needed?(checks) do
    Enum.any?(checks, fn check ->
      (check.name in [:amount, :isin] and check.result == :failed) or
        (check.name == :amount and check.result == :missing)
    end)
  end

  @doc "The portfolio the depot number of a receipt with `checks` belongs to, as `{id, name}`."
  def portfolio(checks) do
    case Enum.find(checks, &match?(%Check{name: :depot, result: :passed}, &1)) do
      nil -> nil
      check -> {check.portfolio_id, check.portfolio_name}
    end
  end

  @doc "Whether a receipt with `checks` was booked already under its bank reference."
  def duplicate?(checks),
    do: Enum.any?(checks, &match?(%Check{name: :reference, result: :failed}, &1))

  defp amount(%Fields{shares: shares, price: price, amount: amount} = fields)
       when shares != nil and price != nil and amount != nil do
    computed = computed_amount(fields)
    off = computed |> Decimal.sub(amount) |> Decimal.abs()

    result =
      if Decimal.gt?(off, TransactionForm.price_tolerance(shares)), do: :failed, else: :passed

    %Check{name: :amount, result: result, computed: Decimal.round(computed, 2, :half_up)}
  end

  defp amount(_fields), do: %Check{name: :amount, result: :missing}

  defp computed_amount(fields) do
    gross = Decimal.mult(fields.shares, fields.price)
    fees_and_taxes = Decimal.add(fields.fees || 0, fields.taxes || 0)

    if fields.kind == :purchase,
      do: Decimal.add(gross, fees_and_taxes),
      else: Decimal.sub(gross, fees_and_taxes)
  end

  @doc "The amount check's sum in words, e.g. „Stück × Kurs + Gebühren“."
  def formula(%Fields{kind: kind} = fields) do
    {price, sign} = if kind == :dividend, do: {"Dividende", "−"}, else: {"Kurs", "+"}
    sign = if kind == :sale, do: "−", else: sign

    costs =
      for {label, value} <- [{"Gebühren", fields.fees}, {"Steuern", fields.taxes}],
          value && not Decimal.eq?(value, 0),
          do: " #{sign} #{label}"

    "Stück × #{price}#{Enum.join(costs)}"
  end

  defp found(fields, text) do
    case Matching.missing(text, fields) do
      [] -> %Check{name: :found, result: :passed}
      missing -> %Check{name: :found, result: :failed, not_found: missing}
    end
  end

  defp isin(nil, _known), do: %Check{name: :isin, result: :missing}

  defp isin(isin, known) do
    result =
      cond do
        not ISIN.valid?(isin) -> :failed
        known == :any or MapSet.member?(known, isin) -> :passed
        true -> :new_security
      end

    %Check{name: :isin, result: result}
  end

  defp depot_number("", _portfolios), do: %Check{name: :depot, result: :missing}

  defp depot_number(digits, portfolios) do
    case portfolios do
      %{^digits => portfolio} ->
        %Check{
          name: :depot,
          result: :passed,
          portfolio_id: portfolio.id,
          portfolio_name: portfolio.name
        }

      _unknown ->
        %Check{name: :depot, result: :failed}
    end
  end

  defp reference(nil, _booked_on), do: %Check{name: :reference, result: :missing}

  defp reference(reference, booked_on) do
    case booked_on.(reference) do
      nil -> %Check{name: :reference, result: :passed}
      day -> %Check{name: :reference, result: :failed, booked_on: day}
    end
  end
end
