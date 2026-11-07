defmodule Abakus.Paperless.Connection do
  @moduledoc "A user's Paperless-ngx: its URL and API token, one row per user."

  use Abakus.Schema

  import Ecto.Changeset

  schema "paperless_connections" do
    belongs_to :user, Abakus.Users.User

    field :url, :string
    field :token, :string, redact: true

    timestamps()
  end

  @doc """
  URL and API token, both required; a blank token keeps the one stored, unless the URL changes, so a token never
  goes to another server.
  """
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:url, :token])
    |> keep_stored_token()
    |> update_change(:url, &(&1 && &1 |> String.trim() |> String.trim_trailing("/")))
    |> update_change(:token, &String.trim/1)
    |> validate_required([:url, :token])
    |> validate_token_for_new_url()
    |> validate_length(:url, max: 200)
    |> validate_length(:token, max: 200)
    |> validate_change(:url, fn :url, url ->
      case URI.new(url) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _other ->
          [url: "braucht http:// oder https:// und einen Host"]
      end
    end)
  end

  defp keep_stored_token(changeset) do
    if Map.has_key?(changeset.changes, :token) and get_change(changeset, :token) == nil,
      do: delete_change(changeset, :token),
      else: changeset
  end

  defp validate_token_for_new_url(changeset) do
    if changeset.data.token && get_change(changeset, :url) && !token_given?(changeset.params),
      do: add_error(changeset, :token, "bitte für die neue URL eingeben"),
      else: changeset
  end

  defp token_given?(%{"token" => token}) when is_binary(token), do: String.trim(token) != ""
  defp token_given?(_params), do: false
end
