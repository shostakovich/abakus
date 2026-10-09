defmodule Abakus.Categories.CategoryGroup do
  @moduledoc "A group of categories in the budget. Internal groups hold Ready to Assign and are not listed."

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Categories.Category

  schema "category_groups" do
    field :name, :string
    field :hidden, :boolean, default: false
    field :internal, :boolean, default: false
    field :position, :integer, default: 0
    field :note, :string

    has_many :categories, Category

    timestamps()
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :hidden, :position, :note])
    |> validate_required([:name])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_not_internal()
  end

  defp validate_not_internal(%{data: %{internal: true}} = changeset),
    do: add_error(changeset, :internal, "kann nicht geändert werden")

  defp validate_not_internal(changeset), do: changeset
end
