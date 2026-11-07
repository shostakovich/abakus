defmodule Abakus.Paperless do
  @moduledoc """
  Each user's connection to their own Paperless-ngx (ADR 0016), kept in their settings and used by every area that
  reads or files documents there.
  """

  import Ecto.Query

  alias Abakus.Paperless.Connection
  alias Abakus.Repo
  alias Abakus.Users.Scope

  @doc "The user's connection, unsaved and empty when they have none."
  def get_connection(%Scope{user: user}),
    do: Repo.get_by(Connection, user_id: user.id) || %Connection{user_id: user.id}

  @doc "Whether the connection has a URL and token to reach Paperless with."
  def connected?(%Connection{url: url, token: token}), do: url != nil and token != nil

  @doc "The form of the user's connection."
  def change_connection(%Connection{} = connection, attrs \\ %{}),
    do: Connection.changeset(connection, attrs)

  @doc "Sets the user's Paperless URL and API token, see `Connection.changeset/2`."
  def update_connection(%Scope{} = scope, attrs) do
    scope
    |> get_connection()
    |> Connection.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Forgets the user's Paperless."
  def disconnect(%Scope{user: user}) do
    Repo.delete_all(from c in Connection, where: c.user_id == ^user.id)
    {:ok, %Connection{user_id: user.id}}
  end
end
