defmodule Abakus.BookkeepingTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Bookkeeping, Categories, Ledger, UsersFixtures}
  alias Abakus.Bookkeeping.TaxLine
  alias Abakus.Users.Scope

  setup do
    scope = budget_scope()
    business = account_fixture(name: "Kontist", kind: :tracking)
    private = account_fixture(name: "Girokonto")
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [business.id])
    %{scope: scope, business: business, private: private}
  end

  defp transaction(account, attrs \\ []),
    do: transaction_fixture(Enum.into(attrs, %{account_id: account.id}))

  defp split(account, amounts) do
    {:ok, split} =
      Ledger.create_transaction(budget_scope(), %{
        account_id: account.id,
        date: ~D[2026-10-09],
        amount: Enum.sum(amounts),
        subtransactions: Enum.map(amounts, &%{amount: &1})
      })

    Bookkeeping.get_transaction(budget_scope(), split.id)
  end

  defp save!(scope, transaction, params) do
    {:ok, _lines} =
      Bookkeeping.save_tax_lines(
        scope,
        Bookkeeping.get_transaction(scope, transaction.id),
        params
      )
  end

  defp inbox_ids(scope), do: for({t, _missing} <- Bookkeeping.inbox(scope), do: t.id)

  defp without_category(scope),
    do: for({t, missing} <- Bookkeeping.inbox(scope), :category in missing, do: t.id)

  describe "business accounts" do
    test "are only the user's own accounts", %{scope: scope, business: business} do
      other = Scope.for_user(UsersFixtures.user_fixture())
      {:ok, theirs} = Ledger.create_account(other, %{name: "Fremd", kind: :checking})

      assert {:ok, [id]} = Bookkeeping.put_business_accounts(scope, [business.id, theirs.id, "x"])
      assert id == business.id
      assert Bookkeeping.business_account_ids(scope) == [business.id]
      assert Bookkeeping.in_use?(scope.user)
      refute Bookkeeping.in_use?(other.user)
    end

    test "replace the earlier ones", %{scope: scope, business: business, private: private} do
      {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [private.id])
      assert Bookkeeping.business_account_ids(scope) == [private.id]

      {:ok, []} = Bookkeeping.put_business_accounts(scope, [])
      refute Bookkeeping.in_use?(scope.user)
      refute business.id in Bookkeeping.business_account_ids(scope)
    end
  end

  describe "inbox/1" do
    test "lists the business account's transactions without a category, newest first", c do
      older = transaction(c.business, date: ~D[2026-10-01])
      newer = transaction(c.business, date: ~D[2026-10-05])
      _private = transaction(c.private)
      _zero = transaction(c.business, amount: 0)
      categorised = transaction(c.business)
      save!(c.scope, categorised, %{"transaction" => %{"category" => "internet", "vat" => "19"}})

      assert without_category(c.scope) == [newer.id, older.id]

      assert Enum.find_value(Bookkeeping.inbox(c.scope), fn {t, missing} ->
               t.id == categorised.id && missing
             end) == [:receipt]
    end

    test "leaves out transfers, deleted transactions, match proposals and the opening balance",
         c do
      {:ok, _transfer} =
        Ledger.create_transaction(c.scope, %{
          account_id: c.business.id,
          date: ~D[2026-10-02],
          amount: -50_000,
          payee_id: c.private.transfer_payee.id,
          counterpart_category_id: Categories.ready_to_assign!(c.scope).id
        })

      deleted = transaction(c.business)
      {:ok, _deleted} = Ledger.delete_transaction(c.scope, deleted)
      existing = transaction(c.business, amount: -999)

      {:ok, _proposal} =
        Ledger.create_transaction(c.scope, %{
          account_id: c.business.id,
          date: ~D[2026-10-09],
          amount: -999,
          source: :file,
          matched_transaction_id: existing.id
        })

      {:ok, opened} =
        Ledger.create_account(c.scope, %{name: "Kontist 2", kind: :tracking},
          balance: 10_000,
          date: ~D[2026-10-01]
        )

      {:ok, _ids} = Bookkeeping.put_business_accounts(c.scope, [c.business.id, opened.id])

      assert inbox_ids(c.scope) == [existing.id]
    end

    test "keeps a split until each of its parts has a category", c do
      split = split(c.business, [-1_000, -500])
      [first, second] = split.subtransactions

      save!(c.scope, split, %{first.id => %{"category" => "internet", "vat" => "19"}})
      assert without_category(c.scope) == [split.id]

      save!(c.scope, split, %{second.id => %{"category" => "bank_fees", "vat" => "0"}})
      assert without_category(c.scope) == []
    end

    test "is the user's own", c do
      transaction(c.business)
      other = Scope.for_user(UsersFixtures.user_fixture())

      assert Bookkeeping.inbox(other) == []
    end
  end

  describe "save_tax_lines/3" do
    test "sets, changes and removes a transaction's tax line", c do
      expense = transaction(c.private, amount: -2_368)

      save!(c.scope, expense, %{"transaction" => %{"category" => "internet", "vat" => "19"}})

      assert [%TaxLine{category: "internet", vat: :rate_19, subtransaction_id: nil}] =
               Map.values(Bookkeeping.tax_lines(c.scope, [expense]))

      save!(c.scope, expense, %{"transaction" => %{"category" => "books", "vat" => "7"}})

      assert [%TaxLine{category: "books", vat: :rate_7}] =
               Map.values(Bookkeeping.tax_lines(c.scope, [expense]))

      save!(c.scope, expense, %{"transaction" => %{"category" => "", "vat" => "7"}})
      assert Bookkeeping.tax_lines(c.scope, [expense]) == %{}
      assert Repo.aggregate(TaxLine, :count) == 0
    end

    test "refuses reverse charge outside a §13b category and the other way round", c do
      expense = Bookkeeping.get_transaction(c.scope, transaction(c.business).id)

      assert {:error, %{"transaction" => changeset}} =
               Bookkeeping.save_tax_lines(c.scope, expense, %{
                 "transaction" => %{"category" => "licenses", "vat" => "reverse_charge"}
               })

      assert {"passt nur zu einer §13b-Kategorie", _opts} = changeset.errors[:vat]

      assert {:error, %{"transaction" => changeset}} =
               Bookkeeping.save_tax_lines(c.scope, expense, %{
                 "transaction" => %{"category" => "licenses_13b_eu", "vat" => "19"}
               })

      assert {"muss bei einer §13b-Kategorie Reverse Charge sein", _opts} = changeset.errors[:vat]

      assert {:error, %{"transaction" => changeset}} =
               Bookkeeping.save_tax_lines(c.scope, expense, %{
                 "transaction" => %{"category" => "made_up", "vat" => "19"}
               })

      assert changeset.errors[:category]
      assert Repo.aggregate(TaxLine, :count) == 0
    end

    test "saves nothing while one side is invalid", c do
      split = split(c.business, [-1_000, -500])
      [first, second] = split.subtransactions

      assert {:error, errors} =
               Bookkeeping.save_tax_lines(c.scope, split, %{
                 first.id => %{"category" => "internet", "vat" => "19"},
                 second.id => %{"category" => "licenses", "vat" => "reverse_charge"}
               })

      assert Map.keys(errors) == [second.id]
      assert Repo.aggregate(TaxLine, :count) == 0
    end

    test "annotates a split per part, not as a whole", c do
      split = split(c.business, [-1_000, -500])
      [first, _second] = split.subtransactions

      save!(c.scope, split, %{
        "transaction" => %{"category" => "internet", "vat" => "19"},
        first.id => %{"category" => "mobile", "vat" => "19"}
      })

      assert [{{_id, side}, %TaxLine{category: "mobile"}}] =
               Map.to_list(Bookkeeping.tax_lines(c.scope, [split]))

      assert side == first.id
    end

    test "gives a transfer no tax line", c do
      {:ok, transfer} =
        Ledger.create_transaction(c.scope, %{
          account_id: c.business.id,
          date: ~D[2026-10-02],
          amount: -50_000,
          payee_id: c.private.transfer_payee.id,
          counterpart_category_id: Categories.ready_to_assign!(c.scope).id
        })

      transfer = Bookkeeping.get_transaction(c.scope, transfer.id)

      assert Bookkeeping.sides(transfer) == []

      assert {:ok, []} =
               Bookkeeping.save_tax_lines(c.scope, transfer, %{
                 "transaction" => %{"category" => "private", "vat" => "0"}
               })
    end

    test "finds no transaction of another user", c do
      expense = transaction(c.business)
      other = Scope.for_user(UsersFixtures.user_fixture())

      assert Bookkeeping.get_transaction(other, expense.id) == nil
    end
  end

  describe "tax_lines/2" do
    test "drops the line of a part that left its split", c do
      split = split(c.business, [-1_000, -500])
      [first, second] = split.subtransactions
      save!(c.scope, split, %{first.id => %{"category" => "internet", "vat" => "19"}})

      {:ok, _whole} =
        Ledger.update_transaction(c.scope, split, %{
          subtransactions: [
            %{id: second.id, amount: -500},
            %{amount: -1_000}
          ]
        })

      split = Bookkeeping.get_transaction(c.scope, split.id)

      assert Bookkeeping.tax_lines(c.scope, [split]) == %{}
      assert split.id in inbox_ids(c.scope)
    end
  end
end
