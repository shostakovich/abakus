defmodule Abakus.YnabImport.Plan do
  @moduledoc """
  Reads YNAB's plan export (`GET /plans/{id}`, its `data.plan`) as the import needs it, without deleted entities.
  Amounts in the export are milliunits.

  What the export shows, beyond YNAB's documentation: every category group is marked internal, so only
  categories tell internal from regular; a split's parent carries an internal "Split" category the export does not
  list; a split's transfer part has no id of its counterpart, which only names the split's account.
  """

  @ready_to_assign "Inflow: Ready to Assign"
  @uncategorized "Uncategorized"

  def accounts(plan), do: live(plan, "accounts")

  def payees(plan), do: live(plan, "payees")

  def category_groups(plan), do: live(plan, "category_groups")

  def categories(plan), do: live(plan, "categories")

  @doc "The categories that become categories in Abakus: neither internal nor deleted."
  def regular_categories(plan), do: Enum.filter(categories(plan), &(role(&1) == :regular))

  @doc "What a category is to Abakus: `:ready_to_assign`, `:uncategorised`, `:internal` (left out) or `:regular`."
  def role(%{"internal" => true, "name" => @ready_to_assign}), do: :ready_to_assign
  def role(%{"internal" => true, "name" => @uncategorized}), do: :uncategorised
  def role(%{"internal" => true}), do: :internal
  def role(_category), do: :regular

  @doc "The months, oldest first."
  def months(plan), do: plan |> live("months") |> Enum.sort_by(& &1["month"])

  @doc "The regular categories' records in each month as `{month, category}`, oldest month first."
  def regular_category_months(plan) do
    regular = MapSet.new(regular_categories(plan), & &1["id"])

    for month <- months(plan),
        %{"id" => id} = category <- month["categories"],
        MapSet.member?(regular, id),
        do: {date(month["month"]), category}
  end

  @doc "The transactions by date, in the export's order within a day."
  def transactions(plan), do: plan |> live("transactions") |> Enum.sort_by(& &1["date"])

  @doc "The subtransactions by their transaction's id, in the export's order."
  def subtransactions(plan),
    do: plan |> live("subtransactions") |> Enum.group_by(& &1["transaction_id"])

  @doc "Whether a transaction is the counterpart of a split's transfer part, which the export does not link."
  def part_counterpart?(transaction),
    do:
      not is_nil(transaction["transfer_account_id"]) and
        is_nil(transaction["transfer_transaction_id"])

  def whole_cents?(milliunits), do: is_integer(milliunits) and rem(milliunits, 10) == 0

  def cents(milliunits) when is_integer(milliunits) and rem(milliunits, 10) == 0,
    do: div(milliunits, 10)

  @doc "A date or the date part of a timestamp."
  def date(nil), do: nil
  def date(value), do: value |> String.slice(0, 10) |> Date.from_iso8601!()

  @doc "Milliunits as euros with two decimals, three when they are not whole cents."
  def format(nil), do: "none"

  def format(milliunits) do
    sign = if milliunits < 0, do: "-", else: ""
    euros = div(abs(milliunits), 1000)
    rest = rem(abs(milliunits), 1000)

    decimals =
      if rem(rest, 10) == 0,
        do: rest |> div(10) |> Integer.to_string() |> String.pad_leading(2, "0"),
        else: rest |> Integer.to_string() |> String.pad_leading(3, "0")

    "#{sign}#{euros}.#{decimals}"
  end

  defp live(plan, key), do: plan |> Map.get(key, []) |> Enum.reject(& &1["deleted"])
end
