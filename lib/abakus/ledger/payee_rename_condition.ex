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
    field :deleted_at, :utc_datetime_usec

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :payee, Payee

    timestamps()
  end

  def changeset(condition, attrs) do
    condition
    |> cast(attrs, [:payee_id, :position, :operator, :text])
    |> validate_required([:user_id, :payee_id, :operator, :text])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_length(:text, max: 200)
  end

  @doc "Whether a text leaves a condition blank: empty or whitespace only."
  def blank?(text), do: String.trim(text || "") == ""

  @doc "Whether the condition matches the payee name, ignoring case; a blank condition matches none."
  def matches?(%__MODULE__{operator: operator, text: text}, name) when is_binary(name),
    do: not blank?(text) and compare(operator, fold(name), fold(text))

  defp compare(:contains, name, text), do: String.contains?(name, text)
  defp compare(:is, name, text), do: name == text
  defp compare(:starts_with, name, text), do: String.starts_with?(name, text)
  defp compare(:ends_with, name, text), do: String.ends_with?(name, text)

  @doc "Whether two conditions say the same: one operator and a text that differs at most in case."
  def equivalent?(%__MODULE__{} = one, %__MODULE__{} = other),
    do: one.operator == other.operator and fold(one.text) == fold(other.text)

  defp fold(text), do: text |> :unicode.characters_to_nfc_binary() |> String.downcase()
end
