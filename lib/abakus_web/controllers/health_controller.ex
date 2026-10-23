defmodule AbakusWeb.HealthController do
  @moduledoc false
  use AbakusWeb, :controller

  require Logger

  alias Abakus.BankSync
  alias Abakus.Users.Scope

  # Down, too, while a bank connection has failed for more than a day, so that monitoring notices.
  def show(conn, _params) do
    case check() do
      :ok ->
        json(conn, %{status: "up"})

      {:error, reason} ->
        Logger.error("Health check failed: " <> reason)

        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "down"})
    end
  end

  defp check do
    with {:ok, _result} <- Abakus.Repo.query("SELECT 1"),
         false <- BankSync.failing?(Scope.system()) do
      :ok
    else
      {:error, error} -> {:error, Exception.message(error)}
      true -> {:error, "a bank connection has had no successful fetch for more than a day"}
    end
  end
end
