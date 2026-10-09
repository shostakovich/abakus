defmodule Abakus.Ledger.Matches do
  @moduledoc """
  The rules for match proposals, for `Abakus.Ledger`. A proposal is an import with `matched_transaction_id`: in the
  account and with the amount of the existing transaction, which is in the register (not deleted, no proposal
  itself) and not reconciled; one per transaction. Only imports from a file or the bank propose matches. A proposal
  counts nowhere, so it is no transfer and no split. While it is open, account and amount of both sides are fixed.
  """

  import Ecto.Query

  alias Abakus.Ledger.Transaction
  alias Abakus.{References, Repo}
  alias Ecto.Changeset

  @locked "kann bei einem offenen Zuordnungsvorschlag nicht geändert werden"

  @doc "Checks a new proposal's transaction and that an open proposal or its transaction keeps account and amount."
  def validate(changeset) do
    case Changeset.get_change(changeset, :matched_transaction_id) do
      nil -> validate_locked(changeset)
      id -> changeset |> validate_source() |> validate_target(Repo.get(Transaction, id))
    end
  end

  defp validate_source(changeset) do
    if Changeset.get_field(changeset, :source) in [:file, :bank],
      do: changeset,
      else: add_error(changeset, "ist nur bei Importen aus Datei oder Bank möglich")
  end

  @doc "Checks that `target` (nil when missing) can take the proposal in `changeset`."
  def validate_target(changeset, target) do
    cond do
      is_nil(target) or not is_nil(target.deleted_at) ->
        References.not_found(changeset, :matched_transaction_id)

      not is_nil(target.matched_transaction_id) ->
        add_error(changeset, "ist selbst ein Zuordnungsvorschlag")

      target.account_id != Changeset.get_field(changeset, :account_id) ->
        add_error(changeset, "muss im selben Konto sein")

      target.amount != Changeset.get_field(changeset, :amount) ->
        add_error(changeset, "muss denselben Betrag haben")

      target.cleared == :reconciled ->
        add_error(changeset, "ist abgeschlossen")

      true ->
        changeset
    end
  end

  defp add_error(changeset, message),
    do: Changeset.add_error(changeset, :matched_transaction_id, message)

  defp validate_locked(%Changeset{data: %Transaction{id: nil}} = changeset), do: changeset

  defp validate_locked(changeset) do
    case Enum.filter([:account_id, :amount], &Changeset.changed?(changeset, &1)) do
      [] ->
        changeset

      fields ->
        if open?(changeset.data),
          do: Enum.reduce(fields, changeset, &Changeset.add_error(&2, &1, @locked)),
          else: changeset
    end
  end

  defp open?(%Transaction{deleted_at: nil, matched_transaction_id: id}) when not is_nil(id),
    do: true

  defp open?(%Transaction{id: id}), do: pending?(id)

  @doc "Whether an open proposal points at the transaction."
  def pending?(transaction_id) do
    Repo.exists?(
      from t in Transaction,
        where: t.matched_transaction_id == ^transaction_id and is_nil(t.deleted_at)
    )
  end

  @doc "A proposal counts nowhere, so it cannot have counterparts."
  def validate_proposal(changeset, transfer_accounts) do
    cond do
      is_nil(Changeset.get_field(changeset, :matched_transaction_id)) ->
        changeset

      Transaction.subtransactions(changeset) != [] ->
        Changeset.add_error(
          changeset,
          :subtransactions,
          "muss bei einem Zuordnungsvorschlag leer sein"
        )

      Map.has_key?(transfer_accounts, Changeset.get_field(changeset, :payee_id)) ->
        Changeset.add_error(
          changeset,
          :payee_id,
          "darf bei einem Zuordnungsvorschlag keine Umbuchung sein"
        )

      true ->
        changeset
    end
  end

  @doc """
  The changes accepting a proposal makes to the existing transaction: the import's date and cleared state, and its
  category and memo where the existing one has none. A split's counterpart takes date and memo from its split;
  splits and transfers keep their category rule.
  """
  def merged(%Transaction{} = existing, %Transaction{} = proposal) do
    split_counterpart? = not is_nil(existing.transfer_subtransaction_id)

    own_category? =
      existing.subtransactions == [] and is_nil(existing.transfer_transaction_id) and
        not split_counterpart?

    %{cleared: proposal.cleared, approved: true}
    |> put_if(not split_counterpart?, :date, proposal.date)
    |> put_if(not split_counterpart? and blank?(existing.memo), :memo, proposal.memo)
    |> put_if(own_category? and is_nil(existing.category_id), :category_id, proposal.category_id)
  end

  defp put_if(attrs, true, key, value), do: Map.put(attrs, key, value)
  defp put_if(attrs, false, _key, _value), do: attrs

  defp blank?(memo), do: is_nil(memo) or String.trim(memo) == ""
end
