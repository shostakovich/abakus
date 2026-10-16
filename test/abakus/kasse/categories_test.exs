defmodule Abakus.Kasse.CategoriesTest do
  use Abakus.DataCase

  import Abakus.Kasse.ActivityTexts
  import Abakus.KasseFixtures, only: [person!: 1, scope_of: 1]
  import Abakus.UsersFixtures

  alias Abakus.Kasse.{AccessError, Activities, Categories}
  alias Abakus.Users.Scope

  defp names, do: Enum.map(Categories.list_categories(Scope.system()), & &1.name)

  defp create!(name) do
    {:ok, category} = Categories.create_category(Scope.system(), %{name: name})
    category
  end

  test "lists the seeded categories in their order" do
    assert names() == [
             "Lebensmittel",
             "Restaurant",
             "Haushalt",
             "Miete & Nebenkosten",
             "Transport",
             "Reisen",
             "Freizeit",
             "Gesundheit",
             "Geschenke",
             "Sonstiges"
           ]
  end

  test "puts a new category before Sonstiges and renumbers the positions" do
    category = create!(" Haus  tiere ")

    assert Enum.take(names(), -2) == ["Haus tiere", "Sonstiges"]
    assert category.position == 100

    assert Enum.map(Categories.list_categories(Scope.system()), & &1.position) ==
             Enum.map(1..11, &(&1 * 10))

    assert activity_texts(:oldest_first) == ["Kategorie „Haus tiere“ hinzugefügt"]
  end

  test "logs the scope's person as the actor" do
    anna = person!("Anna")

    {:ok, _category} = Categories.create_category(scope_of(anna.id), %{name: "Kino"})

    assert [%{actor_id: actor_id} | _] = Activities.list_activities(Scope.system())
    assert actor_id == anna.id
  end

  test "refuses a signed-in user who is not a person" do
    outsider = Scope.for_user(user_fixture())
    [food | _] = Categories.list_categories(Scope.system())

    assert_raise AccessError, fn -> Categories.list_categories(outsider) end
    assert_raise AccessError, fn -> Categories.get_category(outsider, food.id) end
    assert_raise AccessError, fn -> Categories.create_category(outsider, %{name: "Kino"}) end
    assert_raise AccessError, fn -> Categories.archive_category(outsider, food) end
    assert activity_texts(:oldest_first) == []
  end

  test "refuses the name of an existing category, regardless of its case" do
    assert {:error, changeset} =
             Categories.create_category(Scope.system(), %{name: "lebensmittel"})

    assert errors_on(changeset) == %{name: ["Die Kategorie „lebensmittel“ gibt es schon."]}
    assert {:error, changeset} = Categories.create_category(Scope.system(), %{name: ""})
    assert errors_on(changeset) == %{name: ["Bitte einen Namen für die Kategorie angeben."]}
    assert activity_texts(:oldest_first) == []
  end

  test "renames a category, logging only a real change" do
    kino = create!("Kino")

    {:ok, theater} = Categories.rename_category(Scope.system(), kino, %{name: "Theater"})
    {:ok, _same} = Categories.rename_category(Scope.system(), theater, %{name: "Theater "})

    assert Categories.get_category!(Scope.system(), kino.id).name == "Theater"
    assert List.last(activity_texts(:oldest_first)) == "Kategorie „Kino“ umbenannt in „Theater“"
    assert length(activity_texts(:oldest_first)) == 2
  end

  describe "moving a category" do
    test "swaps it with its neighbour and logs it" do
      [first, second | _] = Categories.list_categories(Scope.system())

      {:ok, _moved} = Categories.move_category(Scope.system(), second, :up)
      assert Enum.take(names(), 2) == [second.name, first.name]
      {:ok, _moved} = Categories.move_category(Scope.system(), second, :down)
      assert Enum.take(names(), 2) == [first.name, second.name]

      assert activity_texts(:oldest_first) == [
               "Kategorie „Restaurant“ nach oben verschoben",
               "Kategorie „Restaurant“ nach unten verschoben"
             ]
    end

    test "does nothing at the edge" do
      first = hd(Categories.list_categories(Scope.system()))

      assert {:ok, _same} = Categories.move_category(Scope.system(), first, :up)
      assert hd(names()) == first.name
      assert activity_texts(:oldest_first) == []
    end

    test "does not know an archived category" do
      second = Enum.at(Categories.list_categories(Scope.system()), 1)
      {:ok, archived} = Categories.archive_category(Scope.system(), second)

      assert Categories.move_category(Scope.system(), archived, :up) == {:error, :not_found}
    end
  end

  describe "creating a category after moves renumbered the positions" do
    test "puts it directly before Sonstiges" do
      {:ok, _moved} =
        Categories.move_category(
          Scope.system(),
          hd(Categories.list_categories(Scope.system())),
          :down
        )

      create!("Neu")

      assert Enum.take(names(), -3) == ["Geschenke", "Neu", "Sonstiges"]
    end

    test "still puts it directly before Sonstiges when that moved up by one" do
      create!("Neu")

      {:ok, _moved} =
        Categories.move_category(
          Scope.system(),
          List.last(Categories.list_categories(Scope.system())),
          :up
        )

      create!("Noch neuer")

      assert Enum.take(names(), -4) == ["Geschenke", "Noch neuer", "Sonstiges", "Neu"]
    end

    test "puts it at the end without an active Sonstiges" do
      {:ok, _archived} =
        Categories.archive_category(
          Scope.system(),
          List.last(Categories.list_categories(Scope.system()))
        )

      create!("Zuletzt")

      assert List.last(names()) == "Zuletzt"
    end
  end

  test "archives and reactivates a category, logging both" do
    food = hd(Categories.list_categories(Scope.system()))

    {:ok, archived} = Categories.archive_category(Scope.system(), food)
    assert Enum.map(Categories.list_categories(Scope.system(), :archived), & &1.id) == [food.id]
    {:ok, _back} = Categories.reactivate_category(Scope.system(), archived)

    assert hd(names()) == "Lebensmittel"

    assert activity_texts(:oldest_first) == [
             "Kategorie „Lebensmittel“ archiviert",
             "Kategorie „Lebensmittel“ reaktiviert"
           ]
  end
end
