defmodule AbakusWeb.AreasTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.PortfoliosFixtures, only: [portfolio_fixture: 2]
  import Abakus.DomainFixtures
  import Abakus.KasseFixtures
  import Abakus.UsersFixtures

  alias Abakus.Depot.Portfolios
  alias Abakus.Kasse.Participants
  alias Abakus.Users.Scope

  @pages ["Budget", "Vermögen", "Alle Konten", "Alle Depots", "Import & Sync"] ++
           ["Ausgaben", "Salden", "Aktivität"]

  defp sidebar_labels(view) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(~s|#app-shell-sidebar-full nav[aria-label="Hauptnavigation"] a|)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
    |> Enum.filter(&(&1 in @pages))
  end

  defp dock_paths(view) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(".dock a")
    |> Enum.flat_map(&LazyHTML.attribute(&1, "href"))
  end

  # With a real id in every route param, so the area alone answers 404.
  defp get_paths(prefix, id) do
    paths =
      for %{verb: :get, path: path} <- AbakusWeb.Router.__routes__(),
          String.starts_with?(path, prefix),
          do: String.replace(path, ~r"[:*]\w+", Integer.to_string(id))

    assert prefix in paths
    paths
  end

  describe "the budget owner" do
    setup :register_and_log_in_user

    test "opens Finanzen at the Budget from /", %{conn: conn} do
      assert conn |> get(~p"/") |> redirected_to() == ~p"/budget"
    end

    test "opens the area used last, kept in the session", %{conn: conn} do
      conn = get(conn, ~p"/budget/accounts")
      assert get_session(conn, :area) == "finanzen"

      assert conn |> recycle() |> get(~p"/") |> redirected_to() == ~p"/budget"
    end

    test "falls back to an area they may use when the one used last is gone", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, area: "kasse")

      assert conn |> get(~p"/") |> redirected_to() == ~p"/budget"
    end

    test "with Finanzen as their only area: the brand is its name and there is no switch", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/budget")

      assert has_element?(view, "header .navbar", "Finanzen")
      refute has_element?(view, "header .navbar", "Abakus")
      refute has_element?(view, "#area-switcher")
      refute has_element?(view, ~s|nav[aria-label="Bereich wechseln"]|)
    end

    test "without a portfolio sees Vermögen in Finanzen, but no Depots", %{conn: conn} do
      giro = account_fixture(name: "Girokonto")
      transaction_fixture(account_id: giro.id, date: Abakus.LocalTime.today(), amount: 120_000)

      {:ok, view, _html} = live(conn, ~p"/budget")

      assert sidebar_labels(view) == ["Budget", "Vermögen", "Alle Konten", "Import & Sync"]
      refute has_element?(view, sidebar_link("/depot/holdings"))

      {:ok, view, _html} = live(conn, ~p"/depot")

      assert has_element?(view, sidebar_link("/depot") <> "[aria-current=page]", "Vermögen")
      assert view |> element("#net-worth") |> render() =~ "1.200"
    end
  end

  describe "a user who does not own the budget" do
    setup %{conn: conn} do
      _owner = user_fixture()
      account = account_fixture(name: "Girokonto")
      user = user_fixture()

      %{conn: log_in_user(conn, user), user: user, account: account}
    end

    test "gets 404 on every Budget page", %{conn: conn, account: account} do
      for path <- get_paths("/budget", account.id) do
        assert_error_sent 404, fn -> get(conn, path) end
      end

      assert_error_sent 404, fn -> get(conn, ~p"/settings/budget/ynab") end
    end

    test "sees no Budget in the sidebar or the settings", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings/appearance")

      refute has_element?(view, ~s|a[href^="/budget"]|)
      refute html =~ "Girokonto"
      refute has_element?(view, "#settings-ynab-import-sidebar")
      assert has_element?(view, ~s|#settings-access-sidebar[href="/settings/access"]|)
    end

    test "is sent to the settings by /, never to the Budget used before", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, area: "budget")

      assert conn |> get(~p"/") |> redirected_to() == ~p"/settings"
    end
  end

  describe "a person of the Kasse who does not own the budget" do
    setup %{conn: conn} do
      _owner = user_fixture()
      account = account_fixture(name: "Girokonto")
      dora = person!("Dora")

      %{conn: log_in_participant(conn, dora.id), account: account}
    end

    test "sees only the Kasse, under its name and without a switch", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/kasse")

      assert has_element?(view, "header .navbar", "Kasse")
      refute has_element?(view, "#area-switcher")
      refute has_element?(view, ~s|nav[aria-label="Bereich wechseln"]|)
      refute has_element?(view, "aside nav .menu-title")
      refute has_element?(view, ~s|a[href^="/budget"]|)
      refute html =~ "Girokonto"
      assert has_element?(view, sidebar_link("/kasse") <> "[aria-current=page]", "Ausgaben")
      assert has_element?(view, ".dock a[href='/kasse/balances']", "Salden")
    end

    test "opens the Kasse from / and gets 404 on every Budget page", %{
      conn: conn,
      account: account
    } do
      assert conn |> get(~p"/") |> redirected_to() == ~p"/kasse"

      for path <- get_paths("/budget", account.id) do
        assert_error_sent 404, fn -> get(conn, path) end
      end
    end
  end

  describe "a user who is no person of the Kasse" do
    setup :register_and_log_in_user

    setup do
      %{h: household()}
    end

    test "gets 404 on every Kasse page and sees no Kasse in the sidebar", %{conn: conn, h: h} do
      expense = create!(equal(h, "Essen", 3000, "2026-10-01", h.anna, [h.anna, h.ben]))

      for path <- get_paths("/kasse", expense.id) do
        assert_error_sent 404, fn -> get(conn, path) end
      end

      {:ok, view, _html} = live(conn, ~p"/budget")
      refute has_element?(view, ~s|a[href^="/kasse"]|)
      refute has_element?(view, "#area-switcher")
    end

    test "an archived person among them", %{h: h} do
      anna = Participants.get_participant!(h.anna)
      {:ok, _anna} = Participants.archive_participant(nil, anna)
      conn = log_in_participant(build_conn(), anna.id)

      assert_error_sent 404, fn -> get(conn, ~p"/kasse") end
    end
  end

  describe "the budget owner who is a person of the Kasse" do
    setup :register_and_log_in_user

    setup %{user: user} do
      {:ok, olga} =
        Participants.create_participant(nil, %{name: "Olga", email: user.email})

      %{olga: olga}
    end

    test "switches between Finanzen and Kasse from the sidebar and the title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/kasse")

      assert has_element?(view, ~s|#area-finanzen-sidebar[href="/budget"]|, "Finanzen")
      assert has_element?(view, ~s|#area-kasse-sidebar[href="/kasse"][aria-current=page]|)
      assert has_element?(view, ~s|#area-switcher a[href="/budget"]|)
      assert has_element?(view, ~s|#area-switcher a[href="/kasse"][aria-current=page]|)

      assert get_session(get(conn, ~p"/kasse/balances"), :area) == "kasse"
      assert get_session(get(conn, ~p"/depot"), :area) == "finanzen"

      in_finanzen = Plug.Test.init_test_session(conn, area: "finanzen")
      assert get_session(get(in_finanzen, ~p"/settings/kasse"), :area) == "finanzen"
    end

    test "opens the PP import in Finanzen, coming from the Kasse", %{conn: conn} do
      in_kasse = Plug.Test.init_test_session(conn, area: "kasse")
      assert get_session(get(in_kasse, ~p"/depot/import"), :area) == "finanzen"

      {:ok, view, _html} = live(in_kasse, ~p"/depot/import")
      assert has_element?(view, ~s|#area-finanzen-sidebar[aria-current=page]|)
    end

    test "sees only the current area's entries", %{conn: conn} do
      account_fixture(name: "Girokonto")
      account_fixture(name: "Depot", kind: :tracking)

      {:ok, view, _html} = live(conn, ~p"/kasse")

      assert sidebar_labels(view) == ["Ausgaben", "Salden", "Aktivität"]
      refute has_element?(view, "aside nav .menu-title")
      refute has_element?(view, sidebar_link("/budget"))

      assert dock_paths(view) == ["/kasse", "/kasse/balances", "/kasse/activity"]

      {:ok, view, _html} = live(conn, ~p"/budget")

      assert sidebar_labels(view) == ["Budget", "Vermögen", "Alle Konten", "Import & Sync"]
      assert has_element?(view, "aside nav .menu-title", "Budgetkonten")
      assert has_element?(view, "aside nav .menu-title", "Trackingkonten")
      refute has_element?(view, sidebar_link("/kasse"))
      assert dock_paths(view) == ["/budget", "/depot", "/budget/accounts/all"]
    end
  end

  describe "a person of the Kasse who has no portfolio" do
    setup %{conn: conn} do
      owner = user_fixture()

      owner_portfolio =
        portfolio_fixture(Scope.for_user(owner), %{name: "Ottos Altersvorsorge"})

      dora = person!("Dora")

      %{conn: log_in_participant(conn, dora.id), dora: dora, owner_portfolio: owner_portfolio}
    end

    test "gets 404 on every Depot page and sees no Finanzen", %{conn: conn} do
      for path <- get_paths("/depot", 1), path != "/depot/import" do
        assert_error_sent 404, fn -> get(conn, path) end
      end

      {:ok, view, _html} = live(conn, ~p"/kasse")
      refute has_element?(view, ~s|a[href^="/depot"]|)
      refute has_element?(view, "#area-switcher")
    end

    test "creates a portfolio of their own under Einstellungen, which opens the Depot", %{
      conn: conn,
      dora: dora
    } do
      {:ok, view, _html} = live(conn, ~p"/settings/appearance")

      assert has_element?(
               view,
               ~s|#settings-depots-sidebar[href="/settings/depot/portfolios"]|,
               "Depots"
             )

      {:ok, view, _html} = live(conn, ~p"/settings/depot/portfolios")
      refute render(view) =~ "Ottos Altersvorsorge"
      refute has_element?(view, "#settings-receipt-intake-sidebar")

      view
      |> form("#new-portfolio-form", portfolio: %{name: "Doras Depot"})
      |> render_submit()

      assert has_element?(view, "#settings-receipt-intake-sidebar", "Belegeingang")

      {:ok, view, _html} = live(conn, ~p"/depot")
      assert has_element?(view, "aside nav", "Doras Depot")
      refute render(view) =~ "Ottos Altersvorsorge"

      dora = Abakus.Repo.preload(dora, :user)

      assert [%{name: "Doras Depot"}] =
               Portfolios.list_portfolios(Scope.for_user(dora.user))
    end

    test "is not seen by the budget owner, who has a Depot of their own", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/depot/portfolios")
      view |> form("#new-portfolio-form", portfolio: %{name: "Doras Depot"}) |> render_submit()

      owner = Abakus.Repo.get_by!(Abakus.Users.User, budget_owner: true)
      {:ok, view, html} = live(log_in_user(build_conn(), owner), ~p"/depot")

      assert has_element?(view, "aside nav", "Ottos Altersvorsorge")
      refute html =~ "Doras Depot"
    end
  end

  describe "a user with portfolios and no budget" do
    setup :register_and_log_in_user_without_budget

    setup %{scope: scope} do
      account_fixture(name: "Girokonto")
      %{portfolio: portfolio_fixture(scope, %{name: "Langfristig"})}
    end

    test "sees Finanzen without the budget's pages", %{conn: conn, portfolio: portfolio} do
      assert conn |> get(~p"/") |> redirected_to() == ~p"/depot"

      {:ok, view, html} = live(conn, ~p"/depot")

      assert has_element?(view, "header .navbar", "Finanzen")
      refute has_element?(view, ~s|nav[aria-label="Bereich wechseln"]|)
      assert sidebar_labels(view) == ["Vermögen", "Alle Depots", "Import & Sync"]
      assert has_element?(view, sidebar_link("/depot/receipts"), "Import & Sync")
      assert has_element?(view, sidebar_link(~p"/depot/holdings?#{[portfolio: portfolio.id]}"))
      refute has_element?(view, ~s|a[href^="/budget"]|)
      refute html =~ "Girokonto"
      assert dock_paths(view) == ["/depot", "/depot/holdings"]
    end
  end
end
