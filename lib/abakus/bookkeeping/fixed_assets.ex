defmodule Abakus.Bookkeeping.FixedAssets do
  @moduledoc """
  The user's asset register: their fixed assets (`Abakus.Bookkeeping.FixedAsset`) and how they left it
  (`Abakus.Bookkeeping.Disposal`).

  Proposed as the payment of a sale are the business accounts' incoming transactions of exactly its amount, from a
  month before to a month after it, that are no transfer, pay nothing else yet
  (`Abakus.Bookkeeping.claimed_transactions/2`) and lie in no locked period. A trade-in moves no money and has none.

  A disposal in a period locked by a return sent from Abakus (`Abakus.Bookkeeping.Filings`) can no longer change, be
  taken back or go with its asset, nor can a payment in a locked period be linked to a sale or unlinked from it,
  since its tax line would count again or no more. Nor can an asset change, come or go where that changes what it
  counts for in a year whose EÜR was sent from Abakus.
  """

  import Ecto.Changeset
  import Ecto.Query
  import Abakus.Owned

  alias Abakus.{Bookkeeping, Ids, Repo}
  alias Abakus.Bookkeeping.{Disposal, Filings, FixedAsset, IncomeStatement}
  alias Abakus.Users.Scope

  @preloads [disposal: [transaction: :payee]]

  @doc "The user's fixed assets with their disposals, the latest purchase first."
  def list(%Scope{} = scope),
    do:
      Repo.all(
        from a in owned(FixedAsset, scope),
          order_by: [desc: a.purchased_on, desc: a.id],
          preload: ^@preloads
      )

  def get(%Scope{} = scope, id) do
    case Ids.cast(id) do
      {:ok, id} ->
        Repo.one(from a in owned(FixedAsset, scope), where: a.id == ^id, preload: ^@preloads)

      :error ->
        nil
    end
  end

  def change(%FixedAsset{} = asset, attrs \\ %{}), do: FixedAsset.changeset(asset, attrs)

  def create(%Scope{} = scope, attrs) do
    changeset =
      %FixedAsset{user_id: user_id(scope)}
      |> FixedAsset.changeset(attrs)
      |> validate_euer_unchanged(scope, nil)

    with {:ok, asset} <- Repo.insert(changeset) do
      {:ok, Repo.preload(asset, @preloads)}
    end
  end

  @doc "Changes the asset; a disposal it has can no longer come before its purchase."
  def update(%Scope{} = scope, %FixedAsset{} = asset, attrs) do
    asset = scope |> own!(asset) |> Repo.preload(:disposal)

    changeset =
      asset
      |> FixedAsset.changeset(attrs)
      |> validate_disposal_after()
      |> validate_euer_unchanged(scope, asset)

    with {:ok, asset} <- Repo.update(changeset) do
      {:ok, Repo.preload(asset, @preloads, force: true)}
    end
  end

  defp validate_disposal_after(changeset) do
    purchased_on = get_field(changeset, :purchased_on)

    case changeset.data.disposal do
      %Disposal{date: date} when purchased_on != nil ->
        if Date.before?(date, purchased_on),
          do: add_error(changeset, :purchased_on, "liegt nach dem Abgang"),
          else: changeset

      _none ->
        changeset
    end
  end

  defp validate_euer_unchanged(%{valid?: false} = changeset, _scope, _before), do: changeset

  defp validate_euer_unchanged(changeset, scope, before) do
    changed = changeset |> apply_changes() |> Map.put(:disposal, before && before.disposal)

    if euer_changed?(scope, before, changed),
      do: add_error(changeset, :purchased_on, Filings.locked_message()),
      else: changeset
  end

  defp euer_changed?(scope, before, changed),
    do: Enum.any?(Filings.euer_years(scope), &(counted(before, &1) != counted(changed, &1)))

  defp counted(nil, _year), do: %{}
  defp counted(asset, year), do: IncomeStatement.asset_kennzahlen(asset, year)

  @doc """
  Deletes the asset with its disposal; `{:error, :locked}` while the disposal is in a locked period or the asset
  counts in a sent EÜR.
  """
  def delete(%Scope{} = scope, %FixedAsset{} = asset) do
    asset = scope |> own!(asset) |> Repo.preload(:disposal, force: true)

    if locked_disposal?(scope, asset.disposal) or euer_changed?(scope, asset, nil),
      do: {:error, :locked},
      else: Repo.delete(asset, allow_stale: true)
  end

  def change_disposal(%FixedAsset{} = asset, attrs \\ %{}),
    do: Disposal.changeset(asset.disposal || %Disposal{}, attrs, asset.purchased_on)

  @doc """
  Records how the asset left the register, or changes how it did; a payment it names must be one of its proposals
  (`payment_proposals/2`).
  """
  def record_disposal(%Scope{} = scope, %FixedAsset{} = asset, attrs) do
    asset = scope |> own!(asset) |> Repo.preload(:disposal)

    changeset =
      (asset.disposal || %Disposal{user_id: user_id(scope), fixed_asset_id: asset.id})
      |> Disposal.changeset(attrs, asset.purchased_on)
      |> validate_payment(scope)
      |> validate_unlocked(scope)
      |> validate_payment_unlocked(scope)
      |> validate_disposal_euer_unchanged(scope, asset)

    with {:ok, _disposal} <- Repo.insert_or_update(changeset) do
      {:ok, Repo.preload(asset, @preloads, force: true)}
    end
  end

  defp validate_payment(changeset, scope) do
    case get_field(changeset, :transaction_id) do
      nil ->
        changeset

      id ->
        if changeset.valid? and
             Enum.any?(payment_proposals(scope, apply_changes(changeset)), &(&1.id == id)),
           do: changeset,
           else: add_error(changeset, :transaction_id, "passt nicht zum Verkauf")
    end
  end

  defp validate_unlocked(%{changes: changes} = changeset, _scope) when changes == %{},
    do: changeset

  defp validate_unlocked(changeset, scope) do
    dates = [changeset.data.date, get_field(changeset, :date)]

    if Enum.any?(dates, &(&1 && Filings.register_locked?(scope, &1))),
      do: add_error(changeset, :date, Filings.locked_message()),
      else: changeset
  end

  defp validate_disposal_euer_unchanged(%{valid?: false} = changeset, _scope, _asset),
    do: changeset

  defp validate_disposal_euer_unchanged(changeset, scope, asset) do
    if euer_changed?(scope, asset, %{asset | disposal: apply_changes(changeset)}),
      do: add_error(changeset, :date, Filings.locked_message()),
      else: changeset
  end

  defp validate_payment_unlocked(changeset, scope) do
    {before, now} = {changeset.data.transaction_id, get_field(changeset, :transaction_id)}

    if before != now and (payment_locked?(scope, before) or payment_locked?(scope, now)),
      do: add_error(changeset, :transaction_id, Filings.locked_message()),
      else: changeset
  end

  defp payment_locked?(_scope, nil), do: false

  defp payment_locked?(scope, transaction_id) do
    case Bookkeeping.get_transaction(scope, transaction_id) do
      nil -> false
      transaction -> Filings.locked?(scope, transaction.date)
    end
  end

  @doc """
  Takes the disposal back: the asset is in the register again. `{:error, :locked}` while the disposal or its payment
  is in a locked period, or taking it back changes a sent EÜR.
  """
  def remove_disposal(%Scope{} = scope, %FixedAsset{} = asset) do
    asset = scope |> own!(asset) |> Repo.preload(:disposal, force: true)

    if locked_disposal?(scope, asset.disposal) or
         euer_changed?(scope, asset, %{asset | disposal: nil}) do
      {:error, :locked}
    else
      Repo.delete_all(from d in owned(Disposal, scope), where: d.fixed_asset_id == ^asset.id)
      {:ok, Repo.preload(asset, @preloads, force: true)}
    end
  end

  defp locked_disposal?(_scope, nil), do: false

  defp locked_disposal?(scope, %Disposal{} = disposal),
    do:
      Filings.register_locked?(scope, disposal.date) or
        payment_locked?(scope, disposal.transaction_id)

  @doc """
  The transactions proposed as the payment of a sale, with their payees, the earliest first; the payment the sale
  names stays among them in a locked period.
  """
  def payment_proposals(%Scope{} = scope, %Disposal{kind: :sale, date: %Date{} = date} = disposal)
      when is_integer(disposal.amount) and disposal.amount > 0 do
    Repo.all(
      from t in Bookkeeping.business_transactions(scope),
        where: t.amount == ^disposal.amount,
        where: t.date >= ^Date.shift(date, month: -1) and t.date <= ^Date.shift(date, month: 1),
        where: is_nil(t.transfer_transaction_id) and is_nil(t.transfer_subtransaction_id),
        where: t.id not in subquery(Bookkeeping.claimed_transactions(scope, disposal.id)),
        where: ^unlocked_or(scope, disposal.transaction_id),
        order_by: [asc: t.date, asc: t.id],
        preload: :payee
    )
  end

  def payment_proposals(%Scope{}, %Disposal{}), do: []

  defp unlocked_or(scope, nil), do: dynamic(not (^Filings.locked_date(scope)))

  defp unlocked_or(scope, transaction_id),
    do: dynamic([t], not (^Filings.locked_date(scope)) or t.id == ^transaction_id)

  @doc "The disposals from `first` to `last` as entries of `Abakus.Bookkeeping.VatReturn`, each on its own date."
  def disposal_entries(%Scope{} = scope, %Date{} = first, %Date{} = last) do
    Repo.all(
      from d in owned(Disposal, scope),
        where: d.date >= ^first and d.date <= ^last,
        select: %{date: d.date, vat: d.vat, amount: d.amount}
    )
    |> Enum.map(&Map.put(&1, :category, :disposal))
  end
end
