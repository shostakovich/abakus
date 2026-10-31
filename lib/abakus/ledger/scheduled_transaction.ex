defmodule Abakus.Ledger.ScheduledTransaction do
  @moduledoc """
  A transaction the Ledger enters on its next date, as often as its frequency says (`Abakus.Ledger.Scheduled`).
  Twice a month it falls on `first_day` and `second_day`, in either order, and without two days it is monthly; a day
  past the end of a month, also in a monthly or yearly step, stands for the month's last day. A split has subtransactions instead of a category, and a
  transfer payee makes it a transfer.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Amount
  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Account, Payee, ScheduledSubtransaction}

  @frequencies [
    :once,
    :daily,
    :weekly,
    :every_other_week,
    :twice_a_month,
    :every_4_weeks,
    :monthly,
    :every_other_month,
    :every_3_months,
    :every_4_months,
    :twice_a_year,
    :yearly,
    :every_other_year
  ]

  @days [daily: 1, weekly: 7, every_other_week: 14, every_4_weeks: 28]
  @months [
    monthly: 1,
    every_other_month: 2,
    every_3_months: 3,
    every_4_months: 4,
    twice_a_year: 6
  ]
  @years [yearly: 1, every_other_year: 2]

  schema "scheduled_transactions" do
    field :next_date, :date
    field :frequency, Ecto.Enum, values: @frequencies
    field :first_day, :integer
    field :second_day, :integer
    field :amount, :integer
    field :memo, :string
    field :cleared, Ecto.Enum, values: [:uncleared, :cleared], default: :uncleared
    field :deleted_at, :utc_datetime_usec

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :account, Account
    belongs_to :payee, Payee
    belongs_to :category, Category

    has_many :subtransactions, ScheduledSubtransaction,
      where: [deleted_at: nil],
      on_replace: :delete,
      preload_order: [asc: :position, asc: :id]

    timestamps()
  end

  def frequencies, do: @frequencies

  def changeset(scheduled, attrs) do
    scheduled
    |> cast(attrs, [
      :account_id,
      :next_date,
      :frequency,
      :first_day,
      :second_day,
      :payee_id,
      :category_id,
      :memo,
      :amount,
      :cleared
    ])
    |> validate_required([:user_id, :account_id, :next_date, :frequency, :amount, :cleared])
    |> Amount.validate()
    |> validate_days()
    |> cast_assoc(:subtransactions, with: &ScheduledSubtransaction.changeset/3)
    |> validate_split()
  end

  defp validate_days(changeset) do
    if get_field(changeset, :frequency) == :twice_a_month do
      changeset
      |> validate_required([:first_day, :second_day])
      |> validate_number(:first_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 30)
      |> validate_number(:second_day, less_than_or_equal_to: 31)
      |> validate_second_day()
    else
      changeset |> put_change(:first_day, nil) |> put_change(:second_day, nil)
    end
  end

  defp validate_second_day(changeset) do
    with first when is_integer(first) <- get_field(changeset, :first_day),
         second when is_integer(second) and second <= first <- get_field(changeset, :second_day) do
      add_error(changeset, :second_day, "muss nach dem ersten Tag liegen")
    else
      _ordered -> changeset
    end
  end

  defp validate_split(changeset) do
    case get_assoc(changeset, :subtransactions)
         |> Enum.reject(&(&1.action in [:replace, :delete])) do
      [] ->
        changeset

      [_one] ->
        add_error(changeset, :subtransactions, "braucht mindestens zwei Teile")

      parts ->
        changeset
        |> validate_split_sum(parts)
        |> validate_no_category()
    end
  end

  defp validate_split_sum(changeset, parts) do
    amounts = Enum.map(parts, &get_field(&1, :amount))
    amount = get_field(changeset, :amount)

    if is_integer(amount) and Enum.all?(amounts, &is_integer/1) and Enum.sum(amounts) != amount,
      do: add_error(changeset, :amount, "muss der Summe der Teile entsprechen"),
      else: changeset
  end

  defp validate_no_category(changeset) do
    if get_field(changeset, :category_id),
      do: add_error(changeset, :category_id, "muss bei einer Aufteilung leer sein"),
      else: changeset
  end

  @doc "The date of the occurrence after `next_date`; nil for one that happens once."
  def following(%__MODULE__{frequency: :once}), do: nil

  def following(%__MODULE__{frequency: :twice_a_month, next_date: date} = scheduled) do
    case days(scheduled) do
      [first, _second] = days ->
        this_month = Enum.map(days, &on_day(date, &1))

        case Enum.find(this_month, &Date.after?(&1, date)) do
          nil -> date |> Date.beginning_of_month() |> Date.shift(month: 1) |> on_day(first)
          later -> later
        end

      _fewer ->
        following(%{scheduled | frequency: :monthly})
    end
  end

  def following(%__MODULE__{frequency: frequency, next_date: date}) do
    cond do
      days = @days[frequency] -> Date.add(date, days)
      months = @months[frequency] -> Date.shift(date, month: months)
      years = @years[frequency] -> Date.shift(date, year: years)
    end
  end

  # Messages merged field by field may leave the days missing or out of order.
  defp days(scheduled) do
    [scheduled.first_day, scheduled.second_day]
    |> Enum.filter(&(is_integer(&1) and &1 in 1..31))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp on_day(date, day), do: %{date | day: min(day, Date.days_in_month(date))}
end
