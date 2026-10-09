defmodule Abakus.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Abakus.Repo,
      {Phoenix.PubSub, name: Abakus.PubSub},
      Abakus.RateLimit,
      Abakus.WebAuthn.Challenges,
      # Sends sign-in links in the background; a flood of requests is dropped.
      {Task.Supervisor, name: Abakus.TaskSupervisor, max_children: 50},
      AbakusWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Abakus.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AbakusWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
