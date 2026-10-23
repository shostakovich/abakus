defmodule Abakus.Depot.Settings.Setting do
  @moduledoc "A user's settings of the Depot, one row per user."

  use Abakus.Schema

  import Ecto.Changeset

  schema "depot_settings" do
    belongs_to :user, Abakus.Users.User
    belongs_to :benchmark, Abakus.Depot.Securities.Security

    field :paperless_url, :string
    field :paperless_token, :string, redact: true
    field :paperless_tag, :string
    field :paperless_polled_at, :utc_datetime_usec

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

  @doc """
  A changeset for the user's Paperless: URL, API token and tag, all required; a blank token
  keeps the one stored, unless the URL changes, so a token never goes to another server.
  """
  def paperless_changeset(setting, attrs) do
    attrs = keep_blank_token(attrs)

    setting
    |> cast(attrs, [:paperless_url, :paperless_token, :paperless_tag])
    |> update_change(:paperless_url, &(&1 |> String.trim() |> String.trim_trailing("/")))
    |> update_change(:paperless_tag, &String.trim/1)
    |> update_change(:paperless_token, &String.trim/1)
    |> validate_required([:paperless_url, :paperless_token, :paperless_tag])
    |> validate_token_for_new_url(
      Enum.any?(attrs, &(to_string(elem(&1, 0)) == "paperless_token"))
    )
    |> validate_length(:paperless_url, max: 200)
    |> validate_length(:paperless_tag, max: 100)
    |> validate_length(:paperless_token, max: 200)
    |> validate_change(:paperless_url, fn :paperless_url, url ->
      case URI.new(url) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _other ->
          [paperless_url: "braucht http:// oder https:// und einen Host"]
      end
    end)
  end

  defp validate_token_for_new_url(changeset, token_given?) do
    if changeset.data.paperless_token && get_change(changeset, :paperless_url) && !token_given?,
      do: add_error(changeset, :paperless_token, "bitte für die neue URL eingeben"),
      else: changeset
  end

  defp keep_blank_token(attrs) do
    Map.reject(attrs, fn {key, value} ->
      to_string(key) == "paperless_token" and String.trim(value || "") == ""
    end)
  end

  @doc "Whether the user has entered a Paperless to poll."
  def paperless?(%__MODULE__{} = setting),
    do:
      setting.paperless_url != nil and setting.paperless_token != nil and
        setting.paperless_tag != nil
end
