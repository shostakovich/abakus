defmodule Abakus.Depot.Allocation do
  @moduledoc """
  How the value of the held securities divides into regions and sectors, from the compositions of
  the funds; accounts do not count. Each weight of a composition counts in proportion to their
  sum, so their scale and rounding do not matter. A security without a composition, or without
  countries or sectors in it, counts under nil, „Ohne Angabe“. Pure; shares as fractions of 1.
  """

  alias Abakus.Depot.Allocation.Region
  alias Abakus.Depot.Securities.Composition

  @doc """
  The allocation of `holdings`, each a map with a `security` and its `value` in euro cents, from
  `compositions` as `%{security_id => composition}`:

  - `regions`: `%{key: region, share: fraction}` per block of `Region` with a share, by share,
    then the share without countries under nil
  - `sectors`: the same per sector as DivvyDiary names it
  - `as_of`: when the oldest composition of the holdings was fetched, nil without any
  """
  def of(holdings, compositions),
    do: holdings |> Enum.map(&{&1.value, compositions[&1.security.id]}) |> allocation()

  @doc "The regions and sectors of one fund's `composition`, as `of/2` gives them for it alone."
  def of_composition(%Composition{} = composition), do: allocation([{1, composition}])

  # Each fund as `{value, composition}`.
  defp allocation(funds) do
    total = Enum.sum_by(funds, &elem(&1, 0))

    %{
      regions: shares(funds, total, :countries, &Region.of/1),
      sectors: shares(funds, total, :sectors, & &1),
      as_of: funds |> Enum.flat_map(&fetched_at/1) |> Enum.min(DateTime, fn -> nil end)
    }
  end

  defp fetched_at({_value, nil}), do: []
  defp fetched_at({_value, composition}), do: [composition.fetched_at]

  defp shares(_funds, total, _field, _key_of) when total <= 0, do: []

  defp shares(funds, total, field, key_of) do
    {known, unknown} =
      funds
      |> Enum.flat_map(fn {value, composition} ->
        split(value, weights(composition, field), key_of)
      end)
      |> Enum.group_by(fn {key, _value} -> key end, fn {_key, value} -> value end)
      |> Enum.map(fn {key, values} -> %{key: key, share: share(values, total)} end)
      |> Enum.split_with(& &1.key)

    Enum.sort_by(known, & &1.share, {:desc, Decimal}) ++ unknown
  end

  defp weights(nil, _field), do: %{}

  defp weights(composition, field) do
    for {name, weight} <- Map.fetch!(composition, field),
        weight > 0,
        into: %{},
        do: {name, decimal(weight)}
  end

  # The value of a fund under the key of each weight, in proportion to their sum.
  defp split(value, weights, _key_of) when map_size(weights) == 0, do: [{nil, Decimal.new(value)}]

  defp split(value, weights, key_of) do
    sum = weights |> Map.values() |> Enum.reduce(&Decimal.add/2)

    for {name, weight} <- weights,
        do: {key_of.(name), value |> Decimal.mult(weight) |> Decimal.div(sum)}
  end

  defp share(values, total), do: values |> Enum.reduce(&Decimal.add/2) |> Decimal.div(total)

  defp decimal(weight) when is_float(weight), do: Decimal.from_float(weight)
  defp decimal(weight) when is_integer(weight), do: Decimal.new(weight)
end
