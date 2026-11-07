defmodule Abakus.Depot.Settings do
  @moduledoc """
  Each user's settings of the Depot: the benchmark they compare their portfolios with and the tag of the documents
  in their Paperless that are receipts.
  """

  import Ecto.Query, warn: false

  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Settings.Setting
  alias Abakus.Paperless.Connection
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

  @doc "The form of the tag of the user's receipt intake."
  def change_paperless_tag(%Setting{} = setting, attrs \\ %{}),
    do: Setting.paperless_tag_changeset(setting, attrs)

  @doc "Sets the tag of the documents the Depot takes from the user's Paperless; another tag has not been polled yet."
  def update_paperless_tag(%Scope{} = scope, attrs) do
    changeset = scope |> get_settings() |> Setting.paperless_tag_changeset(attrs)

    if Ecto.Changeset.changed?(changeset, :paperless_tag),
      do:
        changeset
        |> Ecto.Changeset.put_change(:paperless_polled_at, nil)
        |> Repo.insert_or_update(),
      else: Repo.insert_or_update(changeset)
  end

  @doc "The settings of the users with a tag and a Paperless connection, for polling it."
  def list_paperless do
    Repo.all(
      from s in Setting,
        join: c in Connection,
        on: c.user_id == s.user_id,
        where: not is_nil(s.paperless_tag),
        order_by: s.user_id,
        preload: :user
    )
  end

  @doc "Notes that the user's Paperless was polled just now."
  def paperless_polled(%Setting{id: id}) do
    {1, _settings} =
      Repo.update_all(from(s in Setting, where: s.id == ^id),
        set: [paperless_polled_at: DateTime.utc_now()]
      )

    :ok
  end
end
