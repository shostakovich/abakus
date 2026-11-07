defmodule Abakus.Bookkeeping.FixedAssets do
  @moduledoc """
  The user's asset register: their fixed assets (`Abakus.Bookkeeping.FixedAsset`) and how they left it
  (`Abakus.Bookkeeping.Disposal`).

  Proposed as the payment of a sale are the business accounts' incoming transactions of exactly its amount, from a
  month before to a month after it, that are no transfer and pay no invoice or other disposal. A trade-in moves no
  money and has none.
  """

  import Ecto.Changeset
  import Ecto.Query
  import Abakus.Owned

  alias Abakus.{Bookkeeping, Ids, Repo}
  alias Abakus.Bookkeeping.{Disposal, FixedAsset, InvoicePayment}
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
    with {:ok, asset} <-
           %FixedAsset{user_id: user_id(scope)} |> FixedAsset.changeset(attrs) |> Repo.insert() do
      {:ok, Repo.preload(asset, @preloads)}
    end
  end

  @doc "Changes the asset; a disposal it has can no longer come before its purchase."
  def update(%Scope{} = scope, %FixedAsset{} = asset, attrs) do
    changeset = scope |> own!(asset) |> FixedAsset.changeset(attrs) |> validate_disposal_after()

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

  def delete(%Scope{} = scope, %FixedAsset{} = asset),
    do: scope |> own!(asset) |> Repo.delete(allow_stale: true)

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

  @doc "Takes the disposal back: the asset is in the register again."
  def remove_disposal(%Scope{} = scope, %FixedAsset{} = asset) do
    asset = own!(scope, asset)
    Repo.delete_all(from d in owned(Disposal, scope), where: d.fixed_asset_id == ^asset.id)
    {:ok, Repo.preload(asset, @preloads, force: true)}
  end

  @doc "The transactions proposed as the payment of a sale, with their payees, the earliest first."
  def payment_proposals(%Scope{} = scope, %Disposal{kind: :sale, date: %Date{} = date} = disposal)
      when is_integer(disposal.amount) and disposal.amount > 0 do
    Repo.all(
      from t in Bookkeeping.business_transactions(scope),
        where: t.amount == ^disposal.amount,
        where: t.date >= ^Date.shift(date, month: -1) and t.date <= ^Date.shift(date, month: 1),
        where: is_nil(t.transfer_transaction_id) and is_nil(t.transfer_subtransaction_id),
        where:
          t.id not in subquery(from p in owned(InvoicePayment, scope), select: p.transaction_id),
        where: t.id not in subquery(other_payments(scope, disposal)),
        order_by: [asc: t.date, asc: t.id],
        preload: :payee
    )
  end

  def payment_proposals(%Scope{}, %Disposal{}), do: []

  defp other_payments(scope, %Disposal{id: id}) do
    query =
      from d in owned(Disposal, scope),
        where: not is_nil(d.transaction_id),
        select: d.transaction_id

    if id, do: where(query, [d], d.id != ^id), else: query
  end

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
