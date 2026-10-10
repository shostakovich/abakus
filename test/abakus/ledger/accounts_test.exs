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

  test "balances/0 sums each account's register, cleared including reconciled, and counts the unapproved" do
    giro = account_fixture()
    cash = account_fixture(%{kind: :cash})
    _empty = account_fixture()

    for {amount, cleared} <- [{10_000, :reconciled}, {-2_500, :cleared}, {-1_000, :uncleared}],
        do: transaction_fixture(%{account_id: giro.id, amount: amount, cleared: cleared})

    transaction_fixture(%{account_id: cash.id, amount: -300, approved: false})
    deleted = transaction_fixture(%{account_id: cash.id, amount: -99_999, approved: false})
    {:ok, _deleted} = Ledger.delete_transaction(deleted)

    assert Ledger.balances() == %{
             giro.id => %{balance: 6_500, cleared: 7_500, uncleared: -1_000, unapproved: 0},
             cash.id => %{balance: -300, cleared: 0, uncleared: -300, unapproved: 1}
           }
  end

  test "list_accounts/0 orders by position" do
    second = account_fixture(position: 2)
    first = account_fixture(position: 1)

    assert Enum.map(Ledger.list_accounts(), & &1.id) == [first.id, second.id]
  end

  describe "link_ofx_account/3" do
    test "remembers the file's account, so it finds the account again" do
      account = account_fixture()

      assert {:ok, %Account{ofx_bank_id: "10020030", ofx_acct_id: "DE02"}} =
               Ledger.link_ofx_account(account, "10020030", "DE02")

      assert Ledger.get_account_by_ofx("10020030", "DE02").id == account.id
      assert Ledger.get_account_by_ofx("10020031", "DE02") == nil
      assert Ledger.get_account_by_ofx(nil, "DE02") == nil
    end

    test "finds a card account by its account id alone" do
      account = account_fixture()
      {:ok, _account} = Ledger.link_ofx_account(account, nil, "4111")

      assert Ledger.get_account_by_ofx(nil, "4111").id == account.id
      assert Ledger.get_account_by_ofx("1", "4111") == nil
    end

    test "takes the file's account from the account that had it, and replaces the account's own" do
      old = account_fixture()
      new = account_fixture()
      {:ok, _old} = Ledger.link_ofx_account(old, "1", "A")

      assert {:ok, _new} = Ledger.link_ofx_account(new, "1", "A")
      assert Ledger.get_account_by_ofx("1", "A").id == new.id
      assert %Account{ofx_bank_id: nil, ofx_acct_id: nil} = Repo.reload!(old)

      assert {:ok, _new} = Ledger.link_ofx_account(new, "1", "B")
      assert Ledger.get_account_by_ofx("1", "A") == nil
    end

    test "the account form does not change the link" do
      {:ok, account} = Ledger.link_ofx_account(account_fixture(), "1", "A")

      assert {:ok, %Account{ofx_bank_id: "1", ofx_acct_id: "A"}} =
               Ledger.update_account(account, %{name: "Neu", ofx_bank_id: "2", ofx_acct_id: "B"})
    end
  end

  test "an account cannot be deleted while its transfer payee exists" do
    account = account_fixture()
    assert_raise Ecto.ConstraintError, fn -> Repo.delete(account) end
  end
end
