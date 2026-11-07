defmodule Abakus.Application do
  @moduledoc false

  use Application

  alias Abakus.Bookkeeping.Filings
  alias Abakus.Depot.Receipts

  @impl true
  def start(_type, _args) do
    children =
      [
        Abakus.Repo,
        {Phoenix.PubSub, name: Abakus.PubSub},
        Abakus.RateLimit,
        Abakus.WebAuthn.Challenges,
        # Sends sign-in links in the background; a flood of requests is dropped.
        {Task.Supervisor, name: Abakus.TaskSupervisor, max_children: 50},
        {Task.Supervisor, name: Abakus.Depot.TaskSupervisor},
        # Sends returns to ELSTER apart from the page, so that closing it does not stop a send.
        {Task.Supervisor, name: Abakus.Bookkeeping.TaskSupervisor},
        Abakus.Depot.Receipts.Recognition,
        AbakusWeb.Endpoint
      ] ++ jobs()

    Supervisor.start_link(children, strategy: :one_for_one, name: Abakus.Supervisor)
  end

  @doc false
  def jobs(enabled? \\ Application.fetch_env!(:abakus, :jobs)) do
    if enabled?,
      do: [
        Abakus.ExchangeRates.Job,
        Abakus.Kasse.Recurring.Job,
        Abakus.Backup.Job,
        Abakus.Depot.MarketData.Job,
        Abakus.Depot.Receipts.PaperlessJob,
        Abakus.BankSync.Job,
        Abakus.Ledger.Scheduled.Job,
        Supervisor.child_spec({Task, &Receipts.resume_recognition/0}, id: :resume_recognition),
        Supervisor.child_spec({Task, &Filings.release_interrupted/0}, id: :release_interrupted)
      ],
      else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    AbakusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
