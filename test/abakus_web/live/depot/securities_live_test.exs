defmodule AbakusWeb.Depot.SecuritiesLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures, TaxonomiesFixtures}
  import Abakus.UsersFixtures
  import Setzkasten.Test.Confirm

  alias Abakus.Depot.{FakePriceFeed, FakeSymbolSearch, FakeSymbolSource, Receipts, Settings}
  alias Abakus.Depot.MarketData.JobRun
  alias Abakus.Depot.Securities.Security
  alias Abakus.{ExchangeRates, FakeExchangeRateSource, Repo}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    %{portfolio: portfolio_fixture(scope)}
  end

  defp fresh, do: DateTime.utc_now()

  defp checked(attrs),
    do: security_fixture(Keyword.merge([fetched_at: fresh(), checked_at: fresh()], attrs))

  # Background fetches tell the page over PubSub; once their task is gone, the message is there.
  defp await_background_fetches do
    for pid <- Task.Supervisor.children(Abakus.Depot.TaskSupervisor) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  # The price as it reads, without the invisible places that line the column up.
  defp price_in(lv, security) do
    lv
    |> element("#security-#{security.id} data")
    |> render()
    |> String.replace(~r{<span class="invisible.*?</span>}, "")
    |> String.replace(~r{<[^>]+>}, "")
  end

  defp edit(conn, security) do
    {:ok, lv, _html} = live(conn, ~p"/depot/securities/#{security}/edit")
    lv
  end

  describe "list" do
    test "shows each active security with its source, quote and marks, the retired folded",
         %{conn: conn, scope: scope} do
      vanguard =
        checked(
          isin: "IE00B3RBWM25",
          latest_close: 16_666_000_000,
          latest_date: Date.utc_today()
        )

      failing =
        checked(
          name: "L&G Gerd Kommer",
          symbol: "LDGL.L",
          fetch_error: "Yahoo notiert LDGL.L in USD, das Wertpapier ist in EUR."
        )

      retired = checked(name: "iShares Dividend", symbol: "VGEU.F", retired: true)
      {:ok, _setting} = Settings.update_benchmark(scope, vanguard.id)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      row = lv |> element("#security-#{vanguard.id}") |> render()
      assert row =~ "IE00B3RBWM25"
      assert row =~ "VGWL.DE"
      assert price_in(lv, vanguard) == "166,66 €"
      assert row =~ "Benchmark"
      refute row =~ "ISIN fehlt"

      assert has_element?(lv, "#security-#{failing.id}", "ISIN fehlt")

      assert has_element?(
               lv,
               ~s(a#security-#{failing.id}-error[href="/depot/securities/#{failing.id}/edit"][aria-label="Fehler bei L&G Gerd Kommer ansehen"]),
               "Fehler"
             )

      refute has_element?(lv, "table [data-tip]")
      assert has_element?(lv, "table thead th .sr-only", "Hinweise")

      lv |> element("#security-#{failing.id}-error") |> render_click()

      assert has_element?(
               lv,
               "#security_symbol-help",
               "Yahoo notiert LDGL.L in USD, das Wertpapier ist in EUR."
             )

      assert has_element?(
               lv,
               "#security-#{vanguard.id}-edit[href='/depot/securities/#{vanguard.id}/edit']"
             )

      retired_row = lv |> element("#securities-retired[data-folded] #security-#{retired.id}")
      assert render(retired_row) =~ "VGEU.F"
      refute render(retired_row) =~ "Ausgemustert"

      assert has_element?(lv, "#securities-retired button[aria-expanded=false]", "Ausgemustert")
    end

    test "counts the securities as numbers are written", %{conn: conn} do
      now = DateTime.utc_now()

      Repo.insert_all(
        Security,
        for(
          i <- 1..1000,
          do: %{
            name: "Alt #{i}",
            retired: true,
            quote_feed: :manual,
            currency: "EUR",
            inserted_at: now,
            updated_at: now
          }
        )
      )

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      assert has_element?(lv, "header", "1.000\u00A0ausgemustert")
    end

    test "says quietly that DivvyDiary does not know an ISIN, with its API key only",
         %{conn: conn} do
      security = checked(isin: "IE00B3RBWM25", divvy_diary_unknown: true)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")
      refute has_element?(lv, "#security-#{security.id}-no-fund-data")

      FakeSymbolSource.stub()
      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      assert has_element?(lv, "#security-#{security.id}-no-fund-data", "Keine Fondsdaten")
      refute has_element?(lv, "#security-#{security.id}-error")
    end

    test "shows DivvyDiary's error only with its API key", %{conn: conn} do
      security =
        checked(isin: "IE00B3RBWM25", divvy_diary_error: "DivvyDiary ist nicht erreichbar.")

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")
      refute has_element?(lv, "#security-#{security.id}-error")

      FakeSymbolSource.stub()
      {:ok, lv, _html} = live(conn, ~p"/depot/securities")
      assert has_element?(lv, "#security-#{security.id}-error")
    end

    test "loads the securities once on opening", %{conn: conn} do
      test = self()
      handler = "securities-#{inspect(test)}"

      :telemetry.attach(
        handler,
        [:abakus, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if query =~ "COLLATE NOCASE", do: send(test, :listed)
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      {:ok, _lv, _html} = live(conn, ~p"/depot/securities")

      assert_received :listed
      assert_received :listed
      refute_received :listed
    end

    test "sets a missing price in the slot of the prices", %{conn: conn} do
      security = checked(latest_close: nil)
      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      assert has_element?(lv, "#security-#{security.id} span.tabular-nums", "–")
      assert has_element?(lv, "#security-#{security.id} span.invisible", ",0000")
    end

    test "names the sources of prices and fund data, and fund data needs the API key",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot/securities")
      assert has_element?(lv, "#data-sources", "ohne API-Key keine Fondsdaten")

      FakeSymbolSource.stub()
      Repo.insert!(%JobRun{name: "daily", ran_at: fresh()})
      {:ok, lv, _html} = live(conn, ~p"/depot/securities")
      assert has_element?(lv, "#data-sources", "DivvyDiary")
      assert has_element?(lv, "#data-sources", "täglich mit den Kursen")
      assert has_element?(lv, "#data-sources", "zuletzt gefragt")
      refute has_element?(lv, "#data-sources", "ohne API-Key")
    end

    test "is a tab of all Depots", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot/holdings")

      assert {:ok, lv, _html} =
               lv
               |> element(~s(#depots-tabs a[href="/depot/securities"]), "Wertpapiere")
               |> render_click()
               |> follow_redirect(conn)

      assert has_element?(lv, ~s(#depots-tabs a[href="/depot/securities"][aria-current=page]))
    end

    test "names the exchange rates' date and their last error, and follows a new load",
         %{conn: conn} do
      Repo.insert!(%ExchangeRates.Run{ran_at: fresh(), error: "Die EZB ist nicht erreichbar."})
      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      assert has_element?(lv, "#data-sources", "Die EZB ist nicht erreichbar.")

      FakeExchangeRateSource.stub(fn _from ->
        {:ok, [{"USD", ~D[2026-10-08], Decimal.new("1.1186")}]}
      end)

      :ok = ExchangeRates.load()
      # The sidebar passes the news on as a message of its own, handled after this render.
      render(lv)

      assert has_element?(lv, "#data-sources", "bis 08.10.2026")
      refute has_element?(lv, "#data-sources", "Die EZB ist nicht erreichbar.")
    end

    test "opening the page refreshes stale quotes, not fresh ones", %{conn: conn} do
      stale = security_fixture(latest_close: 100)
      checked(symbol: "LDGL.DE")

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([], 17_012_000_000)}
      end)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")
      await_background_fetches()

      assert_received {:chart, "VGWL.DE", _today}
      refute_received {:chart, "LDGL.DE", _today}
      assert price_in(lv, stale) == "170,12 €"
    end
  end

  describe "add" do
    test "adds a security by its ISIN with name and symbol from Yahoo", %{conn: conn} do
      FakeSymbolSearch.stub(fn _query ->
        {:ok, [%{symbol: "IS3N.DE", name: "iShares Core MSCI EM IMI", exchange: "GER"}]}
      end)

      FakeSymbolSource.stub()
      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      lv |> element("#security-add") |> render_click()
      assert_patch(lv, ~p"/depot/securities/new")

      lv
      |> form("#new-security-form", security: %{isin: "IE00BKM4GZ66"})
      |> render_change(%{"_target" => ["security", "isin"]})

      render_async(lv)
      assert has_element?(lv, "#security_symbol[value='IS3N.DE']")

      html = lv |> form("#new-security-form") |> render_submit()

      assert_patch(lv, ~p"/depot/securities")
      assert html =~ "„iShares Core MSCI EM IMI“ hinzugefügt. DivvyDiary wird gefragt …"

      assert %{symbol: "IS3N.DE", quote_feed: :yahoo} =
               Repo.get_by!(Security, isin: "IE00BKM4GZ66")

      await_background_fetches()
      assert_received {:symbol, "IE00BKM4GZ66"}
    end

    test "adds a security by its Yahoo symbol without touching the benchmark",
         %{conn: conn, scope: scope} do
      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 16_000_000_000}])}
      end)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities/new")
      lv |> element("#new-security-by button[value=symbol]") |> render_click()

      assert lv |> form("#yahoo-security-form", yahoo: %{symbol: "NO PE"}) |> render_submit() =~
               "Ist kein Yahoo-Symbol"

      html = lv |> form("#yahoo-security-form", yahoo: %{symbol: "iusq.de"}) |> render_submit()

      assert html =~ "„Weltindex-ETF“ hinzugefügt."
      security = Repo.get_by!(Security, symbol: "IUSQ.DE")
      assert has_element?(lv, "#security-#{security.id}", "Weltindex-ETF")
      assert Settings.benchmark_id(scope) == nil
    end

    test "offers to bring back a retired security with that symbol", %{conn: conn} do
      retired = checked(symbol: "IUSQ.DE", retired: true)
      FakePriceFeed.stub(fn symbol, _from, _now -> flunk("fetched #{symbol}") end)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities/new")
      lv |> element("#new-security-by button[value=symbol]") |> render_click()
      lv |> form("#yahoo-security-form", yahoo: %{symbol: "iusq.de"}) |> render_submit()

      assert has_element?(
               lv,
               "#yahoo-security-existing",
               "Gibt es schon, ausgemustert: Vanguard FTSE All-World"
             )

      assert Repo.aggregate(Security, :count) == 1

      lv |> element("#yahoo-security-existing a", "Wieder aufnehmen") |> render_click()
      assert_patch(lv, ~p"/depot/securities/#{retired}/edit?reactivate")
      assert has_element?(lv, "#security_retired:not([checked])")
    end

    test "says why Yahoo cannot deliver a symbol", %{conn: conn} do
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:error, :not_found} end)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities/new")
      lv |> element("#new-security-by button[value=symbol]") |> render_click()

      assert lv |> form("#yahoo-security-form", yahoo: %{symbol: "NOPE.DE"}) |> render_submit() =~
               "Yahoo kennt das Symbol NOPE.DE nicht."

      assert Repo.aggregate(Security, :count) == 0
    end
  end

  describe "add, an ISIN that exists" do
    test "names that security instead of looking it up, and adds nothing", %{conn: conn} do
      security = checked(isin: "IE00B3RBWM25")
      FakeSymbolSearch.stub(fn query -> flunk("looked up #{query}") end)
      {:ok, lv, _html} = live(conn, ~p"/depot/securities/new")

      lv
      |> form("#new-security-form", security: %{isin: "IE00B3RBWM25"})
      |> render_change(%{"_target" => ["security", "isin"]})

      assert has_element?(lv, "#new-security-existing", "Gibt es schon: Vanguard FTSE All-World")
      assert has_element?(lv, "#new-security-create[disabled]")
      assert has_element?(lv, "#new-security-fields.hidden")

      lv |> element("#new-security-existing a", "Bearbeiten") |> render_click()
      assert_patch(lv, ~p"/depot/securities/#{security}/edit")
    end

    test "offers to bring back a retired one", %{conn: conn} do
      security = checked(isin: "IE00B3RBWM25", retired: true)
      {:ok, lv, _html} = live(conn, ~p"/depot/securities/new")

      lv
      |> form("#new-security-form", security: %{isin: "IE00B3RBWM25"})
      |> render_change(%{"_target" => ["security", "isin"]})

      lv |> element("#new-security-existing a", "Wieder aufnehmen") |> render_click()

      assert has_element?(lv, "#security_retired:not([checked])")
      assert has_element?(lv, "#security-form", "Kurse und Fondsdaten werden wieder geholt.")

      lv |> form("#security-form") |> render_submit()
      refute Repo.reload!(security).retired
    end

    test "flags an ISIN only at 12 characters or once the field is left", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot/securities/new")

      lv
      |> form("#new-security-form", security: %{isin: "IE00BKM4GZ6"})
      |> render_change(%{"_target" => ["security", "isin"]})

      refute has_element?(lv, "#new-security-form", "Ist keine gültige ISIN")

      lv |> element("#security_isin") |> render_blur()
      assert has_element?(lv, "#new-security-form", "Ist keine gültige ISIN.")

      {:ok, lv, _html} = live(conn, ~p"/depot/securities/new")

      lv
      |> form("#new-security-form", security: %{isin: "IE00BKM4GZ67"})
      |> render_change(%{"_target" => ["security", "isin"]})

      assert has_element?(lv, "#new-security-form", "Ist keine gültige ISIN.")
    end

    test "keeps the typed ISIN while the other way is shown", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot/securities/new")
      lv |> form("#new-security-form", security: %{isin: "IE00B3"}) |> render_change()

      lv |> element("#new-security-by button[value=symbol]") |> render_click()
      assert has_element?(lv, "#new-security-form.hidden")
      lv |> element("#new-security-by button[value=isin]") |> render_click()

      assert has_element?(lv, "#new-security-form:not(.hidden) #security_isin[value=IE00B3]")
    end
  end

  describe "edit" do
    test "warns before a new symbol, then loads its whole history", %{conn: conn} do
      security = checked([])
      price_fixture(security, ~D[2026-10-05], 100, :manual)
      price_fixture(security, ~D[2026-10-07], 300, :yahoo)

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2017-10-26], 50}])}
      end)

      lv = edit(conn, security)
      assert has_element?(lv, "#edit-security-dialog-title", "Vanguard FTSE All-World")

      assert lv |> form("#security-form", security: %{symbol: "VWRL.AS"}) |> render_change() =~
               "Die Kurse werden neu von Yahoo geladen."

      html = lv |> form("#security-form") |> render_submit()

      assert_patch(lv, ~p"/depot/securities")
      assert html =~ "Gespeichert."
      await_background_fetches()
      assert_received {:chart, "VWRL.AS", nil}
      assert prices_of(security) == [{~D[2017-10-26], 50, :yahoo}, {~D[2026-10-05], 100, :manual}]
    end

    test "asks before Yahoo stops, and keeps the prices", %{conn: conn} do
      security = checked([])
      price_fixture(security, ~D[2026-10-07], 300, :yahoo)
      lv = edit(conn, security)

      lv |> form("#security-form", security: %{quote_feed: "manual"}) |> render_change()
      refute has_element?(lv, "#security_symbol")
      confirm_click(lv, "#security-save", "Kursabruf beenden?")

      assert Repo.reload!(security).quote_feed == :manual
      assert prices_of(security) == [{~D[2026-10-07], 300, :yahoo}]
    end

    test "a new ISIN fetches what DivvyDiary knows; one it does not know shows",
         %{conn: conn} do
      security = checked(isin: "IE00B3RBWM25", attributes: %{"ter" => 0.002})
      composition_fixture(security, %{"US" => 1})
      FakeSymbolSource.stub()
      lv = edit(conn, security)

      assert lv
             |> form("#security-form", security: %{isin: "ie00b5ssqt16"})
             |> render_change() =~ "Die Fondsdaten der bisherigen ISIN werden entfernt"

      assert lv |> form("#security-form") |> render_submit() =~
               "Gespeichert. DivvyDiary wird gefragt …"

      await_background_fetches()

      assert_received {:symbol, "IE00B5SSQT16"}
      assert composition_of(security) == nil
      assert %{isin: "IE00B5SSQT16", attributes: %{}} = Repo.reload!(security)

      assert has_element?(lv, "#security-#{security.id}-no-fund-data", "Keine Fondsdaten")
      refute has_element?(lv, "#security-#{security.id}-error")

      lv = edit(conn, security)

      assert has_element?(
               lv,
               "#security_isin-help:not(.text-warning-ink)",
               "DivvyDiary hat keine Fondsdaten zu dieser ISIN."
             )
    end

    test "checks the receipts again after a new, changed or removed ISIN",
         %{conn: conn, scope: scope} do
      security = checked(isin: nil)
      Receipts.subscribe(scope)

      for isin <- ["IE00B3RBWM25", "IE00B5SSQT16", ""] do
        lv = edit(conn, security)
        lv |> form("#security-form", security: %{isin: isin}) |> render_change()

        if isin == "",
          do: confirm_click(lv, "#security-save"),
          else: lv |> form("#security-form") |> render_submit()

        assert_received :receipts_updated
      end

      lv = edit(conn, security)
      lv |> form("#security-form", security: %{retired: "true"}) |> render_submit()
      refute_received :receipts_updated
    end

    test "keeps what is typed when the security comes again with a new quote", %{conn: conn} do
      security = checked(isin: "IE00B3RBWM25")
      lv = edit(conn, security)
      lv |> form("#security-form", security: %{isin: "IE00B5SSQT16"}) |> render_change()

      Repo.update!(
        Ecto.Changeset.change(security, latest_close: 16_416_000_000, latest_date: ~D[2026-11-04])
      )

      send(lv.pid, :market_data_updated)

      assert has_element?(lv, "#security_isin[value=IE00B5SSQT16]")
      assert has_element?(lv, "#security_symbol-help", "Letzter Kurs 164,16")
    end

    test "fits the ISIN field to an ISIN without limiting a pasted one", %{conn: conn} do
      lv = edit(conn, checked(isin: "IE00B3RBWM25"))

      assert has_element?(lv, "#security_isin[size='13']:not([maxlength])")
    end

    test "asks before removing the ISIN, then drops what DivvyDiary delivered", %{conn: conn} do
      security = checked(isin: "IE00B4L5Y983", attributes: %{"ter" => 0.002})
      composition_fixture(security, %{"US" => 1})
      FakeSymbolSource.stub()
      lv = edit(conn, security)

      lv |> form("#security-form", security: %{isin: ""}) |> render_change()
      assert asked(lv, "#security-save").question == "ISIN entfernen?"
      confirm_click(lv, "#security-save")
      await_background_fetches()

      refute_received {:symbol, _isin}
      assert composition_of(security) == nil
      assert %{isin: nil, attributes: %{}} = Repo.reload!(security)
    end

    test "refuses an ISIN another security has", %{conn: conn} do
      security = checked(isin: "IE00B3RBWM25")
      checked(isin: "IE00B5SSQT16", name: "HSBC MSCI Emerging Markets")
      lv = edit(conn, security)

      assert lv
             |> form("#security-form", security: %{isin: "IE00B5SSQT16"})
             |> render_submit() =~ "Gehört schon zu HSBC MSCI Emerging Markets"

      assert Repo.reload!(security).isin == "IE00B3RBWM25"
    end

    test "retires a security", %{conn: conn} do
      security = checked([])
      lv = edit(conn, security)

      lv |> form("#security-form", security: %{retired: "true"}) |> render_submit()

      assert Repo.reload!(security).retired
      assert has_element?(lv, "#securities-retired[data-folded] #security-#{security.id}")
    end

    test "asks before retiring a security still held, then keeps it", %{
      conn: conn,
      scope: scope,
      portfolio: portfolio
    } do
      security = checked([])

      transaction_fixture(scope, ~D[2026-10-01],
        type: :inbound_delivery,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(1)
      )

      lv = edit(conn, security)

      assert lv |> form("#security-form", security: %{retired: "true"}) |> render_change() =~
               "Noch im Bestand: die Kurse bleiben dann stehen."

      confirm_click(lv, "#security-save", "Wertpapier ausmustern?")

      assert Repo.reload!(security).retired
    end

    test "shows what DivvyDiary and Yahoo delivered so far", %{conn: conn} do
      security =
        checked(
          isin: "IE00B3RBWM25",
          attributes: %{"ter" => 0.0022},
          latest_close: 16_416_000_000,
          latest_date: ~D[2026-11-04]
        )

      composition_fixture(security, %{"US" => 1})
      FakeSymbolSource.stub()
      lv = edit(conn, security)

      assert has_element?(lv, "#security-form", "DivvyDiary: TER 0,22")
      assert has_element?(lv, "#security-form", "Stand 08.10.")
      assert has_element?(lv, "#security-form", "Letzter Kurs 164,16")
    end

    test "shows DivvyDiary's error under the ISIN", %{conn: conn} do
      security =
        checked(isin: "IE00B3RBWM25", divvy_diary_error: "DivvyDiary ist nicht erreichbar.")

      FakeSymbolSource.stub()
      lv = edit(conn, security)

      assert has_element?(
               lv,
               "#security_isin-help.text-warning-ink",
               "DivvyDiary ist nicht erreichbar."
             )
    end

    test "looks a new ISIN up and warns when it is another security's", %{conn: conn} do
      security = checked(isin: "IE00B3RBWM25")

      FakeSymbolSearch.stub(fn _query ->
        {:ok, [%{symbol: "IS3N.DE", name: "iShares Core MSCI EM IMI", exchange: "GER"}]}
      end)

      lv = edit(conn, security)

      lv
      |> form("#security-form", security: %{isin: "IE00BKM4GZ66"})
      |> render_change(%{"_target" => ["security", "isin"]})

      render_async(lv)

      assert has_element?(
               lv,
               "#security_isin-help",
               "Laut Yahoo: iShares Core MSCI EM IMI. Ein anderes Wertpapier?"
             )

      assert %{
               question: "ISIN eines anderen Wertpapiers übernehmen?",
               text:
                 "Laut Yahoo gehört sie zu iShares Core MSCI EM IMI; die Kurse kommen weiter von VGWL.DE."
             } = asked(lv, "#security-save")
    end

    test "takes over the symbol Yahoo found for another security's ISIN", %{conn: conn} do
      security = checked(isin: "IE00B3RBWM25")

      FakeSymbolSearch.stub(fn _query ->
        {:ok, [%{symbol: "IS3N.DE", name: "iShares Core MSCI EM IMI", exchange: "GER"}]}
      end)

      FakePriceFeed.stub(fn _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([])} end)
      lv = edit(conn, security)

      lv
      |> form("#security-form", security: %{isin: "IE00BKM4GZ66"})
      |> render_change(%{"_target" => ["security", "isin"]})

      render_async(lv)
      lv |> element("#security-take-symbol", "Symbol IS3N.DE übernehmen") |> render_click()

      assert has_element?(lv, "#security_symbol[value='IS3N.DE']")
      refute has_element?(lv, "#security-take-symbol")

      assert asked(lv, "#security-save").text ==
               "Laut Yahoo gehört sie zu iShares Core MSCI EM IMI."

      confirm_click(lv, "#security-save")
      await_background_fetches()

      assert %{isin: "IE00BKM4GZ66", symbol: "IS3N.DE"} = Repo.reload!(security)
    end

    test "shows the ISIN's help as soon as a retired security is brought back", %{conn: conn} do
      security = checked(isin: nil, retired: true)
      FakeSymbolSource.stub()
      lv = edit(conn, security)

      refute has_element?(lv, "#security_isin-help")

      lv |> form("#security-form", security: %{retired: "false"}) |> render_change()

      assert has_element?(lv, "#security_isin-help", "Bringt TER")
    end

    test "flags a short ISIN once the field is left", %{conn: conn} do
      security = checked(isin: "IE00B3RBWM25")
      lv = edit(conn, security)

      lv |> form("#security-form", security: %{isin: "IE00B3RBWM2"}) |> render_change()
      refute has_element?(lv, "#security-form", "Ist keine gültige ISIN")

      lv |> element("#security_isin") |> render_blur()
      assert has_element?(lv, "#security-form", "Ist keine gültige ISIN.")
    end

    test "an unknown security goes back to the list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/depot/securities"}}} =
               live(conn, ~p"/depot/securities/999999/edit")
    end
  end

  describe "delete" do
    test "deletes a security without bookings after asking", %{conn: conn} do
      security = checked([])
      price_fixture(security, ~D[2026-10-07], 300, :yahoo)
      lv = edit(conn, security)

      assert asked(lv, "#security-delete").question == "„Vanguard FTSE All-World“ löschen?"
      html = confirm_click(lv, "#security-delete")

      assert html =~ "„Vanguard FTSE All-World“ gelöscht."
      assert Repo.reload(security) == nil
    end

    test "checks the receipts again after deleting", %{conn: conn, scope: scope} do
      security = checked(isin: "IE00B3RBWM25")
      Receipts.subscribe(scope)
      lv = edit(conn, security)

      confirm_click(lv, "#security-delete")

      assert_received :receipts_updated
    end

    test "one another user has assigned stays, the user's own assignments go with it",
         %{conn: conn, scope: scope} do
      security = checked([])
      {_taxonomy, mine} = taxonomy_fixture(scope)
      assignment_fixture(mine, security)
      lv = edit(conn, security)
      assert has_element?(lv, "#security-delete")

      {_taxonomy, theirs} = taxonomy_fixture(user_scope_fixture())
      assignment_fixture(theirs, security)
      confirm_click(lv, "#security-delete")

      assert has_element?(
               lv,
               "#security-delete-reason",
               "Von anderen zugeordnet, nicht löschbar."
             )

      assert Repo.reload(security)

      lv = edit(conn, security)
      refute has_element?(lv, "#security-delete")
    end

    test "a security with bookings can only be retired",
         %{conn: conn, scope: scope, portfolio: portfolio} do
      security = checked([])

      transaction_fixture(scope, ~D[2026-10-01],
        type: :inbound_delivery,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(1)
      )

      lv = edit(conn, security)

      refute has_element?(lv, "#security-delete")
      assert has_element?(lv, "#security-delete-reason", "Hat Buchungen, nicht löschbar.")
    end

    test "a benchmark cannot be deleted", %{conn: conn, scope: scope} do
      security = checked([])
      {:ok, _setting} = Settings.update_benchmark(scope, security.id)
      lv = edit(conn, security)

      refute has_element?(lv, "#security-delete")
      assert has_element?(lv, "#security-delete-reason", "Ist eine Benchmark, nicht löschbar.")
    end

    test "one chosen as benchmark meanwhile stays", %{conn: conn, scope: scope} do
      security = checked([])
      lv = edit(conn, security)
      {:ok, _setting} = Settings.update_benchmark(scope, security.id)

      confirm_click(lv, "#security-delete")

      assert has_element?(lv, "#security-delete-reason", "Ist eine Benchmark")
      assert Repo.reload(security)
    end
  end

  describe "benchmark" do
    test "picks any active security, or none", %{conn: conn, scope: scope} do
      security = security_fixture()
      security_fixture(name: "Altfonds", retired: true)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      refute has_element?(lv, "#benchmark-form option", "Altfonds")
      assert has_element?(lv, ~s(#benchmark-form option:first-child[value=""]), "Keine Benchmark")

      assert lv
             |> form("#benchmark-form", benchmark: %{benchmark_id: security.id})
             |> render_change() =~
               "Vermögen und Performance vergleichen mit Vanguard FTSE All-World."

      assert Settings.benchmark_id(scope) == security.id

      lv |> form("#benchmark-form", benchmark: %{benchmark_id: ""}) |> render_change()
      assert Settings.benchmark_id(scope) == nil
    end

    test "keeps a retired benchmark selectable", %{conn: conn, scope: scope} do
      security_fixture()
      retired = security_fixture(name: "Altfonds", retired: true)
      {:ok, _setting} = Settings.update_benchmark(scope, retired.id)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      assert has_element?(
               lv,
               ~s(#benchmark-form option[selected][value="#{retired.id}"]),
               "Altfonds"
             )
    end

    test "keeps the benchmark when the security is gone", %{conn: conn, scope: scope} do
      security = security_fixture()
      {:ok, _setting} = Settings.update_benchmark(scope, security.id)
      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      for id <- ["#{security.id + 1000}", "abc", "99999999999999999999"] do
        html = render_change(lv, "save_benchmark", %{"benchmark" => %{"benchmark_id" => id}})

        assert html =~ "Dieses Wertpapier gibt es nicht mehr, die Benchmark bleibt."
        assert Settings.benchmark_id(scope) == security.id
      end
    end
  end
end
