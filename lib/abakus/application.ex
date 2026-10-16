defmodule Abakus.Application do
  @moduledoc false

  use Application

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
        AbakusWeb.Endpoint
      ] ++ jobs()

    Supervisor.start_link(children, strategy: :one_for_one, name: Abakus.Supervisor)
  end

  defp jobs do
    if Application.fetch_env!(:abakus, :jobs),
      do: [
        Abakus.Kasse.Fx.RefreshJob,
        Abakus.Kasse.Recurring.Job,
        Abakus.Backup.Job,
        Abakus.Kasse.Ynab.Scheduler,
        Abakus.Depot.MarketData.Job
      ],
      else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    AbakusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
