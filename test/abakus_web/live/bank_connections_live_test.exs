defmodule AbakusWeb.BankConnectionsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.BankSyncFixtures

  alias Abakus.{BankSync, Ledger, Repo}
  alias Abakus.BankSync.{Connection, FakeClient}

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
      account_fixture(name: "Geteilt", shared_expenses: true)
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
      assert has_element?(view, card, "noch nicht abgerufen")
      assert has_element?(view, "#{card} #linked-account-#{current.id}", "Girokonto")
      assert has_element?(view, "#{card} #linked-account-#{current.id}", "ab 15.09.2026")
      refute has_element?(view, "#bank-connections-empty")

      FakeClient.put_transactions("uid-giro", [
        FakeClient.transaction(
          entry_reference: "E-1",
          date: ~D[2026-10-05],
          amount: -4200,
          creditor: "Stadtwerke"
        )
      ])

      FakeClient.put_transactions("uid-savings", [
        FakeClient.transaction(
          transaction_id: "T-1",
          date: ~D[2026-10-20],
          amount: 10_000,
          debtor: "Robert"
        ),
        FakeClient.transaction(transaction_id: "T-0", date: ~D[2026-10-19], amount: 100)
      ])

      view |> element("#bank-connection-#{connection.id}-fetch") |> render_click()
      render_async(view)

      assert [
               {:transactions, "uid-giro", ~D[2026-09-15], psu},
               {:balances, "uid-giro", psu},
               {:transactions, "uid-savings", ~D[2026-10-20], psu},
               {:balances, "uid-savings", psu}
             ] = FakeClient.fetches()

      assert psu.ip_address == "127.0.0.1"
      assert has_element?(view, "#flash-info", "Musterbank abgerufen: 2 neu")
      assert has_element?(view, card, "abgerufen")
      assert has_element?(view, "#{card}-runs li", "von Hand")
      assert has_element?(view, "#{card}-runs li", "2 neu")

      assert [%{payee: %{name: "Stadtwerke"}}] = imported(giro)
      assert [%{payee: %{name: "Robert"}}] = imported(savings)
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

    test "Jetzt abrufen sends the PSU data of the browser", %{conn: conn, giro: giro} do
      linked_connection(giro)

      {:ok, view, _html} =
        conn |> put_req_header("user-agent", "Firefox/140") |> live(~p"/budget/bank-connections")

      fetch(view)

      assert [{:transactions, "uid-giro", _date, psu} | _balances] = FakeClient.fetches()
      assert psu == %{ip_address: "127.0.0.1", user_agent: "Firefox/140"}
    end

    test "Jetzt abrufen takes the client's IP from a trusted proxy", %{conn: conn, giro: giro} do
      mcp = Application.fetch_env!(:abakus, :mcp)
      {:ok, trusted} = Abakus.Network.parse_list("127.0.0.1")
      Application.put_env(:abakus, :mcp, Keyword.put(mcp, :trusted_proxies, trusted))
      on_exit(fn -> Application.put_env(:abakus, :mcp, mcp) end)
      linked_connection(giro)

      {:ok, view, _html} =
        conn
        |> put_req_header("x-forwarded-for", "203.0.113.7")
        |> live(~p"/budget/bank-connections")

      fetch(view)

      assert [{:transactions, "uid-giro", _date, %{ip_address: "203.0.113.7"}} | _balances] =
               FakeClient.fetches()
    end

    test "a failing connection shows its error, and /up fails after a day",
         %{conn: conn, giro: giro} do
      connection = linked_connection(giro)
      FakeClient.fail_fetches(:timeout)

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")
      fetch(view)

      card = "#bank-connection-#{connection.id}"
      assert has_element?(view, "#flash-error", "Abruf von Musterbank fehlgeschlagen")
      assert has_element?(view, "#{card}-error", "Der letzte Abruf ist fehlgeschlagen")
      assert has_element?(view, "#{card}-error", "Girokonto: Enable Banking hat nicht")
      assert has_element?(view, "#{card}-runs li", "fehlgeschlagen")

      assert build_conn() |> get(~p"/up") |> json_response(200) == %{"status" => "up"}

      Repo.update_all(Connection,
        set: [inserted_at: ~U[2026-10-19 09:00:00.000000Z]]
      )

      ExUnit.CaptureLog.capture_log(fn ->
        assert build_conn() |> get(~p"/up") |> json_response(503) == %{"status" => "down"}
      end)
    end

    test "a connection without a linked account cannot fetch", %{conn: conn} do
      connection = connection_fixture()

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")

      assert has_element?(view, "#bank-connection-#{connection.id}-fetch[disabled]")
    end

    test "Freigabe erneuern renews the consent at the bank and keeps the linked accounts",
         %{conn: conn, giro: giro} do
      connection = linked_connection(giro)

      Repo.update_all(Connection, set: [valid_until: ~U[2026-11-03 10:00:00.000000Z]])

      # The bank's account ids change with the new session; the IBAN stays.
      FakeClient.put_session("code-2", %{
        session_id: "session-2",
        valid_until: ~U[2027-05-01 10:00:00.000000Z],
        accounts: [
          %{uid: "uid-giro-2", name: "Girokonto", iban: "DE02100200300000004711"},
          %{uid: "uid-card", name: "Kreditkarte", iban: nil}
        ]
      })

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")
      card = "#bank-connection-#{connection.id}"
      assert has_element?(view, card, "Freigabe bis 03.11.2026")

      assert {:error, {:redirect, %{to: authorize_path}}} =
               view |> element("#{card}-renew", "Freigabe erneuern") |> render_click()

      conn = get(conn, authorize_path)
      assert redirected_to(conn) =~ "https://enablebanking.example/auth/"

      request = List.last(FakeClient.auth_requests())
      assert request.bank == %{name: "Musterbank", country: "DE"}
      assert request.valid_until == ~U[2027-04-18 10:00:00Z]

      conn =
        get(conn, ~p"/budget/bank-connections/callback?#{[code: "code-2", state: request.state]}")

      assert redirected_to(conn) == ~p"/budget/bank-connections"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Die Freigabe für Musterbank gilt jetzt bis 01.05.2027."

      assert [renewed] = BankSync.list_connections(budget_scope())
      assert renewed.id == connection.id
      assert renewed.session_id == "session-2"
      assert renewed.valid_until == ~U[2027-05-01 10:00:00.000000Z]

      assert [
               %{provider_account_id: "uid-giro-2", start_date: ~D[2026-10-02]} = current,
               %{provider_account_id: "uid-card", account_id: nil}
             ] = renewed.linked_accounts

      assert current.account_id == giro.id

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")
      assert has_element?(view, card, "Freigabe bis 01.05.2027")
    end

    test "Finanzen shows a banner while a consent ends within 14 days", %{conn: conn} do
      connection_fixture()

      {:ok, view, _html} = live(conn, ~p"/budget")
      refute has_element?(view, "#bank-consent-banner")

      Repo.update_all(Connection, set: [valid_until: ~U[2026-11-03 10:00:00.000000Z]])

      {:ok, view, _html} = live(conn, ~p"/budget")

      assert has_element?(
               view,
               "#bank-consent-banner",
               "Die Freigabe für Musterbank endet am 03.11.2026"
             )

      assert has_element?(
               view,
               ~s|#bank-consent-banner a[href="/budget/bank-connections"]|,
               "Freigabe erneuern"
             )

      {:ok, view, _html} = live(conn, ~p"/depot")
      assert has_element?(view, "#bank-consent-banner", "Musterbank")

      Repo.update_all(Connection, set: [valid_until: ~U[2026-10-19 10:00:00.000000Z]])

      {:ok, view, _html} = live(conn, ~p"/budget")

      assert has_element?(
               view,
               "#bank-consent-banner",
               "Die Freigabe für Musterbank ist abgelaufen"
             )

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")
      refute has_element?(view, "#bank-consent-banner")
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

    test "a connection removed while it is fetched keeps its name in the flash",
         %{conn: conn, giro: giro} do
      connection = linked_connection(giro)
      test = self()

      FakeClient.put_transactions("uid-giro", fn ->
        send(test, {:fetching, self()})
        receive do: (:go -> [])
      end)

      {:ok, view, _html} = live(conn, ~p"/budget/bank-connections")
      view |> element("#bank-connection-#{connection.id}-fetch") |> render_click()
      assert_receive {:fetching, fetch}
      confirm_click(view, "#bank-connection-#{connection.id}-remove", "Musterbank trennen?")
      send(fetch, :go)
      render_async(view)

      assert has_element?(
               view,
               "#flash-error",
               "Abruf von Musterbank fehlgeschlagen. Die Bankverbindung gibt es nicht mehr."
             )

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

  defp imported(account),
    do: budget_scope() |> Ledger.list_transactions(account) |> Enum.filter(&(&1.source == :bank))

  defp fetch(view) do
    [connection] = BankSync.list_connections(budget_scope())
    view |> element("#bank-connection-#{connection.id}-fetch") |> render_click()
    render_async(view)
  end

  test "is the budget owner's" do
    other = Abakus.UsersFixtures.user_fixture()
    conn = log_in_user(build_conn(), other)

    assert_error_sent 404, fn -> get(conn, ~p"/budget/bank-connections") end
  end
end
