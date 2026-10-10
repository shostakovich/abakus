defmodule Abakus.Ledger.PayeesTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.Payee

  describe "create_payee/1" do
    test "stores the name as entered with its lookup key" do
      category = category_fixture()

      assert {:ok, payee} = Ledger.create_payee(%{name: "🛒 REWE", last_category_id: category.id})
      assert %Payee{name: "🛒 REWE", lookup_key: "rewe", transfer_account_id: nil} = payee
      assert payee.last_category_id == category.id
    end

    test "requires a name" do
      assert {:error, changeset} = Ledger.create_payee(%{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "regular payees are unique by lookup key" do
      payee_fixture(name: "Rewe")

      assert {:error, changeset} = Ledger.create_payee(%{name: "🛒 REWE"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)

      assert {:error, changeset} =
               Ledger.update_payee(payee_fixture(name: "Aldi"), %{name: "REWE"})

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "the same name in decomposed form or with ss is the same payee" do
      payee_fixture(name: "B\u00E4ckerei Stra\u00DFe")

      assert {:error, _} = Ledger.create_payee(%{name: "Ba\u0308ckerei STRASSE"})
      assert {:ok, _} = Ledger.find_payee_by_name("ba\u0308ckerei strasse")
    end

    test "a regular payee may share its lookup key with a transfer payee" do
      account = account_fixture(name: "Girokonto")

      assert {:ok, payee} = Ledger.create_payee(%{name: "transfer : GIROKONTO"})
      assert payee.lookup_key == account.transfer_payee.lookup_key
    end

    test "an account has only one transfer payee" do
      account = account_fixture()

      assert {:error, changeset} = %Payee{} |> Payee.transfer_changeset(account) |> Repo.insert()
      assert %{transfer_account_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "the last category must exist" do
      assert {:error, changeset} = Ledger.create_payee(%{name: "Aldi", last_category_id: -1})
      assert %{last_category_id: ["does not exist"]} = errors_on(changeset)

      assert {:error, changeset} = Ledger.update_payee(payee_fixture(), %{last_category_id: -1})
      assert %{last_category_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "update_payee/2" do
    test "renames a regular payee and its lookup key" do
      payee = payee_fixture(name: "Rewe")

      assert {:ok, %Payee{name: "🛒 Rewe Markt", lookup_key: "rewe markt"}} =
               Ledger.update_payee(payee, %{name: "🛒 Rewe Markt"})
    end

    test "a transfer payee keeps the account's name" do
      account = account_fixture(name: "Girokonto")

      assert {:error, changeset} = Ledger.update_payee(account.transfer_payee, %{name: "Anders"})
      assert %{name: ["folgt dem Kontonamen"]} = errors_on(changeset)
    end
  end

  describe "find_payee_by_name/1" do
    test "ignores emoji and case" do
      payee = payee_fixture(name: "🛒 Rewe")

      assert {:ok, %Payee{id: id}} = Ledger.find_payee_by_name("REWE")
      assert id == payee.id
      assert {:ok, %Payee{id: ^id}} = Ledger.find_payee_by_name("🛍️rewe ")
    end

    test "finds transfer payees" do
      account = account_fixture(name: "💳 Girokonto")
      id = account.transfer_payee.id

      assert {:ok, %Payee{id: ^id}} = Ledger.find_payee_by_name("Transfer : Girokonto")
    end

    test "prefers the regular payee over a transfer payee of the same name" do
      account_fixture(name: "Girokonto")
      payee = payee_fixture(name: "Transfer : Girokonto")

      assert {:ok, found} = Ledger.find_payee_by_name("transfer : girokonto")
      assert found.id == payee.id
    end

    test "is ambiguous between transfer payees of accounts with the same name" do
      account_fixture(name: "Tagesgeld")
      account_fixture(name: "💰 Tagesgeld")

      assert Ledger.find_payee_by_name("Transfer : Tagesgeld") == {:error, :ambiguous}
    end

    test "reports unknown names" do
      assert Ledger.find_payee_by_name("Niemand") == {:error, :not_found}
    end
  end

  test "list_payees/0 lists the regular payees by name" do
    account_fixture(name: "Girokonto")
    payee_fixture(name: "🛒 Rewe")
    payee_fixture(name: "Aldi")

    assert ["Aldi", "🛒 Rewe"] = Enum.map(Ledger.list_payees(), & &1.name)
  end
end
