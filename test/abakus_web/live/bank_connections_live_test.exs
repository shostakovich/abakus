defmodule AbakusWeb.BankConnectionsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.BankSyncFixtures

  alias Abakus.{BankSync, Repo}
  alias Abakus.BankSync.FakeClient

  setup :register_and_log_in_user

  describe "without the configuration" do
    test "the tab says bank sync is not set up", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")

      assert has_element?(
               view,
               ~s|#import-tabs a[href="/budget/bank-connections"][aria-current=page]|,
               "Bankverbindungen"
             )

      assert has_element?(view, "#bank-sync-not-set-up", "Bank-Sync ist nicht eingerichtet")
      assert has_element?(view, ~s|#bank-sync-not-set-up img[src^="/images/plush/landmark"]|)
      assert has_element?(view, "#bank-sync-not-set-up", "ENABLE_BANKING_APP_ID")

      assert has_element?(
               view,
               "#bank-sync-not-set-up",
               "http://localhost:4002/budget/bank-connections/callback"
             )

      refute has_element?(view, "#bank-connect-form")
    end
  end

  describe "connecting a bank" do
    setup do
      FakeClient.serve()
      fix_now(~U[2026-10-20 10:00:00.000000Z])

      giro = account_fixture(name: "Girokonto")
      savings = account_fixture(name: "Tagesgeld")
      account_fixture(name: "Geteilt", fed_by: :shared_expenses)
      account_fixture(name: "Altes Konto", closed: true)

      transaction_fixture(account_id: giro.id, date: ~D[2026-10-01], cleared: :reconciled)

      %{giro: giro, savings: savings}
    end

    test "the import tabs lead to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/import")

      assert has_element?(view, ~s|#import-tabs a[href="/budget/bank-connections"]|)
    end

    test "picks a bank, consents and assigns its accounts with the date to fetch from",
         %{conn: conn, giro: giro, savings: savings} do
      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")
      render_async(view)

      assert has_element?(view, ~s|#bank-connections-empty img[src^="/images/plush/landmark"]|)
      assert has_element?(view, "#bank-connect-country option[selected]", "Deutschland")
      assert has_element?(view, "#bank-connect-bank option", "Musterbank")
      refute has_element?(view, "#bank-connect-bank option", "Banque Exemple")

      view |> form("#bank-connect-form", %{country: "FR"}) |> render_change()
      render_async(view)
      assert has_element?(view, "#bank-connect-bank option", "Banque Exemple")

      view |> form("#bank-connect-form", %{country: "DE"}) |> render_change()
      render_async(view)

      assert {:error, {:redirect, %{to: authorize_path}}} =
               view
               |> form("#bank-connect-form", %{country: "DE", bank: "Musterbank"})
               |> render_submit()

      conn = get(conn, authorize_path)
      assert redirected_to(conn) =~ "https://enablebanking.example/auth/"

      assert [request] = FakeClient.auth_requests()
      assert request.bank == %{name: "Musterbank", country: "DE"}
      assert request.redirect_url == "http://localhost:4002/budget/bank-connections/callback"
      # The bank's maximum consent validity, 180 days.
      assert request.valid_until == ~U[2027-04-18 10:00:00Z]

      conn =
        get(conn, ~p"/budget/bank-connections/callback?#{[code: "code-1", state: request.state]}")

      [connection] = BankSync.list_connections(budget_scope())
      assert redirected_to(conn) == ~p"/budget/bank-connections/#{connection}/accounts"
      assert connection.bank_name == "Musterbank"
      assert connection.bank_country == "DE"
      assert connection.session_id == "session-1"
      assert connection.valid_until == ~U[2027-04-18 10:00:00.000000Z]

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections/#{connection}/accounts")
      render_async(view)

      [current, other] = connection.linked_accounts
      assert has_element?(view, "#bank-accounts-form", "DE02 1002 0030 0000 0047 11")
      assert has_element?(view, "#link-#{current.id}-account option", "Girokonto")
      refute has_element?(view, "#link-#{current.id}-account option", "Geteilt")
      refute has_element?(view, "#link-#{current.id}-account option", "Altes Konto")

      view
      |> form("#bank-accounts-form", %{links: %{current.id => %{account_id: giro.id}}})
      |> render_change()

      assert has_element?(view, ~s|#link-#{current.id}-start-date[value="2026-10-02"]|)

      view
      |> form("#bank-accounts-form", %{links: %{other.id => %{account_id: savings.id}}})
      |> render_change()

      assert has_element?(view, ~s|#link-#{other.id}-start-date[value="2026-10-20"]|)
      assert has_element?(view, ~s|#link-#{current.id}-start-date[value="2026-10-02"]|)

      {:ok, view, _html} =
        view
        |> form("#bank-accounts-form", %{
          links: %{
            current.id => %{account_id: giro.id, start_date: "2026-09-15"},
            other.id => %{account_id: savings.id, start_date: "2026-10-20"}
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/budget/bank-connections")

      assert render(view) =~ "Konten zugeordnet."

      assert [current, other] =
               BankSync.get_connection!(budget_scope(), connection.id).linked_accounts

      assert {current.account_id, current.start_date} == {giro.id, ~D[2026-09-15]}
      assert {other.account_id, other.start_date} == {savings.id, ~D[2026-10-20]}

      card = "#bank-connection-#{connection.id}"
      assert has_element?(view, card, "Musterbank")
      assert has_element?(view, card, "Freigabe bis 18.04.2027")
      assert has_element?(view, "#{card} #linked-account-#{current.id}", "Girokonto")
      assert has_element?(view, "#{card} #linked-account-#{current.id}", "ab 15.09.2026")
      refute has_element?(view, "#bank-connections-empty")
    end

    test "an account left unlinked stays unlinked", %{conn: conn, giro: giro} do
      connection = connection_fixture()
      [current, other] = connection.linked_accounts

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections/#{connection}/accounts")

      view
      |> form("#bank-accounts-form", %{links: %{current.id => %{account_id: giro.id}}})
      |> render_change()

      refute has_element?(view, "#link-#{other.id}-start-date")

      {:ok, view, _html} =
        view
        |> form("#bank-accounts-form", %{links: %{other.id => %{account_id: ""}}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/budget/bank-connections")

      assert has_element?(view, "#linked-account-#{other.id}", "nicht verknüpft")

      assert [%{account_id: id}, %{account_id: nil, start_date: nil}] =
               BankSync.get_connection!(budget_scope(), connection.id).linked_accounts

      assert id == giro.id
    end

    test "a linked account that no longer takes entries stays linked until unlinked",
         %{conn: conn, giro: giro} do
      connection = linked_connection(giro)
      [current, _other] = connection.linked_accounts
      Repo.update!(Ecto.Changeset.change(giro, closed: true))

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections/#{connection}/accounts")

      assert has_element?(
               view,
               "#link-#{current.id}-account option[selected]",
               "Girokonto (geschlossen)"
             )

      {:ok, view, _html} =
        view
        |> form("#bank-accounts-form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/budget/bank-connections")

      assert has_element?(view, "#linked-account-#{current.id}", "Girokonto")

      assert [%{account_id: id} | _other] =
               BankSync.get_connection!(budget_scope(), connection.id).linked_accounts

      assert id == giro.id

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections/#{connection}/accounts")

      view
      |> form("#bank-accounts-form", %{links: %{current.id => %{account_id: ""}}})
      |> render_submit()

      assert [%{account_id: nil} | _other] =
               BankSync.get_connection!(budget_scope(), connection.id).linked_accounts
    end

    test "a connection without bank accounts says so instead of the form", %{conn: conn} do
      FakeClient.put_session("code-1", %{FakeClient.session() | accounts: []})
      connection = connection_fixture()

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections/#{connection}/accounts")

      assert has_element?(view, "#bank-accounts-empty", "kein Konto freigegeben")
      assert has_element?(view, ~s|#bank-accounts-empty img[src^="/images/plush/landmark"]|)
      refute has_element?(view, "#bank-accounts-form")

      assert {:error, {:live_redirect, %{to: "/budget/bank-connections"}}} =
               render_submit(view, "save_links", %{})
    end

    test "a callback whose state is not the session's connects nothing", %{conn: conn} do
      {conn, _request} = go_to_bank(conn)
      conn = get(conn, ~p"/budget/bank-connections/callback?#{[code: "code-1", state: "forged"]}")

      assert redirected_to(conn) == ~p"/budget/bank-connections"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "passt zu keiner begonnenen"
      assert BankSync.list_connections(budget_scope()) == []
    end

    test "a callback connects once", %{conn: conn} do
      {conn, request} = go_to_bank(conn)
      callback = ~p"/budget/bank-connections/callback?#{[code: "code-1", state: request.state]}"
      conn = get(conn, callback)
      assert [_connection] = BankSync.list_connections(budget_scope())

      conn = get(conn, callback)

      assert redirected_to(conn) == ~p"/budget/bank-connections"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "passt zu keiner begonnenen"
      assert [_connection] = BankSync.list_connections(budget_scope())
    end

    test "a consent refused at the bank connects nothing", %{conn: conn} do
      {conn, request} = go_to_bank(conn)

      conn =
        get(
          conn,
          ~p"/budget/bank-connections/callback?#{[error: "access_denied", state: request.state]}"
        )

      assert redirected_to(conn) == ~p"/budget/bank-connections"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "keine Freigabe"
      assert BankSync.list_connections(budget_scope()) == []
    end

    test "a forged authorize link sends nowhere", %{conn: conn} do
      conn = get(conn, ~p"/budget/bank-connections/authorize?#{[token: "forged"]}")

      assert redirected_to(conn) == ~p"/budget/bank-connections"
    end

    test "an authorize link sends only its user, only for five minutes",
         %{conn: conn, user: user} do
      other = Abakus.UsersFixtures.user_fixture()
      expired = System.system_time(:second) - 5 * 60 - 1

      for {user_id, signed_at} <- [{other.id, nil}, {user.id, expired}] do
        conn = get(conn, authorize_link(user_id, signed_at))

        assert redirected_to(conn) == ~p"/budget/bank-connections"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Der Weg zur Bank ist abgelaufen"
        assert get_session(conn, :bank_auth) == nil
      end

      conn = get(conn, authorize_link(user.id, nil))
      assert redirected_to(conn) == "https://enablebanking.example/auth/state-1"
    end

    test "a connection can be removed", %{conn: conn} do
      connection = connection_fixture()

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")

      confirm_click(view, "#bank-connection-#{connection.id}-remove", "Musterbank trennen?")

      refute has_element?(view, "#bank-connection-#{connection.id}")
      assert BankSync.list_connections(budget_scope()) == []
    end

    test "a connection removed in another tab is removed here too", %{conn: conn} do
      connection = connection_fixture()

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")
      {:ok, _connection} = BankSync.delete_connection(budget_scope(), connection)

      confirm_click(view, "#bank-connection-#{connection.id}-remove", "Musterbank trennen?")

      assert has_element?(view, "#flash-info", "Musterbank ist getrennt.")
      refute has_element?(view, "#bank-connection-#{connection.id}")
    end
  end

  defp linked_connection(account) do
    connection = connection_fixture()
    [current, _savings] = connection.linked_accounts

    {:ok, connection} =
      BankSync.assign_accounts(budget_scope(), connection, %{
        current.id => %{account_id: account.id, start_date: ~D[2026-10-02]}
      })

    connection
  end

  defp go_to_bank(conn) do
    {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")
    render_async(view)

    {:error, {:redirect, %{to: authorize_path}}} =
      view
      |> form("#bank-connect-form", %{country: "DE", bank: "Musterbank"})
      |> render_submit()

    {get(conn, authorize_path), List.last(FakeClient.auth_requests())}
  end

  defp authorize_link(user_id, signed_at) do
    token =
      Phoenix.Token.encrypt(
        AbakusWeb.Endpoint,
        "bank-sync authorize",
        %{
          user_id: user_id,
          url: "https://enablebanking.example/auth/state-1",
          auth: %{state: "state-1"}
        },
        signed_at: signed_at || System.system_time(:second)
      )

    ~p"/budget/bank-connections/authorize?#{[token: token]}"
  end

  test "is the budget owner's" do
    other = Abakus.UsersFixtures.user_fixture()
    conn = log_in_user(build_conn(), other)

    assert_error_sent 404, fn -> get(conn, ~p"/budget/bank-connections") end
  end
end
