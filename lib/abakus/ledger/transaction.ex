defmodule Abakus.Ledger.Transaction do
  @moduledoc """
  A booking in an account; the amount is signed (negative = outflow). A transaction is a transfer when its payee
  is a transfer payee. The Ledger keeps both sides of a transfer and their pointers: `transfer_transaction_id`
  points to the other transaction, `transfer_subtransaction_id` (on the counterpart of a split's transfer) to the
  subtransaction it belongs to. A split transaction has subtransactions instead of a category.

  A transaction with `matched_transaction_id` is a match proposal: an import that looks like that existing
  transaction. It counts nowhere until the match is accepted (merged into the existing one) or rejected.

  A transaction entered from a scheduled transaction records it and the date of the occurrence
  (`scheduled_transaction_id`, `scheduled_date`); its id is named after them (`Abakus.Ids.entered_transaction/2`).

  A transaction another area writes and leads refers to its source: the Kasse expense (`kasse_expense_id`) or the
  Depot transaction (`depot_transaction_id`), set on create or once later (`Abakus.Ledger.lead/3`); see `led_by/1`.
  The field `led_by` names that area for the devices, which do not see the references.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Amount
  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Account, Payee, Subtransaction, TransactionOrigin}

  schema "transactions" do
    field :date, :date
    field :amount, :integer
    field :memo, :string
    field :cleared, Ecto.Enum, values: [:uncleared, :cleared, :reconciled], default: :uncleared
    field :approved, :boolean, default: false

    field :source, Ecto.Enum,
      values: [:manual, :ynab, :file, :bank, :api, :kasse, :depot, :scheduled],
      default: :manual

    field :deleted_at, :utc_datetime_usec
    field :scheduled_date, :date
    field :kasse_expense_id, :id
    field :depot_transaction_id, :id
    field :led_by, Ecto.Enum, values: [:kasse, :depot]

    # The category of the counterpart when it is the budget side of a transfer from a tracking account.
    field :counterpart_category_id, Ecto.UUID, virtual: true

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :account, Account
    belongs_to :payee, Payee
    belongs_to :category, Category
    belongs_to :transfer_transaction, __MODULE__
    belongs_to :transfer_subtransaction, Subtransaction
    belongs_to :matched_transaction, __MODULE__
    belongs_to :scheduled_transaction, Abakus.Ledger.ScheduledTransaction

    has_many :subtransactions, Subtransaction,
      where: [deleted_at: nil],
      on_replace: :delete,
      preload_order: [asc: :position, asc: :id]

    has_many :origins, TransactionOrigin

    timestamps()
  end

  @fields [
    :account_id,
    :date,
    :amount,
    :payee_id,
    :category_id,
    :counterpart_category_id,
    :memo,
    :cleared,
    :approved
  ]

  # Where a transaction came from and what it proposes to match are set once, on create.
  @create_fields [:source, :matched_transaction_id]

  # The counterpart of a subtransaction follows its split; these are changed there.
  @split_owned [:account_id, :date, :amount, :payee_id, :memo, :subtransactions]

  @doc """
  Changeset for the transaction and its subtransactions. The rules that need the accounts involved are
  `validate_accounts/4`.
  """
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, @fields ++ create_fields(transaction))
    |> validate_required([:user_id, :account_id, :date, :amount, :cleared, :approved, :source])
    |> Amount.validate()
    |> cast_assoc(:subtransactions, with: &Subtransaction.changeset/3)
    |> validate_split()
    |> validate_not_deleted()
    |> validate_split_counterpart()
    |> unique_constraint(:matched_transaction_id)
    |> unique_references()
  end

  @doc "Changeset that puts the reference to a source as `led_by/1` gives it on a transaction."
  def reference_changeset(transaction, led_by),
    do: transaction |> change(source_reference(led_by)) |> unique_references()

  defp unique_references(changeset) do
    changeset
    |> unique_constraint(:kasse_expense_id, name: :transactions_kasse_expense_id_user_id_index)
    |> unique_constraint(:depot_transaction_id)
  end

  @doc "The source that leads the transaction itself, `{:kasse_expense, id}` or `{:depot_transaction, id}`; nil for none."
  def led_by(%__MODULE__{kasse_expense_id: id}) when not is_nil(id), do: {:kasse_expense, id}

  def led_by(%__MODULE__{depot_transaction_id: id}) when not is_nil(id),
    do: {:depot_transaction, id}

  def led_by(%__MODULE__{}), do: nil

  @doc "The reference to a source as `led_by/1` gives it, with its area as `led_by`."
  def source_reference({:kasse_expense, id}), do: %{kasse_expense_id: id, led_by: :kasse}
  def source_reference({:depot_transaction, id}), do: %{depot_transaction_id: id, led_by: :depot}

  defp create_fields(transaction) do
    if Ecto.get_meta(transaction, :state) == :built, do: @create_fields, else: []
  end

  @doc "The subtransactions the transaction has after the changeset, as changesets."
  def subtransactions(changeset) do
    changeset
    |> get_assoc(:subtransactions)
    |> Enum.reject(&(&1.action in [:replace, :delete]))
  end

  @doc """
  Takes the subtransactions the changeset removes out of it, so they are deleted as tombstones instead:
  `{changeset, removed_ids}`.
  """
  def take_removed_subtransactions(changeset) do
    case get_change(changeset, :subtransactions) do
      nil ->
        {changeset, []}

      subtransactions ->
        {removed, kept} = Enum.split_with(subtransactions, &(&1.action in [:replace, :delete]))

        {%{changeset | changes: Map.put(changeset.changes, :subtransactions, kept)},
         Enum.map(removed, & &1.data.id)}
    end
  end

  @doc "Applies `fun` to the changed subtransactions that stay, keeping the parent's `valid?` in step."
  def update_subtransactions(changeset, fun) do
    case get_change(changeset, :subtransactions) do
      nil ->
        changeset

      subtransactions ->
        subtransactions =
          Enum.map(subtransactions, &if(&1.action in [:replace, :delete], do: &1, else: fun.(&1)))

        %{
          changeset
          | changes: Map.put(changeset.changes, :subtransactions, subtransactions),
            valid?: changeset.valid? and Enum.all?(subtransactions, & &1.valid?)
        }
    end
  end

  defp validate_split(changeset) do
    case subtransactions(changeset) do
      [] ->
        changeset

      subtransactions ->
        changeset
        |> validate_split_size(subtransactions)
        |> validate_split_sum(subtransactions)
        |> validate_blank(:category_id, "muss bei einer Aufteilung leer sein")
        |> validate_blank(:counterpart_category_id, "muss bei einer Aufteilung leer sein")
    end
  end

  defp validate_split_size(changeset, [_]),
    do: add_error(changeset, :subtransactions, "braucht mindestens zwei Teile")

  defp validate_split_size(changeset, _subtransactions), do: changeset

  defp validate_split_sum(changeset, subtransactions) do
    amounts = Enum.map(subtransactions, &get_field(&1, :amount))
    amount = get_field(changeset, :amount)

    if is_integer(amount) and Enum.all?(amounts, &is_integer/1) and Enum.sum(amounts) != amount,
      do: add_error(changeset, :amount, "muss der Summe der Teile entsprechen"),
      else: changeset
  end

  defp validate_not_deleted(%{data: %{deleted_at: nil}} = changeset), do: changeset

  defp validate_not_deleted(changeset),
    do: add_error(changeset, :deleted_at, "Die Buchung ist gelöscht")

  defp validate_split_counterpart(%{data: %{transfer_subtransaction_id: nil}} = changeset),
    do: changeset

  defp validate_split_counterpart(changeset) do
    Enum.reduce(@split_owned, changeset, fn field, changeset ->
      if Map.has_key?(changeset.changes, field),
        do: add_error(changeset, field, "wird in der Aufteilung geändert"),
        else: changeset
    end)
  end

  @doc """
  The rules that need the accounts involved. `account` is the transaction's account, `transfer_accounts` maps
  transfer payee ids to their accounts (at least those the transaction and its subtransactions use), and
  `counterpart_categories` maps the ids of existing counterparts to their category ids.

  - No transfer to the own account, and a split is no transfer as a whole (its subtransactions may be).
  - Tracking accounts have no categories; a transfer between budget accounts has none; a transfer between a budget
    and a tracking account has one on the budget side. When that is the counterpart, `counterpart_category_id`
    gives it, needed until the counterpart has one.

  For a split the rules apply to each subtransaction; when the subtransactions are unchanged (the account
  changed), their errors go to the split's `subtransactions`.
  """
  def validate_accounts(
        changeset,
        %Account{} = account,
        transfer_accounts,
        counterpart_categories \\ %{}
      ) do
    rules = &validate_side(&1, account, transfer_accounts, counterpart_categories)

    case subtransactions(changeset) do
      [] ->
        rules.(changeset)

      subtransactions ->
        changeset
        |> validate_split_payee(transfer_accounts)
        |> validate_subtransactions(subtransactions, rules)
    end
  end

  defp validate_split_payee(changeset, transfer_accounts) do
    if Map.has_key?(transfer_accounts, get_field(changeset, :payee_id)),
      do: add_error(changeset, :payee_id, "darf bei einer Aufteilung keine Umbuchung sein"),
      else: changeset
  end

  defp validate_subtransactions(changeset, subtransactions, rules) do
    if get_change(changeset, :subtransactions) do
      update_subtransactions(changeset, rules)
    else
      errors =
        for s <- subtransactions, {_field, error} <- rules.(s).errors, uniq: true, do: error

      Enum.reduce(errors, changeset, fn {message, opts}, changeset ->
        add_error(changeset, :subtransactions, message, opts)
      end)
    end
  end

  defp validate_side(changeset, account, transfer_accounts, counterpart_categories) do
    other = Map.get(transfer_accounts, get_field(changeset, :payee_id))
    existing = Map.get(counterpart_categories, get_field(changeset, :transfer_transaction_id))

    changeset
    |> validate_not_own_account(account, other)
    |> validate_category(account, other)
    |> validate_counterpart_category(account, other, existing)
  end

  defp validate_not_own_account(changeset, %Account{id: id}, %Account{id: id}),
    do: add_error(changeset, :payee_id, "darf nicht das eigene Konto sein")

  defp validate_not_own_account(changeset, _account, _other), do: changeset

  defp validate_category(changeset, account, other) do
    cond do
      not Account.budget_account?(account) ->
        validate_blank(changeset, :category_id, "muss in einem Tracking-Konto leer sein")

      not Account.takes_category?(account, other) ->
        validate_blank(
          changeset,
          :category_id,
          "muss bei einer Umbuchung zwischen Budget-Konten leer sein"
        )

      other ->
        validate_present(
          changeset,
          :category_id,
          "muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"
        )

      true ->
        changeset
    end
  end

  # A split's counterpart gets its own category directly; its subtransaction is the other side.
  defp validate_counterpart_category(
         %{data: %__MODULE__{transfer_subtransaction_id: id}} = changeset,
         _account,
         _other,
         _existing
       )
       when not is_nil(id),
       do: validate_blank(changeset, :counterpart_category_id, "muss leer sein")

  defp validate_counterpart_category(changeset, account, other, existing) do
    cond do
      not counterpart_on_budget_side?(account, other) ->
        validate_blank(changeset, :counterpart_category_id, "muss leer sein")

      is_nil(existing) ->
        validate_required(changeset, :counterpart_category_id)

      true ->
        changeset
    end
  end

  defp counterpart_on_budget_side?(_account, nil), do: false

  defp counterpart_on_budget_side?(account, other), do: Account.takes_category?(other, account)

  defp validate_blank(changeset, field, message) do
    if is_nil(get_field(changeset, field)),
      do: changeset,
      else: add_error(changeset, field, message)
  end

  defp validate_present(changeset, field, message) do
    if is_nil(get_field(changeset, field)),
      do: add_error(changeset, field, message),
      else: changeset
  end
end
