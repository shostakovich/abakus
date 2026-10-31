defmodule Abakus.Sync.Tables do
  @moduledoc """
  The synced tables (`sync/PROTOCOL.md`), parents before their parts. A table syncs every column of its schema but
  the id, the owner, the timestamps, the lookup key the server derives from the name, and what only the server keeps:
  an account's file link and a transaction's references to the Kasse and the Depot. A part has no owner of its own;
  its parent's is its.
  """

  alias Abakus.Categories.{Assignment, Category, CategoryGroup, TargetSnooze, TargetVersion}
  alias Abakus.Ids

  alias Abakus.Ledger.{
    Account,
    Payee,
    PayeeRenameCondition,
    ScheduledSubtransaction,
    ScheduledTransaction,
    Subtransaction,
    Transaction
  }

  @schemas [
    Account,
    Payee,
    PayeeRenameCondition,
    CategoryGroup,
    Category,
    Assignment,
    TargetVersion,
    TargetSnooze,
    ScheduledTransaction,
    ScheduledSubtransaction,
    Transaction,
    Subtransaction
  ]

  @parents %{
    Subtransaction => {Transaction, :transaction_id},
    ScheduledSubtransaction => {ScheduledTransaction, :scheduled_transaction_id}
  }

  @not_synced [:id, :user_id, :inserted_at, :updated_at, :lookup_key]
  @server_only %{
    Account => [:ofx_bank_id, :ofx_acct_id],
    Transaction => [:kasse_expense_id, :depot_transaction_id]
  }

  @doc "The schemas of the synced tables, parents before their parts."
  def schemas, do: @schemas

  @doc "The schema of a synced table by its name, nil for another table."
  def schema(table), do: Enum.find(@schemas, &(table(&1) == table))

  def table(schema), do: schema.__schema__(:source)

  @doc "The synced columns."
  def columns(schema),
    do: schema.__schema__(:fields) -- (@not_synced ++ Map.get(@server_only, schema, []))

  @doc "A row's synced fields as JSON values, by column."
  def values(%schema{} = row), do: Map.new(columns(schema), &{&1, encode(Map.fetch!(row, &1))})

  @doc "The synced column by its name, nil for another one."
  def column(schema, name), do: Enum.find(columns(schema), &(Atom.to_string(&1) == name))

  @doc "The parent schema of a part and the column pointing at it, nil for a table with an owner."
  def parent(schema), do: Map.get(@parents, schema)

  @doc "The parts of a parent schema with the column pointing at the parent."
  def children(schema), do: for({child, {^schema, key}} <- @parents, do: {child, key})

  @doc "The synced schema a column points at, nil for a column that points at none."
  def reference(schema, column) do
    Enum.find_value(schema.__schema__(:associations), fn name ->
      case schema.__schema__(:association, name) do
        %Ecto.Association.BelongsTo{owner_key: ^column, related: related} -> synced(related)
        _other -> nil
      end
    end)
  end

  defp synced(schema), do: if(schema in @schemas, do: schema)

  @doc "A field's value as JSON: dates and moments ISO 8601, enums as text."
  def encode(%Date{} = date), do: Date.to_iso8601(date)
  def encode(%DateTime{} = moment), do: DateTime.to_iso8601(moment)

  def encode(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  def encode(value), do: value

  @doc "A field's value from JSON, as the column's type takes it; `:error` when it does not fit."
  def decode(schema, column, value) do
    case schema.__schema__(:type, column) do
      _type when is_nil(value) -> {:ok, nil}
      Ecto.UUID -> Ids.cast(value)
      :integer when not is_integer(value) -> :error
      :boolean when not is_boolean(value) -> :error
      type -> cast(type, value)
    end
  end

  defp cast(type, value) do
    case Ecto.Type.cast(type, value) do
      {:ok, value} -> {:ok, value}
      _invalid -> :error
    end
  end
end
