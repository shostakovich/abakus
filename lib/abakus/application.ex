defmodule Abakus.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Abakus.Repo,
      {Phoenix.PubSub, name: Abakus.PubSub},
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
