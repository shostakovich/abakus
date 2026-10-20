defmodule Abakus.BankSync.Job do
  @moduledoc """
  Fetches every bank connection at 06:00 and 18:00 local time as the budget owner (`Abakus.BankSync.fetch_all/1`),
  well within the four unattended fetches a day a bank allows. Without bank sync set up or a budget owner it does
  nothing; a failed fetch is logged and waits for the next run.
  """

  alias Abakus.{BankSync, DailyJob}
  alias Abakus.Users.Scope

  def child_spec(_opts),
    do: DailyJob.child_spec(name: __MODULE__, at: [~T[06:00:00], ~T[18:00:00]], run: &run/0)

  @doc "One run: every connection's fetch; `{:error, reasons}` when one failed."
  def run do
    with true <- BankSync.available?(),
         %Scope{} = scope <- Scope.for_budget_owner() do
      scope |> BankSync.fetch_all() |> report()
    else
      _nothing_to_do -> :ok
    end
  end

  defp report(results) do
    case for(
           {connection, {:error, message}} <- results,
           do: "#{connection.bank_name}: #{message}"
         ) do
      [] -> :ok
      errors -> {:error, Enum.join(errors, "; ")}
    end
  end
end
