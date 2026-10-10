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

    test "puts a new account after the others unless it has a position" do
      account_fixture(position: 4)
      account_fixture(position: 2)

      assert {:ok, %Account{position: 5}} = Ledger.create_account(%{name: "Bar", kind: :cash})

      assert {:ok, %Account{position: 1}} =
               Ledger.create_account(%{"name" => "Spar", "kind" => "savings", "position" => "1"})

      assert {:ok, %Account{position: 0}} =
               Ledger.create_account(%{name: "Depot", kind: :tracking, position: 0})
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

  test "takes_category?/2 holds in a budget account unless it transfers to another budget account" do
    checking = %Account{kind: :checking}
    depot = %Account{kind: :tracking}

    assert Account.takes_category?(checking)
    assert Account.takes_category?(checking, depot)
    refute Account.takes_category?(checking, %Account{kind: :savings})
    refute Account.takes_category?(depot)
    refute Account.takes_category?(depot, checking)
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

  test "balances/0 sums each account's register, cleared including reconciled" do
    giro = account_fixture()
    cash = account_fixture(%{kind: :cash})
    _empty = account_fixture()

    for {amount, cleared} <- [{10_000, :reconciled}, {-2_500, :cleared}, {-1_000, :uncleared}],
        do: transaction_fixture(%{account_id: giro.id, amount: amount, cleared: cleared})

    transaction_fixture(%{account_id: cash.id, amount: -300})
    deleted = transaction_fixture(%{account_id: cash.id, amount: -99_999})
    {:ok, _deleted} = Ledger.delete_transaction(deleted)

    assert Ledger.balances() == %{
             giro.id => %{balance: 6_500, cleared: 7_500, uncleared: -1_000},
             cash.id => %{balance: -300, cleared: 0, uncleared: -300}
           }
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
