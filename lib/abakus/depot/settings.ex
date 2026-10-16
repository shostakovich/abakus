defmodule Abakus.Depot.Settings do
  @moduledoc """
  Each user's settings of the Depot: the benchmark they compare their portfolios with and the Paperless their
  receipts come from.
  """

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

  @doc "The form of the user's Paperless."
  def change_paperless(%Setting{} = setting, attrs \\ %{}),
    do: Setting.paperless_changeset(setting, attrs)

  @doc """
  Sets the user's Paperless URL, API token and tag, see `Setting.paperless_changeset/2`; another URL or tag has
  not been polled yet.
  """
  def update_paperless(%Scope{} = scope, attrs) do
    changeset = scope |> get_settings() |> Setting.paperless_changeset(attrs)

    if Ecto.Changeset.changed?(changeset, :paperless_url) or
         Ecto.Changeset.changed?(changeset, :paperless_tag),
       do:
         changeset
         |> Ecto.Changeset.put_change(:paperless_polled_at, nil)
         |> Repo.insert_or_update(),
       else: Repo.insert_or_update(changeset)
  end

  @doc "Forgets the user's Paperless."
  def disconnect_paperless(%Scope{} = scope) do
    scope
    |> get_settings()
    |> Ecto.Changeset.change(
      paperless_url: nil,
      paperless_token: nil,
      paperless_tag: nil,
      paperless_polled_at: nil
    )
    |> Repo.insert_or_update()
  end

  @doc "The settings of the users who have entered a Paperless, for polling it."
  def list_paperless do
    Repo.all(
      from s in Setting,
        where:
          not is_nil(s.paperless_url) and not is_nil(s.paperless_token) and
            not is_nil(s.paperless_tag),
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
