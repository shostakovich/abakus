defmodule Abakus.Depot.Settings.Setting do
  @moduledoc "A user's settings of the Depot, one row per user."

  use Abakus.Schema

  import Ecto.Changeset

  schema "depot_settings" do
    belongs_to :user, Abakus.Users.User
    # The security the user compares their portfolios with, nil for none.
    belongs_to :benchmark, Abakus.Depot.Securities.Security

    timestamps()
  end

  @doc "A changeset for the benchmark; `security?` says whether a security id exists."
  def benchmark_changeset(setting, attrs, security?) do
    setting
    |> cast(attrs, [:benchmark_id])
    |> validate_change(:benchmark_id, fn :benchmark_id, id ->
      if security?.(id), do: [], else: [benchmark_id: "ist kein Wertpapier"]
    end)
  end
end
