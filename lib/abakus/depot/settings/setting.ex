defmodule Abakus.Depot.Settings.Setting do
  @moduledoc "A user's settings of the Depot, one row per user."

  use Abakus.Schema

  import Ecto.Changeset

  schema "depot_settings" do
    belongs_to :user, Abakus.Users.User
    belongs_to :benchmark, Abakus.Depot.Securities.Security

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

  @doc "A changeset for the tag of the documents the Depot takes from the user's Paperless; blank for none."
  def paperless_tag_changeset(setting, attrs) do
    setting
    |> cast(attrs, [:paperless_tag])
    |> update_change(:paperless_tag, &(&1 && String.trim(&1)))
    |> validate_length(:paperless_tag, max: 100)
  end
end
