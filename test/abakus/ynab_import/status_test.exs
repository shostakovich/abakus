defmodule Abakus.YnabImport.StatusTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger, YnabImport}
  alias Abakus.Ledger.{Transaction, TransactionOrigin}
  alias Abakus.YnabImport.Status

  @fixture Path.expand("../../fixtures/ynab/plan.json", __DIR__)
  @external_resource @fixture
  @plan @fixture |> File.read!() |> JSON.decode!() |> Map.fetch!("plan")

  test "is nil without anything from YNAB" do
    transaction_fixture()

    assert YnabImport.status() == nil
  end

  test "counts what the import brought over and dates it by its transactions' origins" do
    {:ok, report} = YnabImport.import_plan(@plan)
    imported_at = Repo.one(from o in TransactionOrigin, select: max(o.inserted_at))

    assert %Status{} = status = YnabImport.status()
    assert status.imported_at == imported_at

    assert Map.take(status, [:accounts, :categories, :payees, :transactions]) ==
             report.counts

    assert status.category_groups == 3
    assert status.first_month == ~D[2026-08-01]
  end

  test "leaves out what was added in Abakus afterwards" do
    {:ok, _report} = YnabImport.import_plan(@plan)
    before = YnabImport.status()

    account = account_fixture()
    payee = payee_fixture()
    category = category_fixture()
    {:ok, _assignment} = Categories.assign(category, ~D[2020-01-01], 1_000)
    transaction_fixture(account_id: account.id, payee_id: payee.id, source: :api)

    assert YnabImport.status() == before
  end

  test "stays put when an imported transaction becomes a transfer to a later account" do
    {:ok, _report} = YnabImport.import_plan(@plan)
    before = YnabImport.status()

    account = account_fixture()

    imported =
      Repo.one(
        from t in Transaction,
          where:
            t.source == :ynab and is_nil(t.transfer_transaction_id) and
              is_nil(t.matched_transaction_id) and is_nil(t.deleted_at) and
              t.cleared != :reconciled,
          limit: 1
      )

    {:ok, _transfer} =
      Ledger.update_transaction(imported, %{payee_id: account.transfer_payee.id, category_id: nil})

    assert Repo.exists?(
             from t in Transaction, where: t.account_id == ^account.id and t.source == :ynab
           )

    assert YnabImport.status() == before
  end
end
