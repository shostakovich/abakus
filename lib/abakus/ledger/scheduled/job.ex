defmodule Abakus.Ledger.Scheduled.Job do
  @moduledoc """
  Enters the budget owner's due scheduled transactions at 00:05 local time and at boot (`Abakus.Ledger.Scheduled`);
  entering is idempotent, so a run at boot never doubles one. Without a budget owner it does nothing.
  """

  alias Abakus.{DailyJob, LocalTime}
  alias Abakus.Ledger.Scheduled
  alias Abakus.Users.Scope

  def child_spec(_opts),
    do:
      DailyJob.child_spec(
        name: __MODULE__,
        at: ~T[00:05:00],
        run: &run/0,
        at_boot?: fn -> true end
      )

  @doc "One run; `{:error, reasons}` when a scheduled transaction was refused."
  def run do
    with %Scope{} = scope <- Scope.for_budget_owner(),
         {:error, _entered, reasons} <- Scheduled.enter_due(scope, LocalTime.today()) do
      {:error, Enum.join(reasons, "; ")}
    else
      _done -> :ok
    end
  end
end
