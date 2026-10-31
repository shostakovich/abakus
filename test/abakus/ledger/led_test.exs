defmodule Abakus.Ledger.LedTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.KasseFixtures, only: [household: 0, equal: 6, create!: 1]

  alias Abakus.Depot.PortfoliosFixtures
  alias Abakus.Ledger
  alias Abakus.Ledger.Transaction

  setup do
    h = household()
    scope = budget_scope()

    c = %{
      h: h,
      scope: scope,
      account: account_fixture(),
      tracking: account_fixture(kind: :tracking)
    }

    Map.merge(c, %{kasse: source(c, :kasse), depot: source(c, :depot)})
  end

  defp source(c, :kasse) do
    expense = create!(equal(c.h, "Market", 2_000, "2026-10-01", c.h.anna, [c.h.anna, c.h.ben]))
    {:kasse_expense, expense.id}
  end

  defp source(c, :depot) do
    transaction =
      PortfoliosFixtures.transaction_fixture(c.scope, ~D[2026-10-01], type: :deposit, amount: 100)

    {:depot_transaction, transaction.id}
  end

  defp led!(c, led_by, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{account_id: c.account.id, date: ~D[2026-10-01], amount: 1_000})
    {:ok, transaction} = Ledger.create_transaction(c.scope, attrs, led_by: led_by)
    transaction
  end

  defp led_changes(c) do
    [
      account_id: %{account_id: account_fixture().id},
      date: %{date: ~D[2026-10-02]},
      amount: %{amount: 2_000},
      payee_id: %{payee_id: payee_fixture().id},
      payee_id: %{payee_id: c.tracking.transfer_payee.id, category_id: category_fixture().id},
      subtransactions: %{
        subtransactions: [
          %{amount: 500, category_id: category_fixture().id},
          %{amount: 500, category_id: category_fixture().id}
        ]
      }
    ]
  end

  test "carries the source it was written from", c do
    assert Ledger.led_by(c.scope, led!(c, c.kasse)) == c.kasse
    assert Ledger.led_by(c.scope, led!(c, c.depot)) == c.depot
    assert Ledger.led_by(c.scope, transaction_fixture()) == nil
  end

  test "refuses changes to the fields a source leads from every caller except that source", c do
    for kind <- [:kasse, :depot], {field, attrs} <- led_changes(c) do
      led_by = source(c, kind)
      transaction = led!(c, led_by)

      for opts <- [[], [led_by: c.kasse], [led_by: c.depot]] do
        assert {:error, changeset} = Ledger.update_transaction(c.scope, transaction, attrs, opts)
        assert Keyword.has_key?(changeset.errors, field), "#{kind} #{field} #{inspect(opts)}"
      end

      assert {:ok, _changed} =
               Ledger.update_transaction(c.scope, transaction, attrs, led_by: led_by)
    end
  end

  test "a source leads one transaction a user has from it", c do
    led!(c, c.kasse)

    assert {:error, changeset} =
             Ledger.create_transaction(
               c.scope,
               %{account_id: c.account.id, date: ~D[2026-10-01], amount: 1},
               led_by: c.kasse
             )

    assert Keyword.has_key?(changeset.errors, :kasse_expense_id)
  end

  test "leaves category, memo, cleared state and approval to anyone", c do
    transaction = led!(c, c.kasse)
    category = category_fixture()

    assert {:ok, changed} =
             Ledger.update_transaction(c.scope, transaction, %{
               category_id: category.id,
               memo: "Mine",
               cleared: :cleared,
               approved: true
             })

    assert {changed.category_id, changed.memo, changed.cleared, changed.approved} ==
             {category.id, "Mine", :cleared, true}
  end

  test "is deleted only by its source", c do
    transaction = led!(c, c.kasse)

    assert {:error, changeset} = Ledger.delete_transaction(c.scope, transaction)
    assert [led_by: {"wird mit ihrer Ausgabe in der Kasse gelöscht", []}] = changeset.errors
    assert {:error, _} = Ledger.delete_transaction(c.scope, transaction, led_by: c.depot)

    assert {:ok, %{deleted_at: %DateTime{}}} =
             Ledger.delete_transaction(c.scope, transaction, led_by: c.kasse)
  end

  test "a proposal it leads is not accepted, as accepting deletes the proposal", c do
    existing = transaction_fixture(account_id: c.account.id, date: ~D[2026-10-01], amount: 1_000)
    proposal = led!(c, c.kasse)

    Repo.update_all(from(t in Transaction, where: t.id == ^proposal.id),
      set: [matched_transaction_id: existing.id]
    )

    assert {:error, changeset} = Ledger.accept_match(c.scope, proposal)
    assert [led_by: {"wird mit ihrer Ausgabe in der Kasse gelöscht", []}] = changeset.errors
    assert Repo.reload(proposal).deleted_at == nil
  end

  test "leads the counterpart of a transfer it writes", c do
    category = category_fixture()

    transaction =
      led!(c, c.depot,
        amount: -1_000,
        payee_id: c.tracking.transfer_payee.id,
        category_id: category.id
      )

    counterpart = Repo.get!(Transaction, transaction.transfer_transaction_id)

    assert Ledger.led_by(c.scope, counterpart) == c.depot

    assert {:error, changeset} =
             Ledger.update_transaction(c.scope, counterpart, %{
               amount: 2_000,
               date: ~D[2026-10-05]
             })

    assert Keyword.keys(changeset.errors) |> Enum.sort() == [:amount, :date]
    assert {:error, _} = Ledger.delete_transaction(c.scope, counterpart)
    assert {:ok, _} = Ledger.update_transaction(c.scope, counterpart, %{memo: "Mine"})

    assert {:ok, _} =
             Ledger.update_transaction(c.scope, counterpart, %{amount: 2_000}, led_by: c.depot)

    assert Repo.get!(Transaction, transaction.id).amount == -2_000
  end

  describe "lead/3" do
    test "puts a source on a transaction, which it leads from then on", c do
      transfer =
        transaction_fixture(%{
          account_id: c.account.id,
          payee_id: account_fixture().transfer_payee.id
        })

      counterpart = Repo.get!(Transaction, transfer.transfer_transaction_id)

      assert {:ok, %Transaction{kasse_expense_id: id}} =
               Ledger.lead(c.scope, counterpart, c.kasse)

      assert {:kasse_expense, id} == c.kasse
      assert Ledger.led_by(c.scope, transfer) == c.kasse
      assert {:error, _changeset} = Ledger.update_transaction(c.scope, transfer, %{amount: 5})
    end

    test "refuses a transaction that is led already", c do
      transaction = led!(c, c.depot)

      assert {:error, changeset} = Ledger.lead(c.scope, transaction, c.kasse)
      assert [led_by: {"folgt der Buchung im Depot", []}] = changeset.errors

      transfer = transaction_fixture(%{payee_id: c.account.transfer_payee.id})
      {:ok, _led} = Ledger.lead(c.scope, transfer, source(c, :depot))
      counterpart = Repo.get!(Transaction, transfer.transfer_transaction_id)

      assert {:error, _changeset} = Ledger.lead(c.scope, counterpart, c.kasse)
    end

    test "refuses a source that leads another transaction", c do
      led!(c, c.kasse)

      assert {:error, changeset} = Ledger.lead(c.scope, transaction_fixture(), c.kasse)
      assert Keyword.has_key?(changeset.errors, :kasse_expense_id)
    end

    test "refuses a deleted transaction", c do
      {:ok, deleted} = Ledger.delete_transaction(c.scope, transaction_fixture())

      assert {:error, changeset} = Ledger.lead(c.scope, deleted, c.kasse)
      assert Keyword.has_key?(changeset.errors, :deleted_at)
    end
  end

  test "a match keeps the date its source leads", c do
    transaction = led!(c, c.depot, amount: -1_000)

    {:ok, proposal} =
      Ledger.create_transaction(c.scope, %{
        account_id: c.account.id,
        date: ~D[2026-10-03],
        amount: -1_000,
        source: :file,
        cleared: :cleared,
        matched_transaction_id: transaction.id
      })

    assert {:ok, matched} = Ledger.accept_match(c.scope, proposal)

    assert {matched.id, matched.date, matched.cleared} ==
             {transaction.id, ~D[2026-10-01], :cleared}
  end
end
