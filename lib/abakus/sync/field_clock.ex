defmodule Abakus.Sync.FieldClock do
  @moduledoc "The clock of a field's current value; a message changes the field only with a newer clock."

  use Ecto.Schema

  @primary_key false
  schema "sync_field_clocks" do
    field :table, :string, primary_key: true
    field :row_id, :string, primary_key: true
    field :column, :string, primary_key: true
    field :clock, :string
  end
end
