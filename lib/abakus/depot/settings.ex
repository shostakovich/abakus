defmodule Abakus.Depot.Settings do
  @moduledoc "Each user's settings of the Depot: the benchmark they compare their portfolios with."

  import Ecto.Query, warn: false

  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Settings.Setting
  alias Abakus.Repo
  alias Abakus.Users.Scope

  @doc "The user's settings, unsaved defaults when they have none yet."
  def get_settings(%Scope{user: user}),
    do: Repo.get_by(Setting, user_id: user.id) || %Setting{user_id: user.id}

  @doc "The id of the user's benchmark, nil for none."
  def benchmark_id(%Scope{} = scope), do: get_settings(scope).benchmark_id

  @doc "Picks the security with `security_id` as the user's benchmark, nil for none."
  def update_benchmark(%Scope{} = scope, security_id) do
    # SQLite names no constraint that fails, so the security is looked up beforehand.
    security? = &Repo.exists?(from s in Security, where: s.id == ^&1)

    scope
    |> get_settings()
    |> Setting.benchmark_changeset(%{benchmark_id: security_id}, security?)
    |> Repo.insert_or_update()
  end
end
