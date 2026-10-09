defmodule Abakus.Ledger.AccountsTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Payee}

  describe "create_account/1" do
    test "creates the account with its transfer payee" do
      assert {:ok, account} = Ledger.create_account(%{name: "💳 Girokonto", kind: :checking})

      assert %Payee{name: "Transfer : 💳 Girokonto", lookup_key: "transfer : girokonto"} =
               account.transfer_payee

      assert Repo.get_by!(Payee, transfer_account_id: account.id).id == account.transfer_payee.id
      assert %Account{closed: false, position: 0, fed_by: nil, note: nil} = account
    end

    test "stores every field" do
      reconciled_at = ~U[2026-10-01 08:30:00.123456Z]

      assert {:ok, account} =
               Ledger.create_account(%{
                 name: "Depot",
                 kind: "tracking",
                 fed_by: "portfolio",
                 closed: true,
                 note: "Wertpapiere",
                 position: 3,
                 last_reconciled_at: reconciled_at
               })

      assert %Account{
               kind: :tracking,
               fed_by: :portfolio,
               closed: true,
               note: "Wertpapiere",
               position: 3
             } =
               Ledger.get_account!(account.id)

      assert Ledger.get_account!(account.id).last_reconciled_at == reconciled_at
    end

    test "requires a name and a kind" do
      assert {:error, changeset} = Ledger.create_account(%{name: " "})
      assert %{name: ["can't be blank"], kind: ["can't be blank"]} = errors_on(changeset)
      assert Repo.aggregate(Payee, :count) == 0
    end

    test "rejects unknown kinds, feeders and negative positions" do
      assert {:error, changeset} =
               Ledger.create_account(%{
                 name: "Karte",
                 kind: :credit_card,
                 fed_by: :mint,
                 position: -1
               })

      assert %{
               kind: ["is invalid"],
               fed_by: ["is invalid"],
               position: ["must be greater than or equal to 0"]
             } =
               errors_on(changeset)
    end
  end

  test "budget_account?/1 holds for every kind but tracking" do
    assert Account.budget_account?(%Account{kind: :checking})
    assert Account.budget_account?(%Account{kind: :savings})
    assert Account.budget_account?(%Account{kind: :cash})
    refute Account.budget_account?(%Account{kind: :tracking})
  end

  describe "update_account/2" do
    test "renaming renames the transfer payee" do
      account = account_fixture(name: "Girokonto")

      assert {:ok, %Account{name: "🏦 Gemeinschaftskonto"} = renamed} =
               Ledger.update_account(account, %{name: "🏦 Gemeinschaftskonto"})

      assert renamed.transfer_payee.name == "Transfer : 🏦 Gemeinschaftskonto"

      assert %Payee{
               name: "Transfer : 🏦 Gemeinschaftskonto",
               lookup_key: "transfer : gemeinschaftskonto"
             } =
               Repo.get_by!(Payee, transfer_account_id: account.id)
    end

    test "other changes leave the transfer payee alone" do
      account = account_fixture(name: "Girokonto")
      payee = Repo.get_by!(Payee, transfer_account_id: account.id)

      assert {:ok, %Account{closed: true} = closed} =
               Ledger.update_account(account, %{closed: true})

      assert Repo.get!(Payee, payee.id).updated_at == payee.updated_at
      assert closed.transfer_payee.id == payee.id
    end

    test "keeps an account on its side of the budget" do
      account = account_fixture(kind: :checking)

      assert {:ok, account} = Ledger.update_account(account, %{kind: :savings})
      assert {:error, changeset} = Ledger.update_account(account, %{kind: :tracking})
      assert %{kind: ["kann nicht zwischen Budget und Tracking wechseln"]} = errors_on(changeset)

      tracking = account_fixture(kind: :tracking)
      assert {:error, changeset} = Ledger.update_account(tracking, %{kind: :cash})
      assert %{kind: ["kann nicht zwischen Budget und Tracking wechseln"]} = errors_on(changeset)
    end

    test "returns the changeset of an invalid update" do
      account = account_fixture()
      assert {:error, changeset} = Ledger.update_account(account, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  test "list_accounts/0 orders by position" do
    second = account_fixture(position: 2)
    first = account_fixture(position: 1)

    assert Enum.map(Ledger.list_accounts(), & &1.id) == [first.id, second.id]
  end

  test "an account cannot be deleted while its transfer payee exists" do
    account = account_fixture()
    assert_raise Ecto.ConstraintError, fn -> Repo.delete(account) end
  end
end
