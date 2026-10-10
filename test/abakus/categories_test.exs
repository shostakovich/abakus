defmodule Abakus.CategoriesTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Categories
  alias Abakus.Categories.{Assignment, Category, CategoryGroup}
  alias Abakus.Names

  describe "ready_to_assign!/0" do
    test "is YNAB's internal category, created by the migrations" do
      category = Categories.ready_to_assign!() |> Repo.preload(:category_group)

      assert %Category{name: "Inflow: Ready to Assign", internal: true} = category

      assert %CategoryGroup{name: "Internal Master Category", internal: true} =
               category.category_group

      assert category.lookup_key == Names.lookup_key(category.name)
      assert %DateTime{} = category.inserted_at
    end

    test "is not listed and cannot be changed" do
      category = Categories.ready_to_assign!() |> Repo.preload(:category_group)

      assert Categories.list_category_groups() == []
      assert {:error, changeset} = Categories.update_category(category, %{name: "Einnahmen"})
      assert %{internal: ["kann nicht geändert werden"]} = errors_on(changeset)

      assert {:error, changeset} =
               Categories.update_category_group(category.category_group, %{hidden: true})

      assert %{internal: ["kann nicht geändert werden"]} = errors_on(changeset)
    end
  end

  describe "category groups" do
    test "store the name as entered" do
      assert {:ok, group} =
               Categories.create_category_group(%{name: "🏠 Wohnen", note: "Fix", position: 2})

      assert %CategoryGroup{name: "🏠 Wohnen", note: "Fix", hidden: false, internal: false} =
               group

      assert {:ok, %CategoryGroup{name: "🏡 Haus", hidden: true}} =
               Categories.update_category_group(group, %{name: "🏡 Haus", hidden: true})
    end

    test "need a name and a position from zero" do
      assert {:error, changeset} = Categories.create_category_group(%{name: "", position: -1})

      assert %{name: ["can't be blank"], position: ["must be greater than or equal to 0"]} =
               errors_on(changeset)
    end

    test "cannot be made internal" do
      assert {:ok, %CategoryGroup{internal: false}} =
               Categories.create_category_group(%{name: "X", internal: true})
    end

    test "with categories cannot be deleted" do
      group = category_group_fixture()
      category_fixture(category_group_id: group.id)

      assert_raise Ecto.ConstraintError, fn -> Repo.delete(group) end
    end
  end

  test "list_category_groups/0 lists groups and categories in order, without internal ones" do
    second = category_group_fixture(position: 2)
    first = category_group_fixture(position: 1)
    b = category_fixture(category_group_id: first.id, position: 1)
    a = category_fixture(category_group_id: first.id, position: 0)
    hidden = category_fixture(category_group_id: second.id, hidden: true)

    assert [
             %{id: first_id, categories: [%{id: a_id}, %{id: b_id}]},
             %{id: second_id, categories: [%{id: hidden_id}]}
           ] =
             Categories.list_category_groups()

    assert {first_id, a_id, b_id, second_id, hidden_id} ==
             {first.id, a.id, b.id, second.id, hidden.id}
  end

  test "list_category_groups(internal: true) lists the internal group with Ready to Assign first" do
    group = category_group_fixture(position: 0)
    category = category_fixture(category_group_id: group.id)
    ready_to_assign = Categories.ready_to_assign!()

    assert [
             %{internal: true, categories: [rta]},
             %{id: group_id, categories: [%{id: category_id}]}
           ] =
             Categories.list_category_groups(internal: true)

    assert {rta.id, group_id, category_id} == {ready_to_assign.id, group.id, category.id}
  end

  test "new groups and categories without a position go to the end" do
    first = category_group_fixture(position: 5)
    category_fixture(category_group_id: first.id, position: 3)

    assert {:ok, %CategoryGroup{position: 6} = group} =
             Categories.create_category_group(%{name: "🎉 Freizeit"})

    assert {:ok, %Category{position: 4}} =
             Categories.create_category(%{name: "Kino", category_group_id: first.id})

    assert {:ok, %Category{position: 0}} =
             Categories.create_category(%{name: "Kino", category_group_id: group.id})
  end

  describe "categories" do
    test "store name, note, hidden and position with the lookup key" do
      group = category_group_fixture()

      assert {:ok, category} =
               Categories.create_category(%{
                 category_group_id: group.id,
                 name: "🛒 Lebensmittel",
                 note: "Supermarkt",
                 hidden: true,
                 position: 4
               })

      assert %Category{
               lookup_key: "lebensmittel",
               note: "Supermarkt",
               hidden: true,
               position: 4,
               internal: false
             } =
               category
    end

    test "need a name and an existing, regular group" do
      assert {:error, changeset} = Categories.create_category(%{name: ""})

      assert %{name: ["can't be blank"], category_group_id: ["can't be blank"]} =
               errors_on(changeset)

      assert {:error, changeset} = Categories.create_category(%{name: "X", category_group_id: -1})
      assert %{category_group_id: ["does not exist"]} = errors_on(changeset)
      assert german(changeset, :category_group_id) == ["existiert nicht"]

      internal_group_id = Categories.ready_to_assign!().category_group_id

      assert {:error, changeset} =
               Categories.create_category(%{name: "X", category_group_id: internal_group_id})

      assert %{category_group_id: ["ist intern"]} = errors_on(changeset)
    end

    test "move between regular groups" do
      category = category_fixture()
      other = category_group_fixture()

      assert {:ok, %Category{category_group_id: group_id}} =
               Categories.update_category(category, %{category_group_id: other.id})

      assert group_id == other.id

      internal_group_id = Categories.ready_to_assign!().category_group_id

      assert {:error, changeset} =
               Categories.update_category(category, %{category_group_id: internal_group_id})

      assert %{category_group_id: ["ist intern"]} = errors_on(changeset)
    end

    test "renaming updates the lookup key" do
      category = category_fixture(name: "🛒 Lebensmittel")

      assert {:ok, %Category{lookup_key: "essen"}} =
               Categories.update_category(category, %{name: "🍎 Essen"})

      assert {:ok, %Category{id: id}} = Categories.find_category_by_name("essen")
      assert id == category.id
      assert Categories.find_category_by_name("lebensmittel") == {:error, :not_found}
    end

    test "cannot take Ready to Assign's lookup key" do
      group = category_group_fixture()

      assert {:error, changeset} =
               Categories.create_category(%{
                 category_group_id: group.id,
                 name: "💰 INFLOW: Ready to Assign"
               })

      assert %{name: ["ist für „Zu verteilen“ reserviert"]} = errors_on(changeset)

      assert {:error, changeset} =
               Categories.update_category(category_fixture(), %{name: "Inflow: Ready to Assign"})

      assert %{name: ["ist für „Zu verteilen“ reserviert"]} = errors_on(changeset)
    end

    test "may share a lookup key" do
      group = category_group_fixture()
      old = category_fixture(category_group_id: group.id, name: "Urlaub", hidden: true)
      new = category_fixture(category_group_id: group.id, name: "🏖️ Urlaub")

      assert old.lookup_key == new.lookup_key
    end

    test "with assignments cannot be deleted" do
      category = category_fixture()
      {:ok, _} = Categories.assign(category, ~D[2026-10-01], 100)

      assert_raise Ecto.ConstraintError, fn -> Repo.delete(category) end
    end
  end

  describe "find_category_by_name/1" do
    test "ignores emoji and case" do
      category = category_fixture(name: "🛒 Lebensmittel")

      assert {:ok, %Category{id: id}} = Categories.find_category_by_name("LEBENSMITTEL")
      assert id == category.id
    end

    test "finds a category hidden in YNAB like any other" do
      hidden = category_fixture(name: "Altlast", hidden: true)

      assert {:ok, %Category{id: id}} = Categories.find_category_by_name("altlast")
      assert id == hidden.id
    end

    test "finds Ready to Assign" do
      id = Categories.ready_to_assign!().id

      assert {:ok, %Category{id: ^id}} =
               Categories.find_category_by_name("inflow: ready to assign")
    end

    test "never finds a regular category under Ready to Assign's name" do
      id = Categories.ready_to_assign!().id

      # Written past the changeset, which refuses the name.
      Repo.insert!(%Category{
        category_group_id: category_group_fixture().id,
        name: "Inflow: Ready to Assign",
        lookup_key: "inflow: ready to assign"
      })

      assert {:ok, %Category{id: ^id}} =
               Categories.find_category_by_name("Inflow: Ready to Assign")
    end

    test "is ambiguous between categories with the same name, hidden in YNAB or not" do
      category_fixture(name: "🚗 Auto")
      category_fixture(name: "Auto")

      assert Categories.find_category_by_name("auto") == {:error, :ambiguous}

      category_fixture(name: "Urlaub", hidden: true)
      category_fixture(name: "🏖️ Urlaub")

      assert Categories.find_category_by_name("urlaub") == {:error, :ambiguous}
    end

    test "reports unknown names" do
      assert Categories.find_category_by_name("Gibt es nicht") == {:error, :not_found}
    end
  end

  describe "assign/3" do
    test "sets and replaces the amount for a category and month" do
      category = category_fixture()

      assert {:ok, %Assignment{id: id, amount: 10_000}} =
               Categories.assign(category, ~D[2026-10-01], 10_000)

      assert {:ok, %Assignment{id: ^id, amount: -500}} =
               Categories.assign(category, ~D[2026-10-01], -500)

      assert {:ok, %Assignment{id: other_id}} = Categories.assign(category, ~D[2026-11-01], 0)
      assert other_id != id
      assert Repo.get!(Assignment, id).amount == -500
    end

    test "any day stands for its month" do
      category = category_fixture()

      assert {:ok, %Assignment{id: id, month: ~D[2026-10-01]}} =
               Categories.assign(category, ~D[2026-10-15], 100)

      assert {:ok, %Assignment{id: ^id, amount: 200}} =
               Categories.assign(category, "2026-10-31", 200)
    end

    test "stores the first of the month" do
      changeset =
        Assignment.changeset(%Assignment{category_id: category_fixture().id}, %{
          month: "2026-10-15",
          amount: 1
        })

      assert get_change(changeset, :month) == ~D[2026-10-01]
    end

    test "needs whole cents" do
      category = category_fixture()

      assert {:error, changeset} = Categories.assign(category, ~D[2026-10-01], 1.5)
      assert %{amount: ["is invalid"]} = errors_on(changeset)

      assert {:error, changeset} = Categories.assign(category, nil, nil)
      assert %{month: ["can't be blank"], amount: ["can't be blank"]} = errors_on(changeset)
    end

    test "takes amounts up to 100 billion euros either way" do
      category = category_fixture()

      assert {:ok, _} = Categories.assign(category, ~D[2026-10-01], 10_000_000_000_000)
      assert {:ok, _} = Categories.assign(category, ~D[2026-10-01], -10_000_000_000_000)

      for amount <- [10_000_000_000_001, -(2 ** 70), 2 ** 70] do
        assert {:error, changeset} = Categories.assign(category, ~D[2026-10-01], amount)
        assert %{amount: [message]} = errors_on(changeset)
        assert message =~ "100.000.000.000"
      end
    end

    test "refuses internal categories" do
      assert {:error, changeset} =
               Categories.assign(Categories.ready_to_assign!(), ~D[2026-10-01], 100)

      assert %{category_id: ["ist intern"]} = errors_on(changeset)
    end

    test "one assignment per category and month" do
      category = category_fixture()

      changeset =
        Assignment.changeset(%Assignment{category_id: category.id}, %{
          month: ~D[2026-10-01],
          amount: 1
        })

      assert {:ok, _} = Repo.insert(changeset)
      assert {:error, changeset} = Repo.insert(changeset)
      assert %{category_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "needs an existing category" do
      assert {:error, changeset} = Categories.assign(%Category{id: -1}, ~D[2026-10-01], 1)
      assert %{category_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "move_assigned/4" do
    test "moves an amount between two categories' assignments in the month" do
      groceries = category_fixture()
      rent = category_fixture()
      Categories.assign(groceries, ~D[2026-10-01], 10_000)

      assert {:ok, 3_000} = Categories.move_assigned(groceries, rent, ~D[2026-10-15], 3_000)

      assert assigned(groceries, ~D[2026-10-01]) == 7_000
      assert assigned(rent, ~D[2026-10-01]) == 3_000
    end

    test "takes from or gives to Zu verteilen, also beyond what is there" do
      groceries = category_fixture()

      assert {:ok, 5_000} =
               Categories.move_assigned(:ready_to_assign, groceries, ~D[2026-10-01], 5_000)

      assert {:ok, 7_000} =
               Categories.move_assigned(groceries, :ready_to_assign, ~D[2026-10-01], 7_000)

      assert assigned(groceries, ~D[2026-10-01]) == -2_000
    end

    test "changes nothing when one side is refused" do
      groceries = category_fixture()
      Categories.assign(groceries, ~D[2026-10-01], 1_000)

      assert {:error, changeset} =
               Categories.move_assigned(
                 groceries,
                 Categories.ready_to_assign!(),
                 ~D[2026-10-01],
                 500
               )

      assert %{category_id: ["ist intern"]} = errors_on(changeset)
      assert assigned(groceries, ~D[2026-10-01]) == 1_000
    end
  end

  describe "reset_assignments/2" do
    test "resets what every category, hidden in YNAB or not, has assigned in the month" do
      groceries = category_fixture()
      rent = category_fixture()
      hidden = category_fixture(hidden: true)
      for c <- [groceries, rent, hidden], do: Categories.assign(c, ~D[2026-10-01], 1_000)
      Categories.assign(groceries, ~D[2026-11-01], 1_000)

      assert :ok = Categories.reset_assignments(~D[2026-10-15])

      assert assigned(groceries, ~D[2026-10-01]) == 0
      assert assigned(rent, ~D[2026-10-01]) == 0
      assert assigned(hidden, ~D[2026-10-01]) == 0
      assert assigned(groceries, ~D[2026-11-01]) == 1_000
    end

    test "resets one category" do
      groceries = category_fixture()
      rent = category_fixture()
      for c <- [groceries, rent], do: Categories.assign(c, ~D[2026-10-01], 1_000)

      assert :ok = Categories.reset_assignments(~D[2026-10-01], groceries)

      assert assigned(groceries, ~D[2026-10-01]) == 0
      assert assigned(rent, ~D[2026-10-01]) == 1_000
    end
  end

  defp assigned(category, month),
    do: Map.get(Categories.budget().assigned, {category.id, month}, 0)

  defp german(changeset, field) do
    for {^field, error} <- changeset.errors, do: AbakusWeb.CoreComponents.translate_error(error)
  end
end
