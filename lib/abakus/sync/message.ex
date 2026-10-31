defmodule Abakus.Sync.Message do
  @moduledoc """
  One change of one field: the user, the row by table and id, the column, its new value as JSON, the clock and the
  device that wrote it. The id numbers the messages in order of arrival and is the cursor a device reads after.
  """

  use Ecto.Schema

  schema "sync_messages" do
    field :user_id, :id
    field :table, :string
    field :row_id, :string
    field :column, :string
    field :value, :string
    field :clock, :string
    field :device, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
