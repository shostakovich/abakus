defmodule Abakus.Application do
  @moduledoc false

  use Application

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
        Abakus.Kasse.Fx.Loader,
        Abakus.Kasse.Ynab.Cache,
        Abakus.Depot.Receipts.Recognition,
        AbakusWeb.Endpoint
      ] ++ jobs()

    Supervisor.start_link(children, strategy: :one_for_one, name: Abakus.Supervisor)
  end

  defp jobs do
    if Application.fetch_env!(:abakus, :jobs),
      do: [
        Abakus.ExchangeRates.Job,
        Abakus.Kasse.Fx.RefreshJob,
        Abakus.Kasse.Recurring.Job,
        Abakus.Backup.Job,
        Abakus.Kasse.Ynab.Scheduler,
        Abakus.Depot.MarketData.Job,
        Abakus.Depot.Receipts.PaperlessJob,
        {Task, &Receipts.resume_recognition/0}
      ],
      else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    AbakusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
