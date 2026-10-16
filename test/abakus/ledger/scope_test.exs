defmodule Abakus.Ledger.ScopeTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.UsersFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Payee, Transaction}

  setup do
    owner = budget_scope()
    account = account_fixture(%{name: "Giro"})
    payee = payee_fixture(%{name: "Rewe"})
    transaction = transaction_fixture(%{account_id: account.id, payee_id: payee.id})
    %{owner: owner, other: user_scope_fixture(), account: account, payee: payee, tx: transaction}
  end

  test "another user sees none of the owner's records", c do
    assert Ledger.list_accounts(c.other) == []
    assert Ledger.list_payees(c.other) == []
    assert Ledger.list_transactions(c.other, :all) == []
    assert Ledger.list_transactions(c.other, c.account) == []
    assert Ledger.balances(c.other) == %{}
    assert Ledger.balance(c.other, c.account, ~D[2026-10-31]) == 0
    assert Ledger.first_open_date(c.other) == nil
    assert Ledger.find_payee_by_name(c.other, "Rewe") == {:error, :not_found}

    assert [%{id: id}] = Ledger.list_accounts(c.owner)
    assert id == c.account.id
  end

  test "the owner's records are missing for another user", c do
    assert Ledger.get_account(c.other, c.account.id) == nil
    assert Ledger.get_transaction(c.other, c.tx.id) == nil
    assert_raise Ecto.NoResultsError, fn -> Ledger.get_account!(c.other, c.account.id) end
    assert_raise Ecto.NoResultsError, fn -> Ledger.get_transaction!(c.other, c.tx.id) end

    assert_raise Ecto.NoResultsError, fn ->
      Ledger.update_account(c.other, c.account, %{name: "Meins"})
    end

    assert_raise Ecto.NoResultsError, fn ->
      Ledger.update_transaction(c.other, c.tx, %{memo: "Meins"})
    end

    assert_raise Ecto.NoResultsError, fn -> Ledger.delete_transaction(c.other, c.tx) end
    assert Ledger.reject_match(c.other, c.tx) == {:error, :not_a_proposal}
  end

  test "another user cannot book into the owner's account or with the owner's payee", c do
    assert {:error, changeset} =
             Ledger.create_transaction(c.other, %{
               account_id: c.account.id,
               date: ~D[2026-10-09],
               amount: -100
             })

    assert %{account_id: ["does not exist"]} = errors_on(changeset)

    {:ok, own} = Ledger.create_account(c.other, %{name: "Giro", kind: :checking})

    assert {:error, changeset} =
             Ledger.create_transaction(c.other, %{
               account_id: own.id,
               date: ~D[2026-10-09],
               amount: -100,
               payee_id: c.payee.id
             })

    assert %{payee_id: ["does not exist"]} = errors_on(changeset)
  end

  test "payees are the user's own, so another user's names are free", c do
    {:ok, own} = Ledger.create_account(c.other, %{name: "Giro", kind: :checking})

    {:ok, transaction} =
      Ledger.create_transaction(c.other, %{
        account_id: own.id,
        date: ~D[2026-10-09],
        amount: -100,
        payee_name: "Rewe"
      })

    assert transaction.payee_id != c.payee.id
    assert [%{name: "Rewe", user_id: user_id}] = Ledger.list_payees(c.other)
    assert user_id == c.other.user.id
  end

  test "a record without its user is refused, not written", c do
    attrs = %{account_id: c.account.id, date: ~D[2026-10-09], amount: -100, source: :manual}

    for changeset <- [
          Account.changeset(%Account{}, %{name: "Giro", kind: :checking}),
          Payee.changeset(%Payee{}, %{name: "Rewe"}),
          Transaction.changeset(%Transaction{cleared: :uncleared, approved: true}, attrs)
        ] do
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
