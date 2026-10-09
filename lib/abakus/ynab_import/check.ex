defmodule Abakus.YnabImport.Check do
  @moduledoc """
  Compares Abakus's numbers after an import with YNAB's in the plan: per month Ready to Assign (`to_be_budgeted`),
  per category and month assigned, activity, available and underfunded, per account the balances. Amounts are
  compared in YNAB's milliunits; underfunded is nil for a category without a target.
  """

  alias Abakus.{Budget, Categories, Ledger}
  alias Abakus.YnabImport.Plan

  @doc """
  The differences as `%{where, field, ynab, abakus}`, months first. `ids` maps YNAB ids to Abakus ids: `accounts`,
  and `categories`, where Uncategorized is nil; categories without an id are not checked.
  """
  def differences(plan, ids) do
    month_differences(plan, ids.categories) ++ account_differences(plan, ids.accounts)
  end

  defp month_differences(plan, categories) do
    months = Plan.months(plan)
    from = Plan.date(List.first(months)["month"])
    through = Plan.date(List.last(months)["month"])
    computed = Categories.budget() |> Budget.months(from, through) |> Map.new(&{&1.month, &1})

    Enum.flat_map(months, fn month ->
      abakus = Map.fetch!(computed, Plan.date(month["month"]))
      label = String.slice(month["month"], 0, 7)

      compare(
        label,
        "Ready to Assign",
        month["to_be_budgeted"],
        milliunits(abakus.ready_to_assign)
      ) ++
        Enum.flat_map(month["categories"], &category_differences(&1, abakus, label, categories))
    end)
  end

  defp category_differences(category, month, label, categories) do
    case row(month, Map.fetch(categories, category["id"])) do
      nil ->
        []

      row ->
        where = "#{label} #{category["name"]}"

        compare(where, "assigned", category["budgeted"], milliunits(row.assigned)) ++
          compare(where, "activity", category["activity"], milliunits(row.activity)) ++
          compare(where, "available", category["balance"], milliunits(row.available)) ++
          compare(
            where,
            "underfunded",
            category["goal_under_funded"],
            row.target && milliunits(row.underfunded)
          )
    end
  end

  defp row(month, {:ok, nil}), do: month.uncategorised
  defp row(month, {:ok, id}), do: Enum.find(month.categories, &(&1.category_id == id))
  defp row(_month, :error), do: nil

  defp account_differences(plan, accounts) do
    balances = Ledger.balances()

    Enum.flat_map(Plan.accounts(plan), fn account ->
      abakus = Map.get(balances, accounts[account["id"]], %{balance: 0, cleared: 0, uncleared: 0})

      compare(account["name"], "balance", account["balance"], milliunits(abakus.balance)) ++
        compare(
          account["name"],
          "cleared balance",
          account["cleared_balance"],
          milliunits(abakus.cleared)
        ) ++
        compare(
          account["name"],
          "uncleared balance",
          account["uncleared_balance"],
          milliunits(abakus.uncleared)
        )
    end)
  end

  defp compare(_where, _field, same, same), do: []

  defp compare(where, field, ynab, abakus),
    do: [%{where: where, field: field, ynab: ynab, abakus: abakus}]

  defp milliunits(cents), do: cents * 10
end
