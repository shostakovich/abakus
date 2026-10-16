defmodule Abakus.Depot.Costs do
  @moduledoc """
  What the held funds cost a year: their TER from PP's attribute times their value, and the TER
  weighted by value. A security without a TER is listed but left out of both. Pure; amounts in
  euro cents, TERs as fractions (0.002 for 0.20 %).
  """

  alias Abakus.Depot.Securities.Security

  @doc """
  The costs of `holdings`, each a map with a `security` and its `value` in euro cents:

  - `funds`: per security its `value`, `ter`, `fund_size` (see `Security.fund_size/1`) and
    `per_year`, nil without a TER; by value. A security held in several portfolios is one fund.
  - `ter`: Σ(value × TER) / Σ value over the funds with a TER, nil without any
  - `per_year`: Σ(value × TER), nil without any TER
  """
  def of(holdings) do
    funds =
      holdings
      |> Enum.group_by(& &1.security.id)
      |> Enum.map(fn {_id, [%{security: security} | _] = rows} ->
        fund(security, Enum.sum_by(rows, & &1.value))
      end)
      |> Enum.sort_by(&{-&1.value, &1.security.name})

    Map.merge(%{funds: funds}, totals(Enum.filter(funds, & &1.ter)))
  end

  defp fund(security, value) do
    ter = Security.ter(security)

    %{
      security: security,
      value: value,
      ter: ter,
      fund_size: Security.fund_size(security),
      per_year: ter && value |> yearly(ter) |> to_cents()
    }
  end

  defp totals([]), do: %{ter: nil, per_year: nil}

  defp totals(funds) do
    per_year = funds |> Enum.map(&yearly(&1.value, &1.ter)) |> Enum.reduce(&Decimal.add/2)
    value = Enum.sum_by(funds, & &1.value)

    %{
      ter: if(value > 0, do: Decimal.div(per_year, value)),
      per_year: to_cents(per_year)
    }
  end

  defp yearly(value, ter), do: Decimal.mult(value, ter)

  defp to_cents(decimal), do: decimal |> Decimal.round(0, :half_up) |> Decimal.to_integer()
end
