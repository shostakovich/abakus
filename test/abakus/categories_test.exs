defmodule Abakus.CategoriesTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Categories
  alias Abakus.Categories.{Assignment, Category, CategoryGroup}
  alias Abakus.Names

  describe "ready_to_assign!/1" do
    test "is YNAB's internal category, created with its first use" do
      category = Categories.ready_to_assign!(budget_scope()) |> Repo.preload(:category_group)

      assert %Category{name: "Inflow: Ready to Assign", internal: true} = category

      assert %CategoryGroup{name: "Internal Master Category", internal: true} =
               category.category_group

      assert category.lookup_key == Names.lookup_key(category.name)
      assert %DateTime{} = category.inserted_at
    end

    test "is not listed and cannot be changed" do
      category = Categories.ready_to_assign!(budget_scope()) |> Repo.preload(:category_group)

      assert Categories.list_category_groups(budget_scope()) == []

      assert {:error, changeset} =
               Categories.update_category(budget_scope(), category, %{name: "Einnahmen"})

      assert %{internal: ["kann nicht geändert werden"]} = errors_on(changeset)

      assert {:error, changeset} =
               Categories.update_category_group(budget_scope(), category.category_group, %{
                 hidden: true
               })

      assert %{internal: ["kann nicht geändert werden"]} = errors_on(changeset)
    end
  end

  describe "category groups" do
    test "store the name as entered" do
      assert {:ok, group} =
               Categories.create_category_group(budget_scope(), %{
                 name: "🏠 Wohnen",
                 note: "Fix",
                 position: 2
               })

      assert %CategoryGroup{name: "🏠 Wohnen", note: "Fix", hidden: false, internal: false} =
               group

      assert {:ok, %CategoryGroup{name: "🏡 Haus", hidden: true}} =
               Categories.update_category_group(budget_scope(), group, %{
                 name: "🏡 Haus",
                 hidden: true
               })
    end

    test "need a name and a position from zero" do
      assert {:error, changeset} =
               Categories.create_category_group(budget_scope(), %{name: "", position: -1})

      assert %{name: ["can't be blank"], position: ["must be greater than or equal to 0"]} =
               errors_on(changeset)
    end

    test "cannot be made internal" do
      assert {:ok, %CategoryGroup{internal: false}} =
               Categories.create_category_group(budget_scope(), %{name: "X", internal: true})
    end

    test "with categories cannot be deleted" do
      group = category_group_fixture()
      category_fixture(category_group_id: group.id)

      assert_raise Ecto.ConstraintError, fn -> Repo.delete(group) end
    end
  end

  test "list_category_groups/1 lists groups and categories in order, without internal ones" do
    second = category_group_fixture(position: 2)
    first = category_group_fixture(position: 1)
    b = category_fixture(category_group_id: first.id, position: 1)
    a = category_fixture(category_group_id: first.id, position: 0)
    hidden = category_fixture(category_group_id: second.id, hidden: true)

    assert [
             %{id: first_id, categories: [%{id: a_id}, %{id: b_id}]},
             %{id: second_id, categories: [%{id: hidden_id}]}
           ] =
             Categories.list_category_groups(budget_scope())

    assert {first_id, a_id, b_id, second_id, hidden_id} ==
             {first.id, a.id, b.id, second.id, hidden.id}
  end

  test "list_category_groups(internal: true) lists the internal group with Ready to Assign first" do
    group = category_group_fixture(position: 0)
    category = category_fixture(category_group_id: group.id)
    ready_to_assign = Categories.ready_to_assign!(budget_scope())

    assert [
             %{internal: true, categories: [rta]},
             %{id: group_id, categories: [%{id: category_id}]}
           ] =
             Categories.list_category_groups(budget_scope(), internal: true)

    assert {rta.id, group_id, category_id} == {ready_to_assign.id, group.id, category.id}
  end

  test "new groups and categories without a position go to the end" do
    first = category_group_fixture(position: 5)
    category_fixture(category_group_id: first.id, position: 3)

    assert {:ok, %CategoryGroup{position: 6} = group} =
             Categories.create_category_group(budget_scope(), %{name: "🎉 Freizeit"})

    assert {:ok, %Category{position: 4}} =
             Categories.create_category(budget_scope(), %{
               name: "Kino",
               category_group_id: first.id
             })

    assert {:ok, %Category{position: 0}} =
             Categories.create_category(budget_scope(), %{
               name: "Kino",
               category_group_id: group.id
             })
  end

  describe "categories" do
    test "store name, note, hidden and position with the lookup key" do
      group = category_group_fixture()

      assert {:ok, category} =
               Categories.create_category(budget_scope(), %{
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
      assert {:error, changeset} = Categories.create_category(budget_scope(), %{name: ""})

      assert %{name: ["can't be blank"], category_group_id: ["can't be blank"]} =
               errors_on(changeset)

      assert {:error, changeset} =
               Categories.create_category(budget_scope(), %{
                 name: "X",
                 category_group_id: Ecto.UUID.generate()
               })

      assert %{category_group_id: ["does not exist"]} = errors_on(changeset)
      assert german(changeset, :category_group_id) == ["existiert nicht"]

      internal_group_id = Categories.ready_to_assign!(budget_scope()).category_group_id

      assert {:error, changeset} =
               Categories.create_category(budget_scope(), %{
                 name: "X",
                 category_group_id: internal_group_id
               })

      assert %{category_group_id: ["ist intern"]} = errors_on(changeset)
    end

    test "move between regular groups" do
      category = category_fixture()
      other = category_group_fixture()

      assert {:ok, %Category{category_group_id: group_id}} =
               Categories.update_category(budget_scope(), category, %{category_group_id: other.id})

      assert group_id == other.id

      internal_group_id = Categories.ready_to_assign!(budget_scope()).category_group_id

      assert {:error, changeset} =
               Categories.update_category(budget_scope(), category, %{
                 category_group_id: internal_group_id
               })

      assert %{category_group_id: ["ist intern"]} = errors_on(changeset)
    end

    test "renaming updates the lookup key" do
      category = category_fixture(name: "🛒 Lebensmittel")

      assert {:ok, %Category{lookup_key: "essen"}} =
               Categories.update_category(budget_scope(), category, %{name: "🍎 Essen"})

      assert {:ok, %Category{id: id}} = Categories.find_category_by_name(budget_scope(), "essen")
      assert id == category.id

      assert Categories.find_category_by_name(budget_scope(), "lebensmittel") ==
               {:error, :not_found}
    end

    test "cannot take Ready to Assign's lookup key" do
      group = category_group_fixture()

      assert {:error, changeset} =
               Categories.create_category(budget_scope(), %{
                 category_group_id: group.id,
                 name: "💰 INFLOW: Ready to Assign"
               })

      assert %{name: ["ist für „Zu verteilen“ reserviert"]} = errors_on(changeset)

      assert {:error, changeset} =
               Categories.update_category(budget_scope(), category_fixture(), %{
                 name: "Inflow: Ready to Assign"
               })

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
      {:ok, _} = Categories.assign(budget_scope(), category, ~D[2026-10-01], 100)

      assert_raise Ecto.ConstraintError, fn -> Repo.delete(category) end
    end
  end

  describe "find_category_by_name/2" do
    test "ignores emoji and case" do
      category = category_fixture(name: "🛒 Lebensmittel")

      assert {:ok, %Category{id: id}} =
               Categories.find_category_by_name(budget_scope(), "LEBENSMITTEL")

      assert id == category.id
    end

    test "finds a category hidden in YNAB like any other" do
      hidden = category_fixture(name: "Altlast", hidden: true)

      assert {:ok, %Category{id: id}} =
               Categories.find_category_by_name(budget_scope(), "altlast")

      assert id == hidden.id
    end

    test "finds Ready to Assign" do
      id = Categories.ready_to_assign!(budget_scope()).id

      assert {:ok, %Category{id: ^id}} =
               Categories.find_category_by_name(budget_scope(), "inflow: ready to assign")
    end

    test "never finds a regular category under Ready to Assign's name" do
      id = Categories.ready_to_assign!(budget_scope()).id

      # Written past the changeset, which refuses the name.
      group = category_group_fixture()

      Repo.insert!(%Category{
        user_id: group.user_id,
        category_group_id: group.id,
        name: "Inflow: Ready to Assign",
        lookup_key: "inflow: ready to assign"
      })

      assert {:ok, %Category{id: ^id}} =
               Categories.find_category_by_name(budget_scope(), "Inflow: Ready to Assign")
    end

    test "is ambiguous between categories with the same name, hidden in YNAB or not" do
      category_fixture(name: "🚗 Auto")
      category_fixture(name: "Auto")

      assert Categories.find_category_by_name(budget_scope(), "auto") == {:error, :ambiguous}

      category_fixture(name: "Urlaub", hidden: true)
      category_fixture(name: "🏖️ Urlaub")

      assert Categories.find_category_by_name(budget_scope(), "urlaub") == {:error, :ambiguous}
    end

    test "reports unknown names" do
      assert Categories.find_category_by_name(budget_scope(), "Gibt es nicht") ==
               {:error, :not_found}
    end
  end

  describe "assign/4" do
    test "sets and replaces the amount for a category and month" do
      category = category_fixture()

      assert {:ok, %Assignment{id: id, amount: 10_000}} =
               Categories.assign(budget_scope(), category, ~D[2026-10-01], 10_000)

      assert {:ok, %Assignment{id: ^id, amount: -500}} =
               Categories.assign(budget_scope(), category, ~D[2026-10-01], -500)

      assert {:ok, %Assignment{id: other_id}} =
               Categories.assign(budget_scope(), category, ~D[2026-11-01], 0)

      assert other_id != id
      assert Repo.get!(Assignment, id).amount == -500
    end

    test "names the assignment, like a target version and a snooze, after its category and month" do
      category = category_fixture()
      scope = budget_scope()

      assert {:ok, %{id: assignment}} = Categories.assign(scope, category, ~D[2026-10-15], 1)
      assert assignment == Abakus.Ids.assignment(category.id, ~D[2026-10-01])

      assert {:ok, %{id: version}} =
               Categories.set_target(scope, category, %{
                 from_month: ~D[2026-10-15],
                 cadence: :monthly,
                 amount: 100
               })

      assert version == Abakus.Ids.target_version(category.id, ~D[2026-10-01])

      assert {:ok, %{id: snooze}} = Categories.snooze_target(scope, category, ~D[2026-10-15])
      assert snooze == Abakus.Ids.target_snooze(category.id, ~D[2026-10-01])
    end

    test "any day stands for its month" do
      category = category_fixture()

      assert {:ok, %Assignment{id: id, month: ~D[2026-10-01]}} =
               Categories.assign(budget_scope(), category, ~D[2026-10-15], 100)

      assert {:ok, %Assignment{id: ^id, amount: 200}} =
               Categories.assign(budget_scope(), category, "2026-10-31", 200)
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

      assert {:error, changeset} =
               Categories.assign(budget_scope(), category, ~D[2026-10-01], 1.5)

      assert %{amount: ["is invalid"]} = errors_on(changeset)

      assert {:error, changeset} = Categories.assign(budget_scope(), category, nil, nil)
      assert %{month: ["can't be blank"], amount: ["can't be blank"]} = errors_on(changeset)
    end

    test "takes amounts up to 100 billion euros either way" do
      category = category_fixture()

      assert {:ok, _} =
               Categories.assign(budget_scope(), category, ~D[2026-10-01], 10_000_000_000_000)

      assert {:ok, _} =
               Categories.assign(budget_scope(), category, ~D[2026-10-01], -10_000_000_000_000)

      for amount <- [10_000_000_000_001, -(2 ** 70), 2 ** 70] do
        assert {:error, changeset} =
                 Categories.assign(budget_scope(), category, ~D[2026-10-01], amount)

        assert %{amount: [message]} = errors_on(changeset)
        assert message =~ "100.000.000.000"
      end
    end

    test "refuses internal categories" do
      assert {:error, changeset} =
               Categories.assign(
                 budget_scope(),
                 Categories.ready_to_assign!(budget_scope()),
                 ~D[2026-10-01],
                 100
               )

      assert %{category_id: ["ist intern"]} = errors_on(changeset)
    end

    test "one assignment per category and month" do
      category = category_fixture()

      changeset =
        Assignment.changeset(%Assignment{category_id: category.id, user_id: category.user_id}, %{
          month: ~D[2026-10-01],
          amount: 1
        })

      assert {:ok, _} = Repo.insert(changeset)
      assert {:error, changeset} = Repo.insert(changeset)
      assert %{category_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "needs an existing category" do
      assert {:error, changeset} =
               Categories.assign(
                 budget_scope(),
                 %Category{id: Ecto.UUID.generate()},
                 ~D[2026-10-01],
                 1
               )

      assert %{category_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "move_assigned/5" do
    test "moves an amount between two categories' assignments in the month" do
      groceries = category_fixture()
      rent = category_fixture()
      Categories.assign(budget_scope(), groceries, ~D[2026-10-01], 10_000)

      assert {:ok, 3_000} =
               Categories.move_assigned(budget_scope(), groceries, rent, ~D[2026-10-15], 3_000)

      assert assigned(groceries, ~D[2026-10-01]) == 7_000
      assert assigned(rent, ~D[2026-10-01]) == 3_000
    end

    test "takes from or gives to Zu verteilen, also beyond what is there" do
      groceries = category_fixture()

      assert {:ok, 5_000} =
               Categories.move_assigned(
                 budget_scope(),
                 :ready_to_assign,
                 groceries,
                 ~D[2026-10-01],
                 5_000
               )

      assert {:ok, 7_000} =
               Categories.move_assigned(
                 budget_scope(),
                 groceries,
                 :ready_to_assign,
                 ~D[2026-10-01],
                 7_000
               )

      assert assigned(groceries, ~D[2026-10-01]) == -2_000
    end

    test "changes nothing when one side is refused" do
      groceries = category_fixture()
      Categories.assign(budget_scope(), groceries, ~D[2026-10-01], 1_000)

      assert {:error, changeset} =
               Categories.move_assigned(
                 budget_scope(),
                 groceries,
                 Categories.ready_to_assign!(budget_scope()),
                 ~D[2026-10-01],
                 500
               )

      assert %{category_id: ["ist intern"]} = errors_on(changeset)
      assert assigned(groceries, ~D[2026-10-01]) == 1_000
    end
  end

  describe "reset_assignments/3" do
    test "resets what every category, hidden in YNAB or not, has assigned in the month" do
      groceries = category_fixture()
      rent = category_fixture()
      hidden = category_fixture(hidden: true)

      for c <- [groceries, rent, hidden],
          do: Categories.assign(budget_scope(), c, ~D[2026-10-01], 1_000)

      Categories.assign(budget_scope(), groceries, ~D[2026-11-01], 1_000)

      assert :ok = Categories.reset_assignments(budget_scope(), ~D[2026-10-15])

      assert assigned(groceries, ~D[2026-10-01]) == 0
      assert assigned(rent, ~D[2026-10-01]) == 0
      assert assigned(hidden, ~D[2026-10-01]) == 0
      assert assigned(groceries, ~D[2026-11-01]) == 1_000
    end

    test "resets one category" do
      groceries = category_fixture()
      rent = category_fixture()
      for c <- [groceries, rent], do: Categories.assign(budget_scope(), c, ~D[2026-10-01], 1_000)

      assert :ok = Categories.reset_assignments(budget_scope(), ~D[2026-10-01], groceries)

      assert assigned(groceries, ~D[2026-10-01]) == 0
      assert assigned(rent, ~D[2026-10-01]) == 1_000
    end
  end

  describe "moving categories and groups" do
    setup do
      wohnen = category_group_fixture(name: "Wohnen")
      essen = category_group_fixture(name: "Essen")
      leer = category_group_fixture(name: "Leer")

      [miete, strom, wasser] =
        for name <- ["Miete", "Strom", "Wasser"],
            do: category_fixture(name: name, category_group_id: wohnen.id)

      [markt, kantine] =
        for name <- ["Markt", "Kantine"],
            do: category_fixture(name: name, category_group_id: essen.id)

      %{
        wohnen: wohnen,
        essen: essen,
        leer: leer,
        miete: miete,
        strom: strom,
        wasser: wasser,
        markt: markt,
        kantine: kantine
      }
    end

    defp budget_order do
      for group <- Categories.list_category_groups(budget_scope()),
          do: {group.name, group.position, Enum.map(group.categories, &{&1.name, &1.position})}
    end

    defp names(rows), do: Enum.map(rows, & &1.name)

    defp messages_after(cursor) do
      Repo.all(
        from m in Abakus.Sync.Message,
          where: m.id > ^cursor and m.table in ["categories", "category_groups"],
          select: {m.row_id, m.column, m.value}
      )
    end

    test "move_category/4 puts a category before another of its group and renumbers the group",
         c do
      assert {:ok, categories} =
               Categories.move_category(budget_scope(), c.wasser.id, c.wohnen.id, c.miete.id)

      assert names(categories) == ["Wasser", "Miete", "Strom"]

      assert [{"Wohnen", 0, [{"Wasser", 0}, {"Miete", 1}, {"Strom", 2}]} | _] = budget_order()
    end

    test "move_category/4 without another category puts it at its group's end", c do
      assert {:ok, categories} =
               Categories.move_category(budget_scope(), c.miete.id, c.wohnen.id, nil)

      assert names(categories) == ["Strom", "Wasser", "Miete"]
    end

    test "move_category/4 moves a category to the start of another group and renumbers both", c do
      assert {:ok, categories} =
               Categories.move_category(budget_scope(), c.miete.id, c.essen.id, c.markt.id)

      assert names(categories) == ["Miete", "Markt", "Kantine"]
      assert Repo.get!(Category, c.miete.id).category_group_id == c.essen.id

      assert budget_order() == [
               {"Wohnen", 0, [{"Strom", 0}, {"Wasser", 1}]},
               {"Essen", 1, [{"Miete", 0}, {"Markt", 1}, {"Kantine", 2}]},
               {"Leer", 2, []}
             ]
    end

    test "move_category/4 moves a category into the middle or to the end of another group", c do
      assert {:ok, categories} =
               Categories.move_category(budget_scope(), c.strom.id, c.essen.id, c.kantine.id)

      assert names(categories) == ["Markt", "Strom", "Kantine"]

      assert {:ok, categories} =
               Categories.move_category(budget_scope(), c.wasser.id, c.essen.id, nil)

      assert names(categories) == ["Markt", "Strom", "Kantine", "Wasser"]

      assert [
               {"Wohnen", 0, [{"Miete", 0}]},
               {"Essen", 1, [{"Markt", 0}, {"Strom", 1}, {"Kantine", 2}, {"Wasser", 3}]},
               _leer
             ] = budget_order()
    end

    test "move_category/4 moves a category into an empty group", c do
      assert {:ok, [%Category{name: "Strom", position: 0}]} =
               Categories.move_category(budget_scope(), c.strom.id, c.leer.id, nil)

      assert [{"Wohnen", 0, [{"Miete", 0}, {"Wasser", 1}]}, _essen, {"Leer", 2, [{"Strom", 0}]}] =
               budget_order()
    end

    test "move_category/4 writes the group and only the changed positions, as messages", c do
      cursor = Abakus.Sync.cursor(budget_scope())

      assert {:ok, _categories} =
               Categories.move_category(budget_scope(), c.miete.id, c.essen.id, c.kantine.id)

      assert Enum.sort(messages_after(cursor)) ==
               Enum.sort([
                 {c.miete.id, "category_group_id", Jason.encode!(c.essen.id)},
                 {c.miete.id, "position", "1"},
                 {c.kantine.id, "position", "2"},
                 {c.strom.id, "position", "0"},
                 {c.wasser.id, "position", "1"}
               ])
    end

    test "move_category/4 to the category's own place writes nothing", c do
      cursor = Abakus.Sync.cursor(budget_scope())

      assert {:ok, categories} =
               Categories.move_category(budget_scope(), c.strom.id, c.wohnen.id, c.wasser.id)

      assert names(categories) == ["Miete", "Strom", "Wasser"]
      assert messages_after(cursor) == []
    end

    test "move_category/4 renumbers equal positions, which order by id", c do
      for category <- [c.miete, c.strom, c.wasser],
          do:
            {:ok, _category} =
              Categories.update_category(budget_scope(), category, %{position: 5})

      [first, second, third] = Enum.sort_by([c.miete, c.strom, c.wasser], & &1.id)

      assert {:ok, categories} =
               Categories.move_category(budget_scope(), third.id, c.wohnen.id, second.id)

      assert Enum.map(categories, &{&1.id, &1.position}) ==
               [{first.id, 0}, {third.id, 1}, {second.id, 2}]
    end

    test "move_category/4 refuses another group with a category of the same lookup key", c do
      category_fixture(name: "🔌 strom", category_group_id: c.essen.id)
      before = budget_order()

      assert Categories.move_category(budget_scope(), c.strom.id, c.essen.id, nil) ==
               {:error, :name_taken}

      assert budget_order() == before
    end

    test "move_category/4 within its group never clashes on a shared lookup key", c do
      category_fixture(name: "🔌 Strom", category_group_id: c.wohnen.id)

      assert {:ok, categories} =
               Categories.move_category(budget_scope(), c.strom.id, c.wohnen.id, nil)

      assert names(categories) == ["Miete", "Wasser", "🔌 Strom", "Strom"]
    end

    test "move_category/4 refuses a place outside the target group or at the category itself",
         c do
      before = budget_order()

      assert Categories.move_category(budget_scope(), c.miete.id, c.wohnen.id, c.markt.id) ==
               {:error, :not_in_group}

      assert Categories.move_category(budget_scope(), c.miete.id, c.essen.id, c.strom.id) ==
               {:error, :not_in_group}

      assert Categories.move_category(budget_scope(), c.miete.id, c.wohnen.id, c.miete.id) ==
               {:error, :not_in_group}

      assert budget_order() == before
    end

    test "move_category/4 refuses Ready to Assign and its internal group", c do
      ready_to_assign = Categories.ready_to_assign!(budget_scope())
      before = budget_order()

      assert Categories.move_category(budget_scope(), ready_to_assign.id, c.wohnen.id, nil) ==
               {:error, :internal}

      assert Categories.move_category(
               budget_scope(),
               c.miete.id,
               ready_to_assign.category_group_id,
               nil
             ) == {:error, :target}

      assert Categories.move_category(budget_scope(), c.miete.id, c.wohnen.id, ready_to_assign.id) ==
               {:error, :not_in_group}

      assert budget_order() == before
    end

    test "move_category/4 refuses deleted categories and groups", c do
      {:ok, _deleted} = Categories.delete_category(budget_scope(), c.wasser, c.miete)
      {:ok, _deleted} = Categories.delete_category_group(budget_scope(), c.leer)
      before = budget_order()

      assert Categories.move_category(budget_scope(), c.wasser.id, c.wohnen.id, nil) ==
               {:error, :not_found}

      assert Categories.move_category(budget_scope(), c.miete.id, c.wohnen.id, c.wasser.id) ==
               {:error, :not_in_group}

      assert Categories.move_category(budget_scope(), c.miete.id, c.leer.id, nil) ==
               {:error, :target}

      assert budget_order() == before
    end

    test "move_category/4 treats another user's categories and groups as missing", c do
      other = Abakus.UsersFixtures.user_scope_fixture()
      {:ok, foreign} = Categories.create_category_group(other, %{name: "Fremd"})
      before = budget_order()

      assert Categories.move_category(other, c.miete.id, foreign.id, nil) == {:error, :not_found}

      assert Categories.move_category(budget_scope(), c.miete.id, foreign.id, nil) ==
               {:error, :target}

      assert budget_order() == before
    end

    test "move_category_group/3 puts a group before another and renumbers the groups", c do
      assert {:ok, groups} =
               Categories.move_category_group(budget_scope(), c.leer.id, c.wohnen.id)

      assert names(groups) == ["Leer", "Wohnen", "Essen"]

      assert Enum.map(budget_order(), fn {name, position, _categories} -> {name, position} end) ==
               [{"Leer", 0}, {"Wohnen", 1}, {"Essen", 2}]
    end

    test "move_category_group/3 without another group puts it last", c do
      assert {:ok, groups} = Categories.move_category_group(budget_scope(), c.wohnen.id, nil)

      assert names(groups) == ["Essen", "Leer", "Wohnen"]
    end

    test "move_category_group/3 renumbers equal positions, which order by id", c do
      for group <- [c.wohnen, c.essen, c.leer],
          do:
            {:ok, _group} =
              Categories.update_category_group(budget_scope(), group, %{position: 5})

      [first, second, third] = Enum.sort_by([c.wohnen, c.essen, c.leer], & &1.id)

      assert {:ok, groups} = Categories.move_category_group(budget_scope(), third.id, second.id)

      assert Enum.map(groups, &{&1.id, &1.position}) ==
               [{first.id, 0}, {third.id, 1}, {second.id, 2}]
    end

    test "move_category_group/3 writes only the changed positions, as messages, none for its own place",
         c do
      cursor = Abakus.Sync.cursor(budget_scope())

      assert {:ok, _groups} =
               Categories.move_category_group(budget_scope(), c.essen.id, c.leer.id)

      assert messages_after(cursor) == []

      assert {:ok, _groups} =
               Categories.move_category_group(budget_scope(), c.leer.id, c.essen.id)

      assert Enum.sort(messages_after(cursor)) ==
               Enum.sort([{c.leer.id, "position", "1"}, {c.essen.id, "position", "2"}])
    end

    test "move_category_group/3 refuses the internal group and deleted or another user's groups",
         c do
      internal_id = Categories.ready_to_assign!(budget_scope()).category_group_id
      {:ok, _deleted} = Categories.delete_category_group(budget_scope(), c.leer)
      other = Abakus.UsersFixtures.user_scope_fixture()
      before = budget_order()

      assert Categories.move_category_group(budget_scope(), internal_id, nil) ==
               {:error, :internal}

      assert Categories.move_category_group(budget_scope(), c.wohnen.id, internal_id) ==
               {:error, :not_in_group}

      assert Categories.move_category_group(budget_scope(), c.leer.id, nil) ==
               {:error, :not_found}

      assert Categories.move_category_group(budget_scope(), c.wohnen.id, c.leer.id) ==
               {:error, :not_in_group}

      assert Categories.move_category_group(other, c.wohnen.id, nil) == {:error, :not_found}
      assert budget_order() == before
    end
  end

  defp assigned(category, month),
    do: Map.get(Categories.budget(budget_scope()).assigned, {category.id, month}, 0)

  defp german(changeset, field) do
    for {^field, error} <- changeset.errors, do: AbakusWeb.CoreComponents.translate_error(error)
  end
end
