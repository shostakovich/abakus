defmodule Abakus.Ids do
  @moduledoc """
  Ids of the Ledger's and the budget's rows (ADR 0025), made as `sync/PROTOCOL.md` describes: a new row gets a
  UUIDv7, a row with a natural key a UUIDv5 named after that key, so every writer makes the same one. Ids are
  lowercase UUID text.
  """

  @namespace "1d70d95f-102c-4115-966f-5db73210e37c"

  @doc "The namespace of the name-based ids."
  def namespace, do: @namespace

  @doc "A new id, later than every id this node made before."
  def generate, do: Ecto.UUID.generate(version: 7, precision: :monotonic)

  @doc "An id as a client sends it, in lowercase, or `:error` when it is no UUID."
  def cast(id) when is_binary(id) and byte_size(id) == 36, do: Ecto.UUID.cast(id)
  def cast(_id), do: :error

  @doc "The assignment of a category in a month."
  def assignment(category_id, %Date{} = month), do: named(["assignment", category_id, month])

  @doc "The snooze of a category's target in a month."
  def target_snooze(category_id, %Date{} = month),
    do: named(["target_snooze", category_id, month])

  @doc "The version of a category's target from its first month."
  def target_version(category_id, %Date{} = from_month),
    do: named(["target_version", category_id, from_month])

  @doc "The transfer payee of an account."
  def transfer_payee(account_id), do: named(["transfer_payee", account_id])

  @doc "The transaction a scheduled transaction's occurrence on `date` is entered as."
  def entered_transaction(scheduled_transaction_id, %Date{} = date),
    do: named(["entered_transaction", scheduled_transaction_id, date])

  @doc "The UUIDv5 of the parts joined by slashes in the namespace (RFC 9562)."
  def named(parts) do
    name = Enum.map_join(parts, "/", &part/1)
    {:ok, namespace} = Ecto.UUID.dump(@namespace)

    <<a::48, _version::4, b::12, _variant::2, c::62, _rest::32>> =
      :crypto.hash(:sha, namespace <> name)

    Ecto.UUID.cast!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end

  defp part(%Date{} = date), do: Date.to_iso8601(date)
  defp part(text) when is_binary(text), do: text
end
