defmodule Abakus.Categories.TargetVersion do
  @moduledoc """
  A category's target (YNAB's "needed for spending") from `from_month` until the next version. Changing a target
  adds a version, so past months keep the target they had; cadence `none` ends the target.

  `set_aside` is YNAB's `goal_needs_whole_amount`: true means "set aside another" (assigned this month counts),
  false means "refill up to" (available counts).
  """

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Amount
  alias Abakus.Categories.Category

  schema "target_versions" do
    field :from_month, :date
    field :cadence, Ecto.Enum, values: [:monthly, :yearly, :none]
    field :amount, :integer
    field :due_on, :date
    field :set_aside, :boolean, default: true

    belongs_to :category, Category

    timestamps()
  end

  @doc "Changeset for a target version whose `category_id` is set; any day stands for its month."
  def changeset(version, attrs) do
    version
    |> cast(attrs, [:from_month, :cadence, :amount, :due_on, :set_aside])
    |> update_change(:from_month, &Date.beginning_of_month/1)
    |> validate_required([:category_id, :from_month, :cadence, :set_aside])
    |> validate_cadence()
    |> check_constraint(:amount, name: :target_versions_amount_positive)
    |> unique_constraint([:category_id, :from_month])
  end

  defp validate_cadence(changeset) do
    case get_field(changeset, :cadence) do
      :monthly ->
        changeset |> validate_amount() |> validate_blank(:due_on)

      :yearly ->
        changeset |> validate_amount() |> validate_required(:due_on) |> validate_due_on()

      :none ->
        changeset |> validate_blank(:amount) |> validate_blank(:due_on)

      nil ->
        changeset
    end
  end

  defp validate_amount(changeset) do
    changeset
    |> validate_required(:amount)
    |> validate_number(:amount, greater_than: 0)
    |> Amount.validate()
  end

  defp validate_due_on(changeset) do
    from_month = get_field(changeset, :from_month)
    due_on = get_field(changeset, :due_on)

    if from_month && due_on && Date.before?(due_on, from_month),
      do: add_error(changeset, :due_on, "darf nicht vor dem Beginn des Ziels liegen"),
      else: changeset
  end

  defp validate_blank(changeset, field) do
    if is_nil(get_field(changeset, field)),
      do: changeset,
      else: add_error(changeset, field, "muss bei diesem Rhythmus leer sein")
  end
end
