defmodule Abakus.Kasse.BudgetLinkSwitchTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.KasseFixtures

  alias Abakus.Kasse.{Activities, BudgetLink, Expenses}
  alias Abakus.Kasse.BudgetLink.{Link, LinkedTransaction}
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Kasse.Ynab
  alias Abakus.Kasse.Ynab.Posting
  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Transaction}
  alias Abakus.Users.Scope

  @start ~D[2026-03-01]

  setup do
    h = household()
    account = account_fixture(%{name: "Geteilt", kind: :cash})
    groceries = category_fixture(%{name: "🛒 Lebensmittel"})
    treats = category_fixture(%{name: "🍷 Genuss"})
    {:ok, _mapping} = BudgetLink.put_category_mapping(scope_of(h.anna), %{h.food => groceries.id})

    Repo.insert!(%Ynab.Connection{
      participant_id: h.anna,
      token: "token",
      plan_id: "plan",
      account_id: "geteilt",
      start_date: @start
    })

    Repo.insert!(%Ynab.CategoryMapping{
      participant_id: h.anna,
      category_id: h.food,
      ynab_category_id: "ynab-food"
    })

    %{h: h, account: account, groceries: groceries.id, treats: treats.id}
  end

  defp switch_on(c), do: BudgetLink.switch_on(scope_of(c.h.anna), c.account.id)

  defp expense!(h, title, cents, date, payer \\ nil),
    do: create!(equal(h, title, cents, date, payer || h.ben, [h.anna, h.ben]))

  # A share the YNAB sync wrote and the final YNAB import brought over.
  defp imported!(c, expense, attrs \\ %{}) do
    synced =
      Map.merge(
        %{
          account_id: c.account.id,
          date: expense.date,
          amount: -Expense.share_of(expense, c.h.anna),
          payee_name: expense.title,
          memo: Posting.memo(expense),
          source: :ynab
        },
        attrs
      )

    transaction_fixture(synced)
  end

  defp linked(expense) do
    case Repo.get_by(LinkedTransaction, expense_id: expense.id) do
      nil -> nil
      link -> Repo.get!(Transaction, link.transaction_id)
    end
  end

  describe "switching on" do
    test "links the marked transactions, books the rest and removes the YNAB connection", c do
      weekly = expense!(c.h, "Wocheneinkauf", 8742, "2026-03-05")
      cinema = expense!(c.h, "Kino", 2400, "2026-03-10", c.h.anna)
      market = expense!(c.h, "Markt", 3000, "2026-03-12")
      gone = expense!(c.h, "Pizza", 2000, "2026-03-14")
      older = expense!(c.h, "Altbau", 5000, "2026-02-20")
      create!(reimbursement(1000, "2026-03-15", c.h.anna, c.h.ben))

      ynab = %{category_id: c.treats, cleared: :reconciled, approved: true, flag: :red}
      weekly_ynab = imported!(c, weekly, ynab)
      stale_ynab = imported!(c, market, %{amount: -1000})
      _twice = imported!(c, weekly)
      older_ynab = imported!(c, older)
      gone_ynab = imported!(c, gone)
      {:ok, _deleted} = Expenses.delete_expense(scope_of(c.h.ben), gone)

      Repo.insert!(%Ynab.Transaction{
        expense_id: weekly.id,
        participant_id: c.h.anna,
        ynab_transaction_id: "ynab-1",
        state: :synced
      })

      assert switch_on(c) == {:ok, %{adopted: 3, created: 1, unadoptable: 1, left: 1}}

      assert %{
               id: weekly_id,
               amount: -4371,
               category_id: treats,
               cleared: :reconciled,
               approved: true,
               flag: :red,
               memo: "Gesamt 87,42 € · bezahlt von Ben",
               source: :ynab
             } = linked(weekly)

      assert {weekly_id, treats} == {weekly_ynab.id, c.treats}

      assert %{id: stale_id, amount: -1500, memo: "Gesamt 30,00 € · bezahlt von Ben"} =
               linked(market)

      assert stale_id == stale_ynab.id

      assert %{amount: -1200, category_id: groceries, approved: false, source: :kasse} =
               linked(cinema)

      assert groceries == c.groceries

      assert linked(older).id == older_ynab.id
      assert Repo.reload!(gone_ynab).deleted_at == nil

      assert Repo.reload!(c.account).fed_by == :shared_expenses
      assert %Link{account_id: account_id, start_date: @start} = Repo.get!(Link, c.h.anna)
      assert account_id == c.account.id

      assert Repo.all(Ynab.Connection) == []
      assert Repo.all(Ynab.CategoryMapping) == []
      assert Repo.all(Ynab.Transaction) == []

      assert hd(Activities.list_activities(Scope.system())).details.text ==
               "YNAB-Verbindung entfernt"
    end

    test "leaves a split or a transfer with the marker as it is and books its expense not twice",
         c do
      weekly = expense!(c.h, "Wocheneinkauf", 8742, "2026-03-05")
      cinema = expense!(c.h, "Kino", 2400, "2026-03-10")
      card = account_fixture(%{name: "Karte", kind: :checking})

      split =
        imported!(c, weekly, %{
          subtransactions: [
            %{amount: -4000, category_id: c.groceries},
            %{amount: -371, category_id: c.treats}
          ]
        })

      transfer =
        transaction_fixture(%{
          account_id: c.account.id,
          date: cinema.date,
          amount: -1200,
          payee_id: Repo.preload(card, :transfer_payee).transfer_payee.id,
          memo: Posting.memo(cinema)
        })

      assert switch_on(c) == {:ok, %{adopted: 0, created: 0, unadoptable: 2, left: 0}}
      assert linked(weekly) == nil
      assert linked(cinema) == nil
      assert Repo.reload!(split).deleted_at == nil
      assert Repo.reload!(transfer).deleted_at == nil
      assert Repo.aggregate(where(Transaction, account_id: ^c.account.id), :count) == 2
    end

    test "adopts the first plain one of several marked transactions and counts the others", c do
      weekly = expense!(c.h, "Wocheneinkauf", 8742, "2026-03-05")

      split =
        imported!(c, weekly, %{
          subtransactions: [
            %{amount: -4000, category_id: c.groceries},
            %{amount: -371, category_id: c.treats}
          ]
        })

      first = imported!(c, weekly)
      _second = imported!(c, weekly)

      assert switch_on(c) == {:ok, %{adopted: 1, created: 0, unadoptable: 2, left: 0}}
      assert linked(weekly).id == first.id
      assert Repo.reload!(split).deleted_at == nil
    end

    test "adopts a marked transaction from before the start date, which then follows the expense",
         c do
      older = expense!(c.h, "Altbau", 5000, "2026-02-20")
      older_ynab = imported!(c, older, %{category_id: c.treats})
      unmarked = expense!(c.h, "Altlast", 1000, "2026-02-21")

      assert switch_on(c) == {:ok, %{adopted: 1, created: 0, unadoptable: 0, left: 0}}
      assert linked(older).id == older_ynab.id
      assert linked(unmarked) == nil

      changed =
        Map.merge(Expenses.input(older), %{
          amount_cents: 6000,
          original_amount: 6000,
          date: ~D[2026-02-10]
        })

      {:ok, older} = Expenses.update_expense(scope_of(c.h.ben), older, changed)

      assert %{id: id, amount: -3000, date: ~D[2026-02-10], category_id: treats} = linked(older)
      assert {id, treats} == {older_ynab.id, c.treats}

      {:ok, _deleted} = Expenses.delete_expense(scope_of(c.h.ben), older)
      assert Repo.reload!(older_ynab).deleted_at
    end

    test "books every expense without a YNAB connection", c do
      Repo.delete_all(Ynab.CategoryMapping)
      Repo.delete_all(Ynab.Connection)
      older = expense!(c.h, "Altbau", 5000, "2025-02-20")

      assert switch_on(c) == {:ok, %{adopted: 0, created: 1, unadoptable: 0, left: 0}}
      assert %{amount: -2500} = linked(older)
      assert Repo.get!(Link, c.h.anna).start_date == nil
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
      assert Repo.get(Ynab.Connection, c.h.anna)
      assert BudgetLink.account_choices(scope_of(c.h.anna)) |> Enum.map(& &1.id) == [c.account.id]
    end
  end

  describe "after switching on" do
    setup c do
      older = expense!(c.h, "Altbau", 5000, "2026-02-20")
      {:ok, _counts} = switch_on(c)
      %{older: older}
    end

    test "an older expense gets no transaction when it changes", c do
      changed = Map.merge(Expenses.input(c.older), %{amount_cents: 6000, original_amount: 6000})
      {:ok, older} = Expenses.update_expense(scope_of(c.h.ben), c.older, changed)

      assert linked(older) == nil
    end

    test "an older expense gets one once moved after the start date", c do
      {:ok, older} =
        Expenses.update_expense(
          scope_of(c.h.ben),
          c.older,
          Map.put(Expenses.input(c.older), :date, ~D[2026-03-02])
        )

      assert %{amount: -2500, date: ~D[2026-03-02]} = linked(older)
    end

    test "an older expense entered after the switch gets one", c do
      backdated = expense!(c.h, "Nachtrag", 1000, "2026-01-15")

      assert %{amount: -500, date: ~D[2026-01-15]} = linked(backdated)
    end

    test "the account takes no entries and offers no reconcile", c do
      account = Ledger.get_account!(budget_scope(), c.account.id)
      refute Account.takes_entries?(account)
      refute Account.reconcilable?(account)
    end
  end
end
