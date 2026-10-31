defmodule Abakus.Ledger.PayeesTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.{Payee, PayeeRenameCondition}

  describe "create_payee/2" do
    test "stores the name as entered with its lookup key" do
      category = category_fixture()

      assert {:ok, payee} =
               Ledger.create_payee(budget_scope(), %{
                 name: "🛒 REWE",
                 last_category_id: category.id
               })

      assert %Payee{name: "🛒 REWE", lookup_key: "rewe", transfer_account_id: nil} = payee
      assert payee.last_category_id == category.id
    end

    test "requires a name" do
      assert {:error, changeset} = Ledger.create_payee(budget_scope(), %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "regular payees are unique by lookup key" do
      payee_fixture(name: "Rewe")

      assert {:error, changeset} = Ledger.create_payee(budget_scope(), %{name: "🛒 REWE"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.update_payee(budget_scope(), payee_fixture(name: "Aldi"), %{name: "REWE"})

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "the same name in decomposed form or with ss is the same payee" do
      payee_fixture(name: "B\u00E4ckerei Stra\u00DFe")

      assert {:error, _} = Ledger.create_payee(budget_scope(), %{name: "Ba\u0308ckerei STRASSE"})
      assert {:ok, _} = Ledger.find_payee_by_name(budget_scope(), "ba\u0308ckerei strasse")
    end

    test "a regular payee may share its lookup key with a transfer payee" do
      account = account_fixture(name: "Girokonto")

      assert {:ok, payee} = Ledger.create_payee(budget_scope(), %{name: "transfer : GIROKONTO"})
      assert payee.lookup_key == account.transfer_payee.lookup_key
    end

    test "an account has only one transfer payee" do
      account = account_fixture()

      assert {:error, changeset} =
               %Payee{user_id: account.user_id}
               |> Payee.transfer_changeset(account)
               |> Repo.insert()

      assert %{transfer_account_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "the last category must exist" do
      assert {:error, changeset} =
               Ledger.create_payee(budget_scope(), %{
                 name: "Aldi",
                 last_category_id: Ecto.UUID.generate()
               })

      assert %{last_category_id: ["does not exist"]} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.update_payee(budget_scope(), payee_fixture(), %{
                 last_category_id: Ecto.UUID.generate()
               })

      assert %{last_category_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "update_payee/3" do
    test "renames a regular payee and its lookup key" do
      payee = payee_fixture(name: "Rewe")

      assert {:ok, %Payee{name: "🛒 Rewe Markt", lookup_key: "rewe markt"}} =
               Ledger.update_payee(budget_scope(), payee, %{name: "🛒 Rewe Markt"})
    end

    test "a transfer payee keeps the account's name" do
      account = account_fixture(name: "Girokonto")

      assert {:error, changeset} =
               Ledger.update_payee(budget_scope(), account.transfer_payee, %{name: "Anders"})

      assert %{name: ["folgt dem Kontonamen"]} = errors_on(changeset)
    end
  end

  describe "find_payee_by_name/2" do
    test "ignores emoji and case" do
      payee = payee_fixture(name: "🛒 Rewe")

      assert {:ok, %Payee{id: id}} = Ledger.find_payee_by_name(budget_scope(), "REWE")
      assert id == payee.id
      assert {:ok, %Payee{id: ^id}} = Ledger.find_payee_by_name(budget_scope(), "🛍️rewe ")
    end

    test "finds transfer payees" do
      account = account_fixture(name: "💳 Girokonto")
      id = account.transfer_payee.id

      assert {:ok, %Payee{id: ^id}} =
               Ledger.find_payee_by_name(budget_scope(), "Transfer : Girokonto")
    end

    test "prefers the regular payee over a transfer payee of the same name" do
      account_fixture(name: "Girokonto")
      payee = payee_fixture(name: "Transfer : Girokonto")

      assert {:ok, found} = Ledger.find_payee_by_name(budget_scope(), "transfer : girokonto")
      assert found.id == payee.id
    end

    test "is ambiguous between transfer payees of accounts with the same name" do
      account_fixture(name: "Tagesgeld")
      account_fixture(name: "💰 Tagesgeld")

      assert Ledger.find_payee_by_name(budget_scope(), "Transfer : Tagesgeld") ==
               {:error, :ambiguous}
    end

    test "reports unknown names" do
      assert Ledger.find_payee_by_name(budget_scope(), "Niemand") == {:error, :not_found}
    end
  end

  test "list_payees/0 lists the regular payees by name" do
    account_fixture(name: "Girokonto")
    payee_fixture(name: "🛒 Rewe")
    payee_fixture(name: "Aldi")

    assert ["Aldi", "🛒 Rewe"] = Enum.map(Ledger.list_payees(budget_scope()), & &1.name)
  end

  describe "merge_duplicate_payees/2" do
    test "merges payees with one lookup key into the oldest, which takes over what pointed at the others" do
      category = category_fixture()
      oldest = payee_fixture(name: "Bäckerei Korn")

      newer =
        Repo.insert!(%Payee{
          user_id: oldest.user_id,
          name: "BÄCKEREI KORN",
          lookup_key: oldest.lookup_key,
          last_category_id: category.id
        })

      booked = transaction_fixture(payee_id: newer.id)

      condition =
        Repo.insert!(%PayeeRenameCondition{
          user_id: oldest.user_id,
          payee_id: newer.id,
          operator: :contains,
          text: "KORN"
        })

      assert :ok = Ledger.merge_duplicate_payees(budget_scope(), [newer.id])

      assert Repo.reload(booked).payee_id == oldest.id
      assert Repo.reload(condition).payee_id == oldest.id
      assert %Payee{deleted_at: %DateTime{}, successor_id: successor_id} = Repo.reload(newer)
      assert successor_id == oldest.id
      assert Repo.reload(oldest).last_category_id == category.id
      assert [%Payee{id: id}] = Ledger.list_payees(budget_scope())
      assert id == oldest.id
    end

    test "leaves a payee alone whose lookup key is its own" do
      payee = payee_fixture(name: "Aldi")

      assert :ok = Ledger.merge_duplicate_payees(budget_scope(), [payee.id])
      assert Repo.reload(payee).deleted_at == nil
    end
  end
end
