defmodule Abakus.YnabImport do
  @moduledoc """
  The import from YNAB (docs/SPEC.md, "YNAB import"): fetches a plan's export with a personal access token,
  replaces the whole budget with it (docs/adr/0002-ynab-reimport-replaces.md) and checks Abakus's numbers against
  YNAB's. Data Abakus cannot represent stops it before anything is written (`Unsupported`); so does any
  transaction that did not come from YNAB, as the budget then holds data of its own.
  """

  import Ecto.Query

  alias Abakus.Ledger.Transaction
  alias Abakus.Repo
  alias Abakus.YnabImport.{Check, Client, Loader, Report, Unsupported}

  @doc "The personal access token from `YNAB_TOKEN`."
  def token do
    case System.get_env("YNAB_TOKEN") do
      token when token in [nil, ""] -> {:error, :no_token}
      token -> {:ok, token}
    end
  end

  @doc "Fetches the plan `plan_id`, or the token's only plan, and imports it."
  def run(token, plan_id \\ nil) do
    with {:ok, id} <- plan_id(token, plan_id),
         {:ok, plan} <- Client.plan(token, id) do
      import_plan(plan)
    end
  end

  defp plan_id(_token, id) when is_binary(id) and id != "", do: {:ok, id}

  defp plan_id(token, nil) do
    case Client.plans(token) do
      {:ok, [%{"id" => id}]} -> {:ok, id}
      {:ok, []} -> {:error, :no_plans}
      {:ok, plans} -> {:error, {:choose_plan, Enum.map(plans, &{&1["id"], &1["name"]})}}
      error -> error
    end
  end

  defp plan_id(_token, _id), do: {:error, :bad_plan_id}

  @doc "Replaces the budget with the plan (an export's `data.plan`) and checks it; returns a `Report`."
  def import_plan(plan) do
    case Unsupported.problems(plan) do
      [] -> replace(plan)
      problems -> {:error, {:unsupported, problems}}
    end
  end

  defp replace(plan) do
    with {:ok, loaded} <- Repo.transact(fn -> load(plan) end) do
      {:ok,
       %Report{
         plan: plan["name"],
         counts: loaded.counts,
         merged_payees: loaded.merged_payees,
         differences: Check.differences(plan, loaded)
       }}
    end
  rescue
    error in Loader.WriteError -> {:error, {:not_written, error.message}}
  end

  defp load(plan) do
    if Repo.exists?(from t in Transaction, where: t.source != :ynab) do
      {:error, :own_data}
    else
      Loader.wipe()
      {:ok, Loader.load(plan)}
    end
  end

  @doc "Why an import did not run, as lines for the operator."
  def error_lines(:own_data),
    do: [
      "Abakus holds transactions that did not come from YNAB; an import would delete them, so it stops."
    ]

  def error_lines({:unsupported, problems}),
    do: [
      "The plan holds data Abakus cannot represent; nothing was imported:"
      | Enum.map(problems, &("  " <> &1))
    ]

  def error_lines({:choose_plan, plans}),
    do: [
      "The token sees several plans; pass the id of one:"
      | Enum.map(plans, fn {id, name} -> "  #{id}  #{name}" end)
    ]

  def error_lines({:not_written, message}),
    do: ["Abakus refused part of the plan, so the budget stays as it was: #{message}"]

  def error_lines(:no_plans), do: ["The token sees no plans."]

  def error_lines(:bad_plan_id),
    do: [~s{Pass the plan's id as a string, such as import_ynab("…").}]

  def error_lines(:no_token),
    do: ["YNAB_TOKEN is not set; create a personal access token in YNAB's settings."]

  def error_lines({:ynab, status, detail}), do: ["YNAB answered #{status}: #{detail}"]
  def error_lines({:ynab, reason}), do: ["Could not reach YNAB: #{inspect(reason)}"]
end
