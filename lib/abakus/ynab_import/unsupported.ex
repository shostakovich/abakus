defmodule Abakus.YnabImport.Unsupported do
  @moduledoc """
  What in a YNAB plan Abakus cannot represent, found before anything is written: accounts other than checking,
  savings and cash in the budget (no credit cards or loans), targets other than "needed for spending" monthly,
  yearly or by a date without repeat, amounts that are not whole cents, and transactions that refer to something
  deleted or internal.
  """

  alias Abakus.YnabImport.{Plan, Targets}

  @budget_types ["checking", "savings", "cash"]
  @never ["creditCard", "lineOfCredit"]

  @doc "The problems as sentences, each once, in the plan's order; empty when the plan can be imported."
  def problems(plan) do
    Enum.uniq(accounts(plan) ++ targets(plan) ++ assignments(plan) ++ transactions(plan))
  end

  defp accounts(plan) do
    for %{"type" => type} = account <- Plan.accounts(plan),
        type in @never or (account["on_budget"] == true and type not in @budget_types),
        do: "Account “#{account["name"]}” is of type #{type}."
  end

  defp targets(plan) do
    for {_month, category} <- Plan.regular_category_months(plan),
        problem = target_problem(category),
        do: "Category “#{category["name"]}” #{problem}."
  end

  defp target_problem(%{"goal_type" => nil}), do: nil
  defp target_problem(%{"goal_type" => "NEED"} = category), do: need_problem(category)
  defp target_problem(%{"goal_type" => type}), do: "has a target of type #{type}"
  defp target_problem(_category), do: nil

  defp need_problem(category) do
    amount = category["goal_target"]
    cadence = Targets.cadence(category)

    cond do
      cadence == nil ->
        "has a target that repeats neither monthly nor yearly"

      cadence in [:yearly, :once] and is_nil(Targets.due_on(category)) ->
        "has a target by a date without a due date"

      not Plan.whole_cents?(amount) or amount <= 0 ->
        "has a target of #{Plan.format(amount)}, which is not a positive amount in whole cents"

      true ->
        nil
    end
  end

  defp assignments(plan) do
    for {month, %{"budgeted" => budgeted} = category} <- Plan.regular_category_months(plan),
        not Plan.whole_cents?(budgeted),
        do:
          "Category “#{category["name"]}” has an assignment in #{Calendar.strftime(month, "%Y-%m")} " <>
            "that is not whole cents: #{Plan.format(budgeted)}."
  end

  defp transactions(plan) do
    known = %{
      accounts: ids(Plan.accounts(plan)),
      payees: ids(Plan.payees(plan)),
      categories: ids(Enum.reject(Plan.categories(plan), &(Plan.role(&1) == :internal)))
    }

    parts = Plan.subtransactions(plan)

    Enum.flat_map(Plan.transactions(plan), fn transaction ->
      own = Map.get(parts, transaction["id"], [])
      name = "transaction #{transaction["id"]} on #{transaction["date"]}"

      problems(transaction, String.capitalize(name, :ascii), known, own != []) ++
        single_part(own, String.capitalize(name, :ascii)) ++
        Enum.flat_map(own, &problems(&1, "A part of #{name}", known, false))
    end)
  end

  # The Ledger needs two parts; YNAB keeps a split whose other parts were deleted.
  defp single_part([_part], name), do: ["#{name} is a split with a single part."]
  defp single_part(_parts, _name), do: []

  # A split's own category is YNAB's internal "Split", which Abakus leaves blank.
  defp problems(record, name, known, split?) do
    [
      not Plan.whole_cents?(record["amount"]) &&
        "#{name} has an amount that is not whole cents: #{Plan.format(record["amount"])}.",
      unknown?(record["account_id"], known.accounts) &&
        "#{name} is in an account that was deleted.",
      unknown?(record["payee_id"], known.payees) && "#{name} has a payee that was deleted.",
      (not split? and unknown?(record["category_id"], known.categories)) &&
        "#{name} has a category that was deleted or is internal."
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp unknown?(nil, _known), do: false
  defp unknown?(id, known), do: not MapSet.member?(known, id)

  defp ids(records), do: MapSet.new(records, & &1["id"])
end
