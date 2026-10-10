defmodule AbakusWeb.BudgetCategoriesTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger, Repo}
  alias Abakus.Categories.Category

  @october ~D[2026-10-01]

  setup :register_and_log_in_user

  setup do
    leisure = category_group_fixture(name: "🎉 Freizeit")
    movies = category_fixture(name: "🎬 Kino", category_group_id: leisure.id)
    games = category_fixture(name: "🎳 Bowling", category_group_id: leisure.id)
    %{leisure: leisure, movies: movies, games: games, checking: account_fixture()}
  end

  defp open(conn) do
    conn
    |> put_connect_params(%{"today" => "2026-10-10"})
    |> live(~p"/")
    |> then(fn {:ok, view, _html} -> view end)
  end

  # A category's name selects it; the inspector's pencil opens its popover.
  defp edit_category(view, category) do
    view |> element("#select-#{category.id}") |> render_click()
    view |> element("#edit-category") |> render_click()
  end

  defp submit_name(view, name),
    do: view |> form("#edit-form", %{"name" => name}) |> render_submit()

  defp names(group_id) do
    Enum.find(Categories.list_category_groups(), &(&1.id == group_id)).categories
    |> Enum.map(& &1.name)
  end

  test "\"+ Gruppe\" adds a group at the end", c do
    view = open(c.conn)

    view |> element("#add-group") |> render_click()
    assert has_element?(view, "#edit-pop", "Neue Kategoriegruppe")
    submit_name(view, "🏠 Wohnen")

    assert List.last(Categories.list_category_groups()).name == "🏠 Wohnen"
    refute has_element?(view, "#edit-pop")
    assert has_element?(view, "tbody tr.app-grp", "Wohnen")
  end

  test "the group's \"+\" adds a category at its end", c do
    view = open(c.conn)

    view |> element("#add-category-#{c.leisure.id}") |> render_click()
    assert has_element?(view, "#edit-pop", "Neue Kategorie in 🎉 Freizeit")
    submit_name(view, "🎢 Freizeitpark")

    assert names(c.leisure.id) == ["🎬 Kino", "🎳 Bowling", "🎢 Freizeitpark"]
    [_movies, _games, park] = hd(Categories.list_category_groups()).categories
    assert has_element?(view, "#category-#{park.id}", "Freizeitpark")
  end

  test "a name is needed; the popover stays with the error", c do
    view = open(c.conn)

    view |> element("#add-category-#{c.leisure.id}") |> render_click()
    submit_name(view, " ")

    assert has_element?(view, "#edit-pop .invalid-feedback", "muss ausgefüllt werden")
    assert names(c.leisure.id) == ["🎬 Kino", "🎳 Bowling"]
  end

  test "the inspector's pencil renames a category, emoji and all", c do
    view = open(c.conn)

    edit_category(view, c.movies)
    assert has_element?(view, ~s|#edit-pop input[name=name][value="🎬 Kino"]|)
    submit_name(view, "🍿 Kino & Streaming")

    assert Repo.reload!(c.movies).name == "🍿 Kino & Streaming"
    assert has_element?(view, "#category-#{c.movies.id}", "Kino & Streaming")
  end

  test "clicking a group's name renames it", c do
    view = open(c.conn)

    view |> element("#edit-group-#{c.leisure.id}") |> render_click()
    submit_name(view, "🎈 Spaß")

    assert Repo.reload!(c.leisure).name == "🎈 Spaß"
  end

  test "\"Abbrechen\" and Escape close the popover and change nothing", c do
    view = open(c.conn)

    edit_category(view, c.movies)
    view |> element("#edit-pop button", "Abbrechen") |> render_click()
    refute has_element?(view, "#edit-pop")

    view |> element("#edit-group-#{c.leisure.id}") |> render_click()
    view |> element("#edit-pop") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#edit-pop")
  end

  describe "deleting a category" do
    test "moves everything into the chosen category", c do
      Categories.assign(c.movies, @october, 2_000)
      Categories.assign(c.games, @october, 500)
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()

      assert has_element?(view, "#edit-pop", "„🎬 Kino“ löschen")
      refute has_element?(view, ~s|#delete-form option[value="#{c.movies.id}"]|)
      refute has_element?(view, "#delete-reconciled")

      view
      |> form("#delete-form", %{"into" => "#{c.games.id}"})
      |> render_submit()

      refute Repo.reload(c.movies)
      assert Categories.budget().assigned == %{{c.games.id, @october} => 2_500}
      refute has_element?(view, "#category-#{c.movies.id}")
      assert has_element?(view, "#assign-#{c.games.id}-2026-10[value='25,00']")
    end

    test "says reconciled transactions change too, and confirming covers them", c do
      transaction =
        transaction_fixture(
          account_id: c.checking.id,
          category_id: c.movies.id,
          cleared: :reconciled
        )

      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()
      assert has_element?(view, "#delete-reconciled", "abgeglichene Buchungen")

      view |> form("#delete-form", %{"into" => "#{c.games.id}"}) |> render_submit()

      assert Repo.reload!(transaction).category_id == c.games.id
    end

    test "asks again when a transaction got reconciled meanwhile", c do
      transaction = transaction_fixture(account_id: c.checking.id, category_id: c.movies.id)
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()
      Ledger.update_transaction(transaction, %{cleared: :reconciled})
      view |> form("#delete-form", %{"into" => "#{c.games.id}"}) |> render_submit()

      assert %Category{} = Repo.reload(c.movies)
      assert has_element?(view, "#delete-reconciled")
    end

    test "offers no internal category as the target", c do
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()

      rta = Categories.ready_to_assign!()
      refute has_element?(view, ~s|#delete-form option[value="#{rta.id}"]|)
      assert has_element?(view, ~s|#delete-form option[value="#{c.games.id}"]|, "🎳 Bowling")
    end
  end

  describe "deleting a group" do
    test "a group with categories offers no deleting", c do
      view = open(c.conn)

      view |> element("#edit-group-#{c.leisure.id}") |> render_click()

      refute has_element?(view, "#edit-delete")
      assert has_element?(view, "#edit-pop", "Nur leere Gruppen")
    end

    test "an empty group is deleted", c do
      empty = category_group_fixture(name: "🗑️ Leer")
      view = open(c.conn)

      view |> element("#edit-group-#{empty.id}") |> render_click()
      view |> element("#edit-delete") |> render_click()

      refute Repo.reload(empty)
      refute has_element?(view, "#group-#{empty.id}")
    end
  end

  describe "changed meanwhile" do
    test "renaming a category deleted in another tab shows a note", c do
      view = open(c.conn)

      edit_category(view, c.movies)
      {:ok, _deleted} = Categories.delete_category(c.movies, c.games)
      submit_name(view, "Kino neu")

      assert render(view) =~ "inzwischen geändert oder gelöscht"
      refute has_element?(view, "#category-#{c.movies.id}")
    end

    test "deleting a group deleted in another tab shows a note", c do
      empty = category_group_fixture(name: "🗑️ Leer")
      view = open(c.conn)

      view |> element("#edit-group-#{empty.id}") |> render_click()
      {:ok, _deleted} = Categories.delete_category_group(empty)
      view |> element("#edit-delete") |> render_click()

      assert render(view) =~ "inzwischen geändert oder gelöscht"
      refute has_element?(view, "#edit-pop")
    end

    test "assigning after a category was deleted in another tab", c do
      view = open(c.conn)
      {:ok, _deleted} = Categories.delete_category(c.movies, c.games)

      view |> element("#assign-#{c.games.id}-2026-10") |> render_blur(%{"value" => "5"})

      refute has_element?(view, "#category-#{c.movies.id}")
      assert has_element?(view, "#available-#{c.games.id}-2026-10", "5,00 €")
    end

    test "asking again about reconciled transactions keeps the chosen category", c do
      transaction = transaction_fixture(account_id: c.checking.id, category_id: c.movies.id)
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()
      Ledger.update_transaction(transaction, %{cleared: :reconciled})
      view |> form("#delete-form", %{"into" => "#{c.games.id}"}) |> render_submit()

      assert has_element?(view, ~s|#delete-form option[value="#{c.games.id}"][selected]|)
    end
  end

  test "a sum of assignments out of range is refused with a note", c do
    Categories.assign(c.movies, @october, 10_000_000_000_000)
    Categories.assign(c.games, @october, 1)
    view = open(c.conn)

    edit_category(view, c.movies)
    view |> element("#edit-delete") |> render_click()
    view |> form("#delete-form", %{"into" => "#{c.games.id}"}) |> render_submit()

    assert has_element?(view, "#edit-pop", "zu groß")
    assert Repo.reload(c.movies)
  end

  test "\"Löschen\" sent while adding changes nothing", c do
    view = open(c.conn)

    view |> element("#add-category-#{c.leisure.id}") |> render_click()
    render_click(view, "edit_delete", %{})

    assert has_element?(view, "#edit-pop", "Neue Kategorie")
  end

  test "adding with a filter on shows everything again, the new group too", c do
    {:ok, view, _html} =
      c.conn
      |> put_connect_params(%{"today" => "2026-10-10"})
      |> live(~p"/?filter=overspent")

    view |> element("#add-group") |> render_click()
    submit_name(view, "🏠 Wohnen")

    assert_patch(view, ~p"/?month=2026-10")
    assert has_element?(view, "tbody tr.app-grp", "Wohnen")
  end
end
