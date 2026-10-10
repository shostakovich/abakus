defmodule Abakus.Categories.DeleteTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Budget, Categories, Ledger}
  alias Abakus.Categories.{Assignment, Category, CategoryGroup, TargetSnooze, TargetVersion}
  alias Abakus.Ledger.{Payee, Subtransaction, Transaction}

  @september ~D[2026-09-01]
  @october ~D[2026-10-01]

  setup do
    group = category_group_fixture(name: "🎉 Freizeit")

    %{
      checking: account_fixture(kind: :checking),
      depot: account_fixture(kind: :tracking),
      rta: Categories.ready_to_assign!(),
      group: group,
      movies: category_fixture(name: "🎬 Kino", category_group_id: group.id),
      leisure: category_fixture(name: "🎳 Freizeit", category_group_id: group.id)
    }
  end

  defp months, do: Budget.months(Categories.budget(), @october)

  defp totals do
    Enum.map(months(), fn month ->
      {month.month, month.ready_to_assign, Enum.sum(Enum.map(month.categories, & &1.available))}
    end)
  end

  defp assignments(category) do
    Repo.all(
      from a in Assignment,
        where: a.category_id == ^category.id,
        order_by: a.month,
        select: {a.month, a.amount}
    )
  end

  describe "scenario: deleting moves everything to the chosen category" do
    setup c do
      transaction_fixture(account_id: c.checking.id, category_id: c.rta.id, amount: 100_000)
      Categories.assign(c.movies, @september, 3_000)
      Categories.assign(c.movies, @october, 2_000)
      Categories.assign(c.leisure, @october, 5_000)

      ticket =
        transaction_fixture(
          account_id: c.checking.id,
          payee_name: "Kino am Markt",
          category_id: c.movies.id,
          amount: -1_000,
          date: ~D[2026-09-12]
        )

      split =
        transaction_fixture(
          account_id: c.checking.id,
          amount: -3_000,
          date: ~D[2026-10-03],
          subtransactions: [
            %{amount: -1_000, category_id: c.movies.id},
            %{amount: -2_000, category_id: c.leisure.id}
          ]
        )

      transfer =
        transaction_fixture(
          account_id: c.checking.id,
          payee_id: c.depot.transfer_payee.id,
          category_id: c.movies.id,
          amount: -1_000,
          date: ~D[2026-10-05]
        )

      deleted = transaction_fixture(account_id: c.checking.id, category_id: c.movies.id)
      {:ok, _deleted} = Ledger.delete_transaction(deleted)

      Categories.set_target(c.movies, %{from_month: @october, cadence: :monthly, amount: 2_000})
      Categories.snooze_target(c.movies, @october)

      %{ticket: ticket, split: split, transfer: transfer, deleted: deleted}
    end

    test "Kino with 20,00 € available goes into Freizeit", c do
      available = fn category ->
        Enum.find(List.last(months()).categories, &(&1.category_id == category.id)).available
      end

      assert available.(c.movies) == 2_000
      before = totals()

      assert {:ok, %Category{}} = Categories.delete_category(c.movies, c.leisure)

      for transaction <- [c.ticket, c.transfer, c.deleted] do
        assert Repo.reload!(transaction).category_id == c.leisure.id
      end

      assert Repo.all(
               from s in Subtransaction,
                 where: s.transaction_id == ^c.split.id,
                 select: s.category_id
             ) == [c.leisure.id, c.leisure.id]

      assert Repo.get_by!(Payee, name: "Kino am Markt").last_category_id == c.leisure.id
      assert assignments(c.leisure) == [{@september, 3_000}, {@october, 7_000}]
      assert totals() == before

      refute Repo.reload(c.movies)

      assert [%CategoryGroup{categories: [%Category{name: "🎳 Freizeit"}]}] =
               Categories.list_category_groups()

      refute Repo.exists?(from a in Assignment, where: a.category_id == ^c.movies.id)
      refute Repo.exists?(from v in TargetVersion, where: v.category_id == ^c.movies.id)
      refute Repo.exists?(from s in TargetSnooze, where: s.category_id == ^c.movies.id)
    end
  end

  describe "scenario: deleting touches reconciled transactions only after confirmation" do
    setup c do
      transaction =
        transaction_fixture(
          account_id: c.checking.id,
          category_id: c.movies.id,
          cleared: :reconciled
        )

      %{transaction: transaction}
    end

    test "is refused without confirmation and moves them with it", c do
      assert Categories.reconciled_transactions?(c.movies)
      refute Categories.reconciled_transactions?(c.leisure)

      assert {:error, :reconciled} = Categories.delete_category(c.movies, c.leisure)
      assert Repo.reload(c.movies)

      assert {:ok, _category} =
               Categories.delete_category(c.movies, c.leisure, reconciled: :confirmed)

      assert %Transaction{category_id: category_id, cleared: :reconciled} =
               Repo.reload!(c.transaction)

      assert category_id == c.leisure.id
    end

    test "a reconciled split counts with its lines", c do
      transaction_fixture(
        account_id: c.checking.id,
        cleared: :reconciled,
        subtransactions: [
          %{amount: -500, category_id: c.leisure.id},
          %{amount: -750, category_id: c.rta.id}
        ]
      )

      assert Categories.reconciled_transactions?(c.leisure)
    end

    test "a deleted reconciled transaction does not count", c do
      {:ok, _deleted} = Ledger.delete_transaction(c.transaction, reconciled: :confirmed)

      refute Categories.reconciled_transactions?(c.movies)
      assert {:ok, _category} = Categories.delete_category(c.movies, c.leisure)
    end
  end

  describe "delete_category/3" do
    test "moves into a category of another group", c do
      other = category_fixture()
      Categories.assign(c.movies, @october, 1_000)

      assert {:ok, _category} = Categories.delete_category(c.movies, other)
      assert assignments(other) == [{@october, 1_000}]
    end

    test "refuses Ready to Assign, the category itself and a category that is gone", c do
      gone = category_fixture()
      Repo.delete!(gone)

      assert {:error, :target} = Categories.delete_category(c.movies, c.rta)
      assert {:error, :target} = Categories.delete_category(c.movies, c.movies)
      assert {:error, :target} = Categories.delete_category(c.movies, gone)
      assert Repo.reload(c.movies)
    end

    test "refuses Ready to Assign and a category that is gone as the one deleted", c do
      assert {:error, :internal} = Categories.delete_category(c.rta, c.leisure)
      Repo.delete!(c.movies)
      assert {:error, :not_found} = Categories.delete_category(c.movies, c.leisure)
    end
  end

  describe "delete_category_group/1" do
    test "deletes an empty group" do
      group = category_group_fixture()

      assert {:ok, %CategoryGroup{}} = Categories.delete_category_group(group)
      refute Repo.reload(group)
    end

    test "refuses a group with categories and the internal one", c do
      assert {:error, :not_empty} = Categories.delete_category_group(c.group)
      assert Repo.reload(c.group)

      internal = Repo.preload(c.rta, :category_group).category_group
      assert {:error, :internal} = Categories.delete_category_group(internal)
    end
  end
end
