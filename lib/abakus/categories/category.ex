defmodule Abakus.Categories.Category do
  @moduledoc """
  An envelope in the budget. Categories are hidden, never deleted, so history keeps its references. Internal
  categories (Ready to Assign) come from a migration and cannot be changed.
  """

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Categories.{CategoryGroup, TargetVersion}
  alias Abakus.Names

  @ready_to_assign "Inflow: Ready to Assign"

  schema "categories" do
    field :name, :string
    field :lookup_key, :string
    field :hidden, :boolean, default: false
    field :internal, :boolean, default: false
    field :position, :integer, default: 0
    field :note, :string

    belongs_to :category_group, CategoryGroup
    has_many :target_versions, TargetVersion

    timestamps()
  end

  @doc "Changeset for a category; `category_group_id` moves it to another group."
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :hidden, :position, :note, :category_group_id])
    |> validate_required([:name, :category_group_id])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_not_internal()
    |> Names.put_lookup_key()
    |> validate_not_reserved()
  end

  @doc "The internal category's name, as in YNAB. No other category can take its lookup key."
  def ready_to_assign_name, do: @ready_to_assign

  defp validate_not_reserved(changeset) do
    if get_change(changeset, :lookup_key) == Names.lookup_key(@ready_to_assign),
      do: add_error(changeset, :name, "ist für „Zu verteilen“ reserviert"),
      else: changeset
  end

  defp validate_not_internal(%{data: %{internal: true}} = changeset),
    do: add_error(changeset, :internal, "kann nicht geändert werden")

  defp validate_not_internal(changeset), do: changeset
end
