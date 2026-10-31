defmodule AbakusWeb.BudgetCategoriesTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger, Repo}
  alias Abakus.Categories.Category
  alias Setzkasten.Test.Confirm

  @october ~D[2026-10-01]

  setup :register_and_log_in_user
  setup do: fix_today(~D[2026-10-10])

  setup do
    leisure = category_group_fixture(name: "🎉 Freizeit")
    movies = category_fixture(name: "🎬 Kino", category_group_id: leisure.id)
    games = category_fixture(name: "🎳 Bowling", category_group_id: leisure.id)
    %{leisure: leisure, movies: movies, games: games, checking: account_fixture()}
  end

  defp open(conn) do
    {:ok, view, _html} = live(conn, ~p"/budget")
    view
  end

  defp edit_category(view, category),
    do: view |> element("#edit-category-#{category.id}") |> render_click()

  defp submit_name(view, name),
    do: view |> form("#edit-form", %{"name" => name}) |> render_submit()

  defp rename(view, name),
    do: view |> form("#category-name-form", %{"name" => name}) |> render_submit()

  defp names(group_id) do
    Enum.find(Categories.list_category_groups(budget_scope()), &(&1.id == group_id)).categories
    |> Enum.map(& &1.name)
  end

  test "\"+ Gruppe\" adds a group at the end", c do
    view = open(c.conn)

    view |> element("#add-group") |> render_click()
    assert has_element?(view, "#edit-pop", "Neue Kategoriegruppe")
    submit_name(view, "🏠 Wohnen")

    assert List.last(Categories.list_category_groups(budget_scope())).name == "🏠 Wohnen"
    refute has_element?(view, ~s|#edit-pop[data-show="true"]|)
    assert has_element?(view, "tbody tr.app-grp", "Wohnen")
  end

  test "the group's \"+\" adds a category at its end", c do
    view = open(c.conn)

    view |> element("#add-category-#{c.leisure.id}") |> render_click()
    assert has_element?(view, "#edit-pop", "Neue Kategorie in 🎉 Freizeit")
    submit_name(view, "🎢 Freizeitpark")

    assert names(c.leisure.id) == ["🎬 Kino", "🎳 Bowling", "🎢 Freizeitpark"]
    [_movies, _games, park] = hd(Categories.list_category_groups(budget_scope())).categories
    assert has_element?(view, "#category-#{park.id}", "Freizeitpark")
  end

  test "the group's popover also adds a category, for screens without hover", c do
    view = open(c.conn)

    view |> element("#edit-group-#{c.leisure.id}") |> render_click()
    view |> element("#edit-add-category") |> render_click()

    assert has_element?(
             view,
             ~s|#edit-pop[data-anchor="edit-group-#{c.leisure.id}"]|,
             "Neue Kategorie in 🎉 Freizeit"
           )

    submit_name(view, "🎢 Freizeitpark")
    assert names(c.leisure.id) == ["🎬 Kino", "🎳 Bowling", "🎢 Freizeitpark"]
  end

  test "a name is needed; the popover stays with the error", c do
    view = open(c.conn)

    view |> element("#add-category-#{c.leisure.id}") |> render_click()
    submit_name(view, " ")

    assert has_element?(view, "#edit-pop #edit-name-error-0", "Name muss ausgefüllt werden")
    assert names(c.leisure.id) == ["🎬 Kino", "🎳 Bowling"]
  end

  test "the pencil on a category's row opens its dialog, which renames it, emoji and all", c do
    view = open(c.conn)

    assert has_element?(
             view,
             ~s|#category-#{c.movies.id} button#edit-category-#{c.movies.id}[aria-label="🎬 Kino bearbeiten"][aria-haspopup=dialog]|
           )

    edit_category(view, c.movies)

    assert has_element?(view, ~s|dialog#category-dialog[data-show="true"]|)
    assert has_element?(view, "#category-dialog-title", "🎬 Kino")
    assert has_element?(view, ~s|#category-name-input[value="🎬 Kino"][autofocus]|)
    assert has_element?(view, "#category-dialog #inspector-target")
    assert has_element?(view, "#category-dialog #category-delete #edit-delete")
    refute has_element?(view, "#edit-pop")

    rename(view, "🍿 Kino & Streaming")

    assert Repo.reload!(c.movies).name == "🍿 Kino & Streaming"
    assert has_element?(view, "#category-#{c.movies.id}", "Kino & Streaming")
    assert has_element?(view, "#category-dialog-title", "🍿 Kino & Streaming")
    assert has_element?(view, ~s|#category-name-input[value="🍿 Kino & Streaming"]|)
    assert has_element?(view, "#flash-info", "Name gespeichert.")

    rename(view, " ")

    assert has_element?(view, "#category-name-input-error-0", "Name muss ausgefüllt werden")
    assert Repo.reload!(c.movies).name == "🍿 Kino & Streaming"
  end

  test "the name is renamed in place: leaving the field saves, the same name saves nothing", c do
    view = open(c.conn)
    edit_category(view, c.movies)

    refute has_element?(view, "#category-name-form button")

    assert has_element?(
             view,
             ~s|#category-name-input[phx-hook=RenameField][data-saved="🎬 Kino"]|
           )

    view |> element("#category-name-input") |> render_blur(%{"value" => "🍿 Filme"})

    assert Repo.reload!(c.movies).name == "🍿 Filme"
    assert has_element?(view, ~s|#category-name-input[data-saved="🍿 Filme"]|)
    assert has_element?(view, "#flash-info", "Name gespeichert.")

    view |> element("#category-name-input") |> render_blur(%{"value" => ""})

    assert has_element?(view, "#category-name-input-error-0", "Name muss ausgefüllt werden")

    saved = Repo.reload!(c.movies).updated_at
    render_click(view, "lv:clear-flash", %{"key" => "info"})
    view |> element("#category-name-input") |> render_blur(%{"value" => " 🍿 Filme "})

    refute has_element?(view, "#category-name-input-error-0")
    refute has_element?(view, "#flash-info")
    assert Repo.reload!(c.movies).updated_at == saved
  end

  test "a name is saved trimmed, so leaving the field again saves nothing", c do
    view = open(c.conn)
    edit_category(view, c.movies)

    rename(view, "Miete ")

    assert Repo.reload!(c.movies).name == "Miete"
    assert has_element?(view, ~s|#category-name-input[data-saved="Miete"]|)

    saved = Repo.reload!(c.movies).updated_at
    render_click(view, "lv:clear-flash", %{"key" => "info"})
    view |> element("#category-name-input") |> render_blur(%{"value" => "Miete "})

    refute has_element?(view, "#flash-info")
    assert Repo.reload!(c.movies).updated_at == saved
  end

  test "on phones the sheet renames and deletes, with the same parts", c do
    {:ok, view, _html} =
      c.conn
      |> put_connect_params(%{
        "fit" => %{"months" => 1, "span" => 7, "compact" => true}
      })
      |> live(~p"/budget")

    refute has_element?(view, "#edit-category-#{c.movies.id}")

    view |> element("#select-#{c.movies.id}") |> render_click()

    assert has_element?(view, "#panel #category-delete #edit-delete")
    refute has_element?(view, "#category-name-input[autofocus]")
    rename(view, "🍿 Kino")

    assert Repo.reload!(c.movies).name == "🍿 Kino"
  end

  test "clicking a group's name renames it", c do
    view = open(c.conn)

    view |> element("#edit-group-#{c.leisure.id}") |> render_click()
    submit_name(view, "🎈 Spaß")

    assert Repo.reload!(c.leisure).name == "🎈 Spaß"
  end

  test "\"Abbrechen\" and Escape close the popover and change nothing", c do
    view = open(c.conn)

    view |> element("#edit-group-#{c.leisure.id}") |> render_click()
    view |> element("#edit-pop button", "Abbrechen") |> render_click()
    refute has_element?(view, ~s|#edit-pop[data-show="true"]|)

    view |> element("#edit-group-#{c.leisure.id}") |> render_click()
    assert has_element?(view, ~s|#edit-pop[data-cancel*="edit_close"]|)
    render_click(view, "edit_close", %{})
    refute has_element?(view, ~s|#edit-pop[data-show="true"]|)
  end

  describe "deleting a category" do
    test "moves everything into the chosen category", c do
      Categories.assign(budget_scope(), c.movies, @october, 2_000)
      Categories.assign(budget_scope(), c.games, @october, 500)
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()

      assert has_element?(view, "#category-dialog #category-delete #delete-form")
      refute has_element?(view, "#category-delete #edit-delete")
      refute has_element?(view, ~s|#delete-form [role=option][data-value="#{c.movies.id}"]|)
      refute has_element?(view, "#delete-into-help")

      Confirm.confirm_click(view, "#delete-submit", "Kategorie „🎬 Kino“ löschen?",
        with: %{"into" => "#{c.games.id}"}
      )

      assert Repo.reload(c.movies).deleted_at
      assert has_element?(view, ~s|dialog#category-dialog[data-show="false"]|)
      assert Categories.budget(budget_scope()).assigned == %{{c.games.id, @october} => 2_500}
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
      assert has_element?(view, "#delete-into-help", "abgeglichene Buchungen")

      Confirm.confirm_click(view, "#delete-submit", nil, with: %{"into" => "#{c.games.id}"})

      assert Repo.reload!(transaction).category_id == c.games.id
    end

    test "asks again when a transaction got reconciled meanwhile", c do
      transaction = transaction_fixture(account_id: c.checking.id, category_id: c.movies.id)
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()
      Ledger.update_transaction(budget_scope(), transaction, %{cleared: :reconciled})
      view |> form("#delete-form") |> render_submit(%{"into" => "#{c.games.id}"})

      assert %Category{} = Repo.reload(c.movies)
      assert has_element?(view, "#delete-into-help")
    end

    test "keeps the chosen category across a re-render, and Abbrechen goes back", c do
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()
      view |> form("#delete-form") |> render_change(%{"into" => "#{c.games.id}"})
      render_click(view, "edit_close", %{})

      assert has_element?(view, ~s|#delete-into-combobox input[name=into][value="#{c.games.id}"]|)

      view |> element("#delete-form button", "Abbrechen") |> render_click()

      refute has_element?(view, "#delete-form")
      assert has_element?(view, "#category-delete #edit-delete")
      assert Repo.reload(c.movies)
    end

    test "renaming while it asks for the target saves the name and leaves the deleting", c do
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()
      rename(view, "🍿 Kino")

      assert Repo.reload!(c.movies).name == "🍿 Kino"
      refute has_element?(view, "#delete-form")
      assert has_element?(view, "#category-delete #edit-delete")
    end

    test "leaves a name's error behind", c do
      view = open(c.conn)

      edit_category(view, c.movies)
      rename(view, " ")
      view |> element("#edit-delete") |> render_click()

      refute has_element?(view, "#delete-form", "Name muss ausgefüllt werden")
    end

    test "offers no internal category as the target", c do
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()

      rta = Categories.ready_to_assign!(budget_scope())
      refute has_element?(view, ~s|#delete-form [role=option][data-value="#{rta.id}"]|)

      assert has_element?(
               view,
               ~s|#delete-form [role=option][data-value="#{c.games.id}"]|,
               "🎳 Bowling"
             )
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
      Confirm.confirm_click(view, "#edit-delete", "Gruppe „🗑️ Leer“ löschen?")

      assert Repo.reload(empty).deleted_at
      refute has_element?(view, "#group-#{empty.id}")
    end
  end

  describe "changed meanwhile" do
    test "renaming a category deleted in another tab shows a note", c do
      view = open(c.conn)

      edit_category(view, c.movies)
      {:ok, _deleted} = Categories.delete_category(budget_scope(), c.movies, c.games)
      rename(view, "Kino neu")

      assert render(view) =~ "inzwischen geändert oder gelöscht"
      refute has_element?(view, "#category-#{c.movies.id}")
    end

    test "deleting a group deleted in another tab shows a note", c do
      empty = category_group_fixture(name: "🗑️ Leer")
      view = open(c.conn)

      view |> element("#edit-group-#{empty.id}") |> render_click()
      {:ok, _deleted} = Categories.delete_category_group(budget_scope(), empty)
      Confirm.confirm_click(view, "#edit-delete")

      assert render(view) =~ "inzwischen geändert oder gelöscht"
      refute has_element?(view, ~s|#edit-pop[data-show="true"]|)
    end

    test "assigning after a category was deleted in another tab", c do
      view = open(c.conn)
      {:ok, _deleted} = Categories.delete_category(budget_scope(), c.movies, c.games)

      view |> element("#assign-#{c.games.id}-2026-10") |> render_blur(%{"value" => "5"})

      refute has_element?(view, "#category-#{c.movies.id}")
      assert has_element?(view, "#available-#{c.games.id}-2026-10", "5,00")
    end

    test "asking again about reconciled transactions keeps the chosen category", c do
      transaction = transaction_fixture(account_id: c.checking.id, category_id: c.movies.id)
      view = open(c.conn)

      edit_category(view, c.movies)
      view |> element("#edit-delete") |> render_click()
      Ledger.update_transaction(budget_scope(), transaction, %{cleared: :reconciled})
      view |> form("#delete-form") |> render_submit(%{"into" => "#{c.games.id}"})

      assert has_element?(view, ~s|#delete-into-combobox input[name=into][value="#{c.games.id}"]|)
    end
  end

  test "\"Löschen\" sent while adding changes nothing", c do
    view = open(c.conn)

    view |> element("#add-category-#{c.leisure.id}") |> render_click()
    render_click(view, "edit_delete", %{})

    assert has_element?(view, "#edit-pop", "Neue Kategorie")
  end
end
