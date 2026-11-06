defmodule Abakus.Ledger.ScheduledTransaction do
  @moduledoc """
  A transaction the Ledger enters on its next date (`Abakus.Ledger.Scheduled`), once or repeating every
  `repeat_every` weeks or months (`repeat_unit`). A monthly step keeps the day of the month, or takes the month's last
  day if it is shorter. A split has subtransactions instead of a category, and a transfer payee makes it a transfer.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Amount
  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Account, Payee, ScheduledSubtransaction, Transaction}

  @units [:week, :month]

  schema "scheduled_transactions" do
    field :next_date, :date
    field :repeat_unit, Ecto.Enum, values: @units
    field :repeat_every, :integer
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

  def changeset(scheduled, attrs) do
    scheduled
    |> cast(attrs, [
      :account_id,
      :next_date,
      :repeat_unit,
      :repeat_every,
      :payee_id,
      :category_id,
      :memo,
      :amount,
      :cleared
    ])
    |> validate_required([:user_id, :account_id, :next_date, :amount, :cleared])
    |> Amount.validate()
    |> validate_repeat()
    |> cast_assoc(:subtransactions, with: &ScheduledSubtransaction.changeset/3)
    |> validate_split()
  end

  defp validate_repeat(changeset) do
    if get_field(changeset, :repeat_unit) do
      changeset
      |> validate_required([:repeat_every])
      |> validate_number(:repeat_every, greater_than_or_equal_to: 1, less_than_or_equal_to: 99)
    else
      put_change(changeset, :repeat_every, nil)
    end
  end

  defp validate_split(changeset) do
    case Transaction.subtransactions(changeset) do
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

  @doc """
  The rules for the accounts involved, so that every occurrence can be entered: `account` is its account and
  `transfer_accounts` maps transfer payee ids to their accounts. No transfer to the own account or to the
  shared-expenses account, whose transactions the Kasse's budget link writes, and a split is no transfer as a whole.
  A budget account's side may have a category, and needs one for a transfer to a tracking account, but has none for
  a transfer to another budget account; a tracking account's has none. A transfer between a tracking and a budget
  account is scheduled in the budget account, which takes its category. A split's rules apply to each part; when
  the parts are unchanged, their errors go to `subtransactions`.
  """
  def validate_accounts(changeset, %Account{} = account, transfer_accounts) do
    Transaction.validate_sides(
      changeset,
      transfer_accounts,
      &validate_side(&1, account, transfer_accounts)
    )
  end

  defp validate_side(changeset, account, transfer_accounts) do
    other = Map.get(transfer_accounts, get_field(changeset, :payee_id))
    category? = not is_nil(get_field(changeset, :category_id))

    case side_error(account, other, category?) do
      nil -> changeset
      {field, message} -> add_error(changeset, field, message)
    end
  end

  defp side_error(%Account{id: id}, %Account{id: id}, _category?),
    do: {:payee_id, "darf nicht das eigene Konto sein"}

  defp side_error(account, other, category?) do
    cond do
      other && other.shared_expenses ->
        {:payee_id, "Das Kasse-Konto nimmt keine geplanten Buchungen an."}

      other && Account.takes_category?(other, account) ->
        {:payee_id, "wird im Budgetkonto geplant"}

      category? ->
        category_error(account, other)

      other && Account.takes_category?(account, other) ->
        {:category_id, "muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"}

      true ->
        nil
    end
  end

  defp category_error(account, other) do
    cond do
      not Account.budget_account?(account) ->
        {:category_id, "muss in einem Tracking-Konto leer sein"}

      not Account.takes_category?(account, other) ->
        {:category_id, "muss bei einer Umbuchung zwischen Budget-Konten leer sein"}

      true ->
        nil
    end
  end

  @doc "The date of the occurrence after `next_date`; nil for one that happens once."
  def following(%__MODULE__{repeat_unit: nil}), do: nil

  def following(%__MODULE__{repeat_unit: :week, repeat_every: every, next_date: date}),
    do: Date.add(date, 7 * (every || 1))

  def following(%__MODULE__{repeat_unit: :month, repeat_every: every, next_date: date}),
    do: Date.shift(date, month: every || 1)

  @doc "The dates of the `count` occurrences after `next_date`, fewer for one that happens once."
  def dates_after(%__MODULE__{} = scheduled, count) do
    scheduled
    |> Stream.unfold(fn scheduled ->
      with %Date{} = date <- following(scheduled), do: {date, %{scheduled | next_date: date}}
    end)
    |> Enum.take(count)
  end

  @doc ~s(How often it happens: `"Einmalig"`, `"Monatlich"`, `"Alle 2 Wochen"`.)
  def repeat_label(%__MODULE__{repeat_unit: unit, repeat_every: every}),
    do: label(unit, every || 1)

  defp label(nil, _every), do: "Einmalig"
  defp label(:week, 1), do: "Wöchentlich"
  defp label(:week, every), do: "Alle #{every} Wochen"
  defp label(:month, 1), do: "Monatlich"
  defp label(:month, 12), do: "Jährlich"
  defp label(:month, every), do: "Alle #{every} Monate"
end
