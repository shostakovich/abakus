defmodule Abakus.Depot.Allocation.Classifications do
  @moduledoc """
  How the value of holdings and accounts divides into the top-level classifications of a
  taxonomy, against their target weights, as PP's rebalancing view compares them.

  Each assignment counts its weight of a value for the top-level classification it is under,
  however deep; a value assigned more than 100 % in all counts more than once, as in PP. Shares
  and targets refer to the value in the classifications, as PP's targets do; what no
  classification below the root holds is unassigned, „Ohne Kategorie“, and left out. The target
  of a top-level classification is its weight as it is. Weights are in 1/100 percent. Pure;
  shares as fractions of 1.
  """

  @full_weight 10_000

  # PP's default threshold for a deviation from the target.
  @tolerance Decimal.new("0.05")

  @doc """
  The allocation of `holdings` (each with a `security` and its `value` in euro cents) and
  `accounts` (each with an `account` and its `value`) into `taxonomy`, whose classifications
  come with their assignments:

  - `taxonomy`
  - `classifications`: each top-level classification with a value or a target, by rank, as
    `%{classification: c, share: fraction, target: fraction, deviation: :above | :below | nil}`;
    `deviation` says whether the share is more than 5 percentage points off the target. None
    while the value in the classifications is not positive.
  - `unassigned`: `%{value: cents, share: fraction}` of the value in no classification, its
    share of all the value nil while that is not positive; nil without such value
  """
  def of(taxonomy, holdings, accounts) do
    values = values(holdings, accounts)
    assignments = assignments(taxonomy.classifications, values)
    classified = values_by_top_level(assignments, values)
    total = classified |> Map.values() |> sum()
    unassigned = unassigned_value(values, assignments)

    %{
      taxonomy: taxonomy,
      classifications: rows(top_levels(taxonomy.classifications), classified, total),
      unassigned: unassigned(unassigned, Decimal.add(total, unassigned))
    }
  end

  # The value of each security and account, as `%{{:security | :account, id} => cents}`.
  defp values(holdings, accounts) do
    Enum.map(holdings, &{{:security, &1.security.id}, &1.value})
    |> Enum.concat(Enum.map(accounts, &{{:account, &1.account.id}, &1.value}))
    |> Enum.group_by(fn {vehicle, _value} -> vehicle end, fn {_vehicle, value} -> value end)
    |> Map.new(fn {vehicle, values} -> {vehicle, Enum.sum(values)} end)
  end

  # The assignments below a top-level classification of what has a value, as `{top-level id,
  # vehicle, weight}`.
  defp assignments(classifications, values) do
    top_level_ids = top_level_ids(classifications)

    for classification <- classifications,
        top_id = top_level_ids[classification.id],
        top_id != nil,
        assignment <- classification.assignments,
        vehicle = vehicle(assignment),
        Map.has_key?(values, vehicle),
        do: {top_id, vehicle, assignment.weight}
  end

  defp vehicle(%{security_id: nil, account_id: id}), do: {:account, id}
  defp vehicle(%{security_id: id}), do: {:security, id}

  # The children of the root, by rank.
  defp top_levels(classifications) do
    roots = for %{parent_id: nil, id: id} <- classifications, into: MapSet.new(), do: id

    classifications
    |> Enum.filter(&MapSet.member?(roots, &1.parent_id))
    |> Enum.sort_by(&{&1.rank, &1.id})
  end

  # The top-level classification of each one below it, itself included, as `%{id => top-level
  # id}`; it walks down from the root, so a broken parent never loops.
  defp top_level_ids(classifications) do
    children = Enum.group_by(classifications, & &1.parent_id)

    for top <- top_levels(classifications),
        classification <- [top | descendants(top, children)],
        into: %{},
        do: {classification.id, top.id}
  end

  defp descendants(classification, children) do
    children
    |> Map.get(classification.id, [])
    |> Enum.flat_map(&[&1 | descendants(&1, children)])
  end

  defp values_by_top_level(assignments, values) do
    Enum.reduce(assignments, %{}, fn {top_id, vehicle, weight}, by_top_level ->
      part = part(values[vehicle], weight)
      Map.update(by_top_level, top_id, part, &Decimal.add(&1, part))
    end)
  end

  # The part of each value its assignments leave, as PP counts it: none when assigned 100 % or
  # more.
  defp unassigned_value(values, assignments) do
    weights =
      Enum.group_by(assignments, fn {_, vehicle, _} -> vehicle end, fn {_, _, weight} ->
        weight
      end)

    values
    |> Enum.map(fn {vehicle, value} ->
      assigned = weights |> Map.get(vehicle, []) |> Enum.sum()
      part(value, max(@full_weight - assigned, 0))
    end)
    |> sum()
  end

  defp rows(top_levels, classified, total) do
    if Decimal.gt?(total, 0) do
      for top <- top_levels,
          value = Map.get(classified, top.id, Decimal.new(0)),
          not (Decimal.eq?(value, 0) and top.weight == 0),
          do: row(top, Decimal.div(value, total))
    else
      []
    end
  end

  defp row(classification, share) do
    target = Decimal.div(classification.weight, @full_weight)

    %{
      classification: classification,
      share: share,
      target: target,
      deviation: deviation(Decimal.sub(share, target))
    }
  end

  defp deviation(difference) do
    cond do
      Decimal.gt?(difference, @tolerance) -> :above
      Decimal.lt?(difference, Decimal.negate(@tolerance)) -> :below
      true -> nil
    end
  end

  defp unassigned(value, whole) do
    case value |> Decimal.round(0) |> Decimal.to_integer() do
      0 -> nil
      cents -> %{value: cents, share: if(Decimal.gt?(whole, 0), do: Decimal.div(value, whole))}
    end
  end

  defp part(value, weight), do: value |> Decimal.mult(weight) |> Decimal.div(@full_weight)

  defp sum(decimals), do: Enum.reduce(decimals, Decimal.new(0), &Decimal.add/2)
end
