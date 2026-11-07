defmodule Abakus.Bookkeeping.FixedAssetsTest do
  use Abakus.DataCase

  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures

  alias Abakus.{Bookkeeping, UsersFixtures}
  alias Abakus.Bookkeeping.{Disposal, FixedAssets, LexofficeReceipt}
  alias Abakus.Users.Scope

  setup do
    scope = budget_scope()
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    %{scope: scope, kontist: kontist}
  end

  test "needs a useful life above the low-value limit", %{scope: scope} do
    assert {:error, changeset} =
             FixedAssets.create(scope, %{
               "name" => "Notebook",
               "purchased_on" => "2027-04-10",
               "net" => "800,01"
             })

    assert errors_on(changeset) == %{useful_life: ["can't be blank"]}

    assert {:ok, asset} =
             FixedAssets.create(scope, %{
               "name" => " Monitor ",
               "purchased_on" => "2027-04-10",
               "net" => "800"
             })

    assert %{name: "Monitor", net: 80_000, useful_life: nil, disposal: nil} = asset
  end

  test "refuses a disposal before the purchase, and a purchase after the disposal", %{
    scope: scope
  } do
    asset = fixed_asset_fixture(scope, %{"purchased_on" => "2025-03-01"})

    assert {:error, changeset} =
             FixedAssets.record_disposal(scope, asset, %{
               "kind" => "sale",
               "date" => "2025-02-28",
               "amount" => "100",
               "vat" => "19"
             })

    assert errors_on(changeset) == %{date: ["liegt vor der Anschaffung"]}

    asset = disposal_fixture(scope, asset, %{"date" => "2027-01-20"})

    assert {:error, changeset} =
             FixedAssets.update(scope, asset, %{"purchased_on" => "2027-02-01"})

    assert errors_on(changeset) == %{purchased_on: ["liegt nach dem Abgang"]}
  end

  test "proposes incoming business transactions of the sale's amount as its payment", c do
    asset = fixed_asset_fixture(c.scope, %{"purchased_on" => "2025-03-01"})
    other = fixed_asset_fixture(c.scope, %{"purchased_on" => "2025-03-01"})

    early = transaction_fixture(account_id: c.kontist.id, date: ~D[2026-12-20], amount: 23_800)
    late = transaction_fixture(account_id: c.kontist.id, date: ~D[2027-02-20], amount: 23_800)
    transaction_fixture(account_id: c.kontist.id, date: ~D[2026-12-19], amount: 23_800)
    transaction_fixture(account_id: c.kontist.id, date: ~D[2027-01-21], amount: 23_900)
    transaction_fixture(date: ~D[2027-01-21], amount: 23_800)

    sale = %Disposal{kind: :sale, date: ~D[2027-01-20], amount: 23_800, vat: :rate_19}
    assert Enum.map(FixedAssets.payment_proposals(c.scope, sale), & &1.id) == [early.id, late.id]
    assert FixedAssets.payment_proposals(c.scope, %{sale | kind: :withdrawal}) == []

    asset = disposal_fixture(c.scope, asset, %{"transaction_id" => early.id})
    assert asset.disposal.transaction.id == early.id
    assert Enum.map(FixedAssets.payment_proposals(c.scope, sale), & &1.id) == [late.id]

    assert Enum.map(FixedAssets.payment_proposals(c.scope, asset.disposal), & &1.id) ==
             [early.id, late.id]

    assert {:error, changeset} =
             FixedAssets.record_disposal(c.scope, other, %{
               "kind" => "sale",
               "date" => "2027-01-20",
               "amount" => "238",
               "vat" => "19",
               "transaction_id" => early.id
             })

    assert errors_on(changeset) == %{transaction_id: ["passt nicht zum Verkauf"]}
  end

  test "proposes no transaction a Lexoffice receipt is attached to", c do
    payment = transaction_fixture(account_id: c.kontist.id, date: ~D[2027-01-20], amount: 23_800)

    Repo.insert!(%LexofficeReceipt{
      user_id: c.scope.user.id,
      lexoffice_id: "r1",
      date: ~D[2027-01-20],
      total: 23_800,
      paperless_ids: [],
      items: [%LexofficeReceipt.Item{amount: 23_800, net: 20_000}],
      payments: [%LexofficeReceipt.Payment{date: ~D[2027-01-20], amount: 23_800}],
      transaction_id: payment.id
    })

    sale = %Disposal{kind: :sale, date: ~D[2027-01-20], amount: 23_800, vat: :rate_19}
    assert FixedAssets.payment_proposals(c.scope, sale) == []
  end

  test "a withdrawal has no payment, and a disposal can be taken back", c do
    asset = fixed_asset_fixture(c.scope, %{"purchased_on" => "2025-03-01"})
    payment = transaction_fixture(account_id: c.kontist.id, date: ~D[2027-01-20], amount: 23_800)
    asset = disposal_fixture(c.scope, asset, %{"transaction_id" => payment.id})

    asset = disposal_fixture(c.scope, asset, %{"kind" => "withdrawal"})
    assert %Disposal{kind: :withdrawal, transaction_id: nil} = asset.disposal

    assert {:ok, %{disposal: nil}} = FixedAssets.remove_disposal(c.scope, asset)
    assert FixedAssets.get(c.scope, asset.id).disposal == nil
  end

  test "deletes an asset with its disposal", %{scope: scope} do
    asset =
      scope
      |> fixed_asset_fixture()
      |> then(&disposal_fixture(scope, &1, %{"date" => "2027-05-01"}))

    assert {:ok, _asset} = FixedAssets.delete(scope, asset)
    assert FixedAssets.list(scope) == []
    assert Repo.all(Disposal) == []
  end

  test "refuses to change, dispose of or delete another user's asset", %{scope: scope} do
    asset =
      scope
      |> fixed_asset_fixture(%{"purchased_on" => "2025-03-01"})
      |> then(&disposal_fixture(scope, &1))

    other = Scope.for_user(UsersFixtures.user_fixture())

    assert FixedAssets.get(other, asset.id) == nil

    for change <- [
          &FixedAssets.update(&1, asset, %{"name" => "Fremd"}),
          &FixedAssets.record_disposal(&1, asset, %{"amount" => "1"}),
          &FixedAssets.remove_disposal(&1, asset),
          &FixedAssets.delete(&1, asset)
        ] do
      assert_raise Ecto.NoResultsError, fn -> change.(other) end
    end

    assert %{name: "Notebook", disposal: %Disposal{amount: 23_800}} =
             FixedAssets.get(scope, asset.id)
  end
end
