defmodule Abakus.Kasse.BudgetLinkSwitchTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.KasseFixtures

  alias Abakus.Kasse.{BudgetLink, Expenses}
  alias Abakus.Kasse.BudgetLink.{Link, LinkedTransaction}
  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Transaction}

  setup do
    h = household()
    account = account_fixture(%{name: "Geteilt", kind: :cash})
    groceries = category_fixture(%{name: "🛒 Lebensmittel"})
    {:ok, _mapping} = BudgetLink.put_category_mapping(scope_of(h.anna), %{h.food => groceries.id})

    %{h: h, account: account, groceries: groceries.id}
  end

  defp switch_on(c), do: BudgetLink.switch_on(scope_of(c.h.anna), c.account.id)

  defp expense!(h, title, cents, date, payer \\ nil),
    do: create!(equal(h, title, cents, date, payer || h.ben, [h.anna, h.ben]))

  defp linked(expense) do
    case Repo.get_by(LinkedTransaction, expense_id: expense.id) do
      nil -> nil
      link -> Repo.get!(Transaction, link.transaction_id)
    end
  end

  describe "switching on" do
    test "gives every non-reimbursement expense that changes the owner's balance a linked transaction",
         c do
      weekly = expense!(c.h, "Wocheneinkauf", 8742, "2026-03-05")
      cinema = expense!(c.h, "Kino", 2400, "2026-03-10", c.h.anna)
      older = expense!(c.h, "Altbau", 5000, "2025-02-20")
      gone = expense!(c.h, "Pizza", 2000, "2026-03-14")
      {:ok, _deleted} = Expenses.delete_expense(scope_of(c.h.ben), gone)
      payback = create!(reimbursement(1000, "2026-03-15", c.h.anna, c.h.ben))
      others = create!(equal(c.h, "Bar", 3000, "2026-03-16", c.h.ben, [c.h.ben, c.h.cleo]))
      own = create!(equal(c.h, "Bäcker", 500, "2026-03-17", c.h.anna, [c.h.anna]))
      gift = create!(equal(c.h, "Geschenk", 1500, "2026-03-18", c.h.anna, [c.h.ben]))

      assert switch_on(c) == {:ok, %{created: 4}}

      assert %{
               amount: -4371,
               date: ~D[2026-03-05],
               category_id: groceries,
               memo: "Gesamt 87,42 € · bezahlt von Ben",
               cleared: :cleared,
               approved: false,
               source: :kasse
             } = linked(weekly)

      assert groceries == c.groceries
      assert %{amount: 1200, memo: "Gesamt 24,00 € · bezahlt von Anna"} = linked(cinema)
      assert %{amount: -2500, date: ~D[2025-02-20]} = linked(older)
      assert %{amount: 1500} = linked(gift)

      for expense <- [gone, payback, others, own], do: assert(linked(expense) == nil)

      assert Repo.reload!(c.account).fed_by == :shared_expenses
      assert %Link{account_id: account_id, start_date: nil} = Repo.get!(Link, c.h.anna)
      assert account_id == c.account.id
    end

    test "moves the feed from another account fed by shared expenses", c do
      before = account_fixture(%{name: "Alt", kind: :cash, fed_by: :shared_expenses})

      assert {:ok, _counts} = switch_on(c)
      assert Repo.reload!(before).fed_by == nil
      assert Repo.reload!(c.account).fed_by == :shared_expenses
    end

    test "links only the budget owner's participant", c do
      assert BudgetLink.switch_on(scope_of(c.h.ben), c.account.id) ==
               {:error, :not_budget_owner}
    end

    test "links once", c do
      assert {:ok, _counts} = switch_on(c)
      assert switch_on(c) == {:error, :linked}
    end

    test "needs an open budget account not fed by another app", c do
      closed = account_fixture(%{kind: :cash, closed: true})
      tracking = account_fixture(%{kind: :tracking})
      depot = account_fixture(%{kind: :checking, fed_by: :portfolio})

      for id <- [closed.id, tracking.id, depot.id, "", "x", -1] do
        assert BudgetLink.switch_on(scope_of(c.h.anna), id) == {:error, :no_account}
      end

      assert Repo.all(Link) == []
      assert BudgetLink.account_choices(scope_of(c.h.anna)) |> Enum.map(& &1.id) == [c.account.id]
    end

    test "the account takes no entries and offers no reconcile", c do
      {:ok, _counts} = switch_on(c)

      account = Ledger.get_account!(budget_scope(), c.account.id)
      refute Account.takes_entries?(account)
      refute Account.reconcilable?(account)
    end
  end

  describe "a link with a start date" do
    setup c do
      older = expense!(c.h, "Altbau", 5000, "2026-02-20")

      {:ok, _account} =
        Ledger.update_account(budget_scope(), c.account, %{fed_by: :shared_expenses})

      Repo.insert!(%Link{
        participant_id: c.h.anna,
        account_id: c.account.id,
        start_date: ~D[2026-03-01]
      })

      %{older: older}
    end

    test "books an older expense not when it changes", c do
      changed = Map.merge(Expenses.input(c.older), %{amount_cents: 6000, original_amount: 6000})
      {:ok, older} = Expenses.update_expense(scope_of(c.h.ben), c.older, changed)

      assert linked(older) == nil
    end

    test "books an older expense once moved after the start date", c do
      {:ok, older} =
        Expenses.update_expense(
          scope_of(c.h.ben),
          c.older,
          Map.put(Expenses.input(c.older), :date, ~D[2026-03-02])
        )

      assert %{amount: -2500, date: ~D[2026-03-02]} = linked(older)
    end

    test "books an older expense entered later", c do
      backdated = expense!(c.h, "Nachtrag", 1000, "2026-01-15")

      assert %{amount: -500, date: ~D[2026-01-15]} = linked(backdated)
    end
  end
end
