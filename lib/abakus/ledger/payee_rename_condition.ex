defmodule Abakus.Ledger.PayeeRenameCondition do
  @moduledoc """
  One condition of a payee's rename rule: a payee name it matches (`operator` and `text`, ignoring case) is
  renamed to the payee. A payee's conditions are kept in order (`position`).
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Ledger.Payee

  schema "payee_rename_conditions" do
    field :position, :integer, default: 0
    field :operator, Ecto.Enum, values: [:contains, :is, :starts_with, :ends_with]
    field :text, :string

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :payee, Payee

    timestamps()
  end

  def changeset(condition, attrs) do
    condition
    |> cast(attrs, [:payee_id, :position, :operator, :text])
    |> validate_required([:user_id, :payee_id, :operator, :text])
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
