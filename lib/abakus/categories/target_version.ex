defmodule Abakus.Categories.TargetVersion do
  @moduledoc """
  A category's target (YNAB's "needed for spending") from `from_month` until the next version: monthly, or by a
  date (`due_on`), which `repeats_yearly` or ends after its month. Changing a target adds a version, so past
  months keep the target they had; cadence `none` ends the target.

  `set_aside` is YNAB's `goal_needs_whole_amount`: true means "set aside another" (assigned this month counts),
  false means "refill up to" (available counts).
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.{Amount, Ids}
  alias Abakus.Categories.Category

  schema "target_versions" do
    field :from_month, :date
    field :cadence, Ecto.Enum, values: [:monthly, :by_date, :none]
    field :amount, :integer
    field :due_on, :date
    field :repeats_yearly, :boolean, default: false
    field :set_aside, :boolean, default: true
    field :deleted_at, :utc_datetime_usec

    belongs_to :category, Category
    belongs_to :user, Abakus.Users.User, type: :id

    timestamps()
  end

  @doc """
  Whether a version sets a target: messages merged field by field may leave one without the amount or the date its
  cadence needs, and that one counts as none.
  """
  def complete?(%{cadence: :monthly, amount: amount}), do: is_integer(amount)

  def complete?(%{cadence: :by_date, amount: amount, due_on: due_on}),
    do: is_integer(amount) and not is_nil(due_on)

  def complete?(_version), do: false

  @doc "A yearly due date moved on by whole years until it is not before `month`; that is the same target."
  def next_due(due_on, month) do
    due_on
    |> Stream.iterate(&Date.shift(&1, year: 1))
    |> Enum.find(&(not Date.before?(&1, month)))
  end

  @doc "Changeset for a target version whose `category_id` and `user_id` are set; any day stands for its month."
  def changeset(version, attrs) do
    version
    |> cast(attrs, [:from_month, :cadence, :amount, :due_on, :repeats_yearly, :set_aside])
    |> update_change(:from_month, &Date.beginning_of_month/1)
    |> validate_required([
      :category_id,
      :user_id,
      :from_month,
      :cadence,
      :repeats_yearly,
      :set_aside
    ])
    |> validate_cadence()
    |> check_constraint(:amount, name: :target_versions_amount_positive)
    |> unique_constraint([:category_id, :from_month])
    |> Ids.put_named_id(:from_month, &Ids.target_version/2)
  end

  defp validate_cadence(changeset) do
    case get_field(changeset, :cadence) do
      :monthly ->
        changeset |> validate_amount() |> validate_blank(:due_on) |> validate_not_repeating()

      :by_date ->
        changeset |> validate_amount() |> validate_required(:due_on) |> validate_due_on()

      :none ->
        changeset
        |> validate_blank(:amount)
        |> validate_blank(:due_on)
        |> validate_not_repeating()

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

  defp validate_not_repeating(changeset) do
    if get_field(changeset, :repeats_yearly) == true,
      do: add_error(changeset, :repeats_yearly, "gibt es nur bei einem Ziel bis zu einem Datum"),
      else: changeset
  end

  defp validate_blank(changeset, field) do
    if is_nil(get_field(changeset, field)),
      do: changeset,
      else: add_error(changeset, field, "muss bei diesem Rhythmus leer sein")
  end
end
