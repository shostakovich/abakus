defmodule Abakus.Categories.ScopeTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.UsersFixtures

  alias Abakus.{Categories, Ledger}
  alias Abakus.Categories.{Assignment, Category, CategoryGroup}

  @october ~D[2026-10-01]

  setup do
    owner = budget_scope()
    group = category_group_fixture(%{name: "Alltag"})
    category = category_fixture(%{name: "Lebensmittel", category_group_id: group.id})
    into = category_fixture(%{name: "Haushalt", category_group_id: group.id})
    {:ok, _assignment} = Categories.assign(owner, category, @october, 5_000)

    {:ok, _target} =
      Categories.set_target(owner, category, %{
        from_month: @october,
        cadence: :monthly,
        amount: 5_000
      })

    {:ok, _snooze} = Categories.snooze_target(owner, category, @october)
    account = account_fixture(%{name: "Giro"})

    transaction_fixture(%{account_id: account.id, category_id: category.id, cleared: :reconciled})

    %{
      owner: owner,
      other: user_scope_fixture(),
      group: group,
      category: category,
      into: into
    }
  end

  test "another user sees no accounts, categories or transactions of the owner", c do
    assert Categories.list_category_groups(c.other) == []
    assert Categories.find_category_by_name(c.other, "Lebensmittel") == {:error, :not_found}
    assert Categories.target_for(c.other, c.category, @october) == nil
    refute Categories.target_snoozed?(c.other, c.category, @october)
    refute Categories.reconciled_transactions?(c.other, c.category)
    assert Categories.income_by_payee(c.other) == %{}

    assert %{categories: [], activity: activity, assigned: assigned, targets: targets} =
             Categories.budget(c.other)

    assert {activity, assigned, targets} == {%{}, %{}, %{}}
    assert Ledger.list_accounts(c.other) == []
    assert Ledger.list_transactions(c.other, :all) == []

    assert [%{id: group_id}] = Categories.list_category_groups(c.owner)
    assert group_id == c.group.id
    assert Categories.reconciled_transactions?(c.owner, c.category)
  end

  test "each user has a Ready to Assign of their own", c do
    owner_rta = Categories.ready_to_assign!(c.owner)
    other_rta = Categories.ready_to_assign!(c.other)

    assert other_rta.id != owner_rta.id
    assert other_rta.user_id == c.other.user.id
    assert Categories.ready_to_assign!(c.other).id == other_rta.id

    assert [%{internal: true, categories: [%{id: id}]}] =
             Categories.list_category_groups(c.other, internal: true)

    assert id == other_rta.id
  end

  test "the owner's records are missing for another user", c do
    assert_raise Ecto.NoResultsError, fn ->
      Categories.update_category(c.other, c.category, %{name: "Meins"})
    end

    assert_raise Ecto.NoResultsError, fn ->
      Categories.update_category_group(c.other, c.group, %{name: "Meins"})
    end

    assert Categories.delete_category_group(c.other, c.group) == {:error, :not_found}
    assert Categories.delete_category(c.other, c.category, c.into) == {:error, :not_found}

    assert {:error, changeset} = Categories.assign(c.other, c.category, @october, 100)
    assert %{category_id: ["does not exist"]} = errors_on(changeset)

    assert {:error, changeset} =
             Categories.set_target(c.other, c.category, %{from_month: @october, cadence: :none})

    assert %{category_id: ["does not exist"]} = errors_on(changeset)

    assert {:error, changeset} = Categories.snooze_target(c.other, c.category, @october)
    assert %{category_id: ["does not exist"]} = errors_on(changeset)

    assert {:error, changeset} =
             Categories.create_category(c.other, %{name: "X", category_group_id: c.group.id})

    assert %{category_group_id: ["does not exist"]} = errors_on(changeset)
  end

  test "another user changes nothing of the owner's budget", c do
    :ok = Categories.unsnooze_target(c.other, c.category, @october)
    :ok = Categories.reset_assignments(c.other, @october, c.category)
    :ok = Categories.reset_assignments(c.other, @october)
    {:ok, []} = Categories.fill_underfunded(c.other, @october, @october)

    assert Categories.target_snoozed?(c.owner, c.category, @october)
    assert [%Assignment{amount: 5_000}] = Repo.all(Assignment)
  end

  test "another user cannot book or remember the owner's categories", c do
    {:ok, account} = Ledger.create_account(c.other, %{name: "Giro", kind: :checking})

    assert {:error, changeset} =
             Ledger.create_transaction(c.other, %{
               account_id: account.id,
               date: ~D[2026-10-09],
               amount: -100,
               category_id: c.category.id
             })

    assert %{category_id: ["does not exist"]} = errors_on(changeset)

    assert {:error, changeset} =
             Ledger.create_payee(c.other, %{name: "Rewe", last_category_id: c.category.id})

    assert %{last_category_id: ["does not exist"]} = errors_on(changeset)
  end

  test "a category or group without its user is refused, not written", c do
    assert %{user_id: ["can't be blank"]} =
             errors_on(CategoryGroup.changeset(%CategoryGroup{}, %{name: "Alltag"}))

    assert %{user_id: ["can't be blank"]} =
             errors_on(
               Category.changeset(%Category{}, %{name: "Kino", category_group_id: c.group.id})
             )
  end
end
