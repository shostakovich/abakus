defmodule AbakusWeb.Depot.SecuritiesLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}

  alias Abakus.Depot.FakePriceFeed
  alias Abakus.Depot.Settings
  alias Abakus.{ExchangeRates, FakeExchangeRateSource, Repo}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    portfolio_fixture(scope)
    :ok
  end

  defp fresh, do: DateTime.utc_now()

  # Background fetches tell the page over PubSub; once their task is gone, the message is there.
  defp await_background_fetches do
    for pid <- Task.Supervisor.children(Abakus.Depot.TaskSupervisor) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  defp save_feed(lv, security, feed, symbol) do
    lv
    |> form("#feed-#{security.id}", feed: %{quote_feed: feed, symbol: symbol})
    |> render_submit()
  end

  test "lists the securities with feed, latest quote and fetch status", %{conn: conn} do
    security_fixture(
      latest_close: 16_666_000_000,
      latest_date: ~D[2026-10-09],
      fetched_at: fresh(),
      checked_at: fresh()
    )

    security_fixture(
      name: "L&G Gerd Kommer",
      symbol: "LDGL.L",
      fetch_error: "Yahoo notiert LDGL.L in USD, das Wertpapier ist in EUR.",
      fetched_at: fresh(),
      checked_at: fresh()
    )

    security_fixture(
      name: "iShares Dividend",
      retired: true,
      fetched_at: fresh(),
      checked_at: fresh()
    )

    {:ok, lv, html} = live(conn, ~p"/depot/securities")

    assert html =~ "Vanguard FTSE All-World"
    assert html =~ "166,66\u00A0€"
    assert html =~ "Yahoo notiert LDGL.L in USD, das Wertpapier ist in EUR."
    assert lv |> element("#retired") |> render() =~ "iShares Dividend"
  end

  test "is a tab of all Depots", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/holdings")

    assert {:ok, lv, _html} =
             lv
             |> element(~s(#depots-tabs a[href="/depot/securities"]), "Wertpapiere")
             |> render_click()
             |> follow_redirect(conn)

    assert has_element?(lv, ~s(#depots-tabs a[href="/depot/securities"][aria-current=page]))
    assert has_element?(lv, sidebar_link("/depot/holdings") <> "[aria-current=page]")
  end

  test "shows until when exchange rates are stored and the last error", %{conn: conn} do
    ExchangeRates.store([{"USD", ~D[2026-10-08], Decimal.new("1.1186")}])

    Repo.insert!(%ExchangeRates.Run{ran_at: fresh(), error: "Die EZB ist nicht erreichbar."})

    {:ok, lv, _html} = live(conn, ~p"/depot/securities")

    rates = lv |> element("#exchange-rates") |> render()
    assert rates =~ "08.10.2026"
    assert rates =~ "Die EZB ist nicht erreichbar."
  end

  test "a load of the exchange rates updates the page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/securities")

    FakeExchangeRateSource.stub(fn _from ->
      {:ok, [{"USD", ~D[2026-10-08], Decimal.new("1.1186")}]}
    end)

    :ok = ExchangeRates.load()
    # The sidebar passes the news on as a message of its own, handled after this render.
    render(lv)

    assert lv |> element("#exchange-rates") |> render() =~ "08.10.2026"
  end

  test "opening the page refreshes stale quotes, not fresh ones", %{conn: conn} do
    stale = security_fixture(latest_close: 100)
    security_fixture(symbol: "LDGL.DE", fetched_at: fresh(), checked_at: fresh())

    FakePriceFeed.stub(fn _symbol, _from, _now ->
      {:ok, FakePriceFeed.chart_result([], 17_012_000_000)}
    end)

    {:ok, lv, _html} = live(conn, ~p"/depot/securities")
    await_background_fetches()

    assert_received {:chart, "VGWL.DE", _today}
    refute_received {:chart, "LDGL.DE", _today}
    assert lv |> element("#security-#{stale.id}") |> render() =~ "170,12\u00A0€"
  end

  test "a new symbol drops the old Yahoo prices and fetches the whole history", %{conn: conn} do
    security = security_fixture(fetched_at: fresh(), checked_at: fresh())
    price_fixture(security, ~D[2026-10-05], 100, :pp)
    price_fixture(security, ~D[2026-10-06], 200, :manual)
    price_fixture(security, ~D[2026-10-07], 300, :yahoo)

    FakePriceFeed.stub(fn _symbol, _from, _now ->
      {:ok, FakePriceFeed.chart_result([{~D[2017-10-26], 50}])}
    end)

    {:ok, lv, _html} = live(conn, ~p"/depot/securities")
    save_id = "feed-#{security.id}-save"
    save_feed(lv, security, "yahoo", "VWRL.AS")
    assert_push_event(lv, "setzkasten:saved", %{id: ^save_id})
    assert has_element?(lv, "##{save_id}.setzkasten-saved")
    await_background_fetches()

    assert_received {:chart, "VWRL.AS", nil}

    assert prices_of(security) == [
             {~D[2017-10-26], 50, :yahoo},
             {~D[2026-10-05], 100, :pp},
             {~D[2026-10-06], 200, :manual}
           ]
  end

  test "switching to manual keeps the Yahoo prices and fetches nothing", %{conn: conn} do
    security = security_fixture(fetched_at: fresh(), checked_at: fresh())
    price_fixture(security, ~D[2026-10-07], 300, :yahoo)
    FakePriceFeed.stub(fn _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([])} end)

    {:ok, lv, _html} = live(conn, ~p"/depot/securities")
    save_feed(lv, security, "manual", "")
    await_background_fetches()

    refute_received {:chart, _symbol, _from}
    assert prices_of(security) == [{~D[2026-10-07], 300, :yahoo}]
    assert Repo.reload!(security).quote_feed == :manual
  end

  test "Yahoo needs a symbol", %{conn: conn} do
    security = security_fixture(fetched_at: fresh(), checked_at: fresh())

    {:ok, lv, _html} = live(conn, ~p"/depot/securities")

    assert save_feed(lv, security, "yahoo", "") =~ "Muss ausgefüllt werden"
    refute_push_event(lv, "setzkasten:saved", %{})
    assert Repo.reload!(security).symbol == "VGWL.DE"
  end

  describe "benchmark" do
    defp benchmark_id(scope), do: Settings.benchmark_id(scope)

    test "creates a security from a Yahoo symbol, prefilled with IUSQ.DE, as the benchmark",
         %{conn: conn, scope: scope} do
      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 16_000_000_000}])}
      end)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")
      assert has_element?(lv, ~s(#yahoo-security input[name="yahoo[symbol]"][value="IUSQ.DE"]))

      html = lv |> form("#yahoo-security") |> render_submit()

      assert_received {:chart, "IUSQ.DE", nil}
      assert html =~ "Weltindex-ETF ist deine Benchmark."
      security = Repo.get_by!(Abakus.Depot.Securities.Security, symbol: "IUSQ.DE")
      assert benchmark_id(scope) == security.id
      assert has_element?(lv, "#security-#{security.id}", "Weltindex-ETF")
      assert has_element?(lv, ~s(#benchmark-form option[selected][value="#{security.id}"]))
      assert prices_of(security) == [{~D[2026-10-08], 16_000_000_000, :yahoo}]
    end

    test "shows why Yahoo cannot deliver a symbol", %{conn: conn, scope: scope} do
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:error, :not_found} end)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      html = lv |> form("#yahoo-security", yahoo: %{symbol: "NOPE.DE"}) |> render_submit()

      assert html =~ "Yahoo kennt das Symbol NOPE.DE nicht."
      assert benchmark_id(scope) == nil
    end

    test "picks any active security as the benchmark, or none", %{conn: conn, scope: scope} do
      security = security_fixture()
      security_fixture(name: "Altfonds", retired: true)

      {:ok, lv, _html} = live(conn, ~p"/depot/securities")

      refute has_element?(lv, "#benchmark-form option", "Altfonds")
      assert has_element?(lv, ~s(#benchmark-form option:first-child[value=""]), "Keine Benchmark")
      refute has_element?(lv, "#benchmark-form option[selected]")

      lv |> form("#benchmark-form", benchmark: %{benchmark_id: security.id}) |> render_change()
      assert benchmark_id(scope) == security.id

      lv |> form("#benchmark-form", benchmark: %{benchmark_id: ""}) |> render_change()
      assert benchmark_id(scope) == nil
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

      lv |> form("#benchmark-form", benchmark: %{benchmark_id: retired.id}) |> render_change()
      assert benchmark_id(scope) == retired.id
    end

    test "keeps the benchmark when the security is gone", %{conn: conn, scope: scope} do
      security = security_fixture()
      {:ok, lv, _html} = live(conn, ~p"/depot/securities")
      lv |> form("#benchmark-form", benchmark: %{benchmark_id: security.id}) |> render_change()

      for id <- ["#{security.id + 1000}", "abc", "99999999999999999999"] do
        html = render_change(lv, "save_benchmark", %{"benchmark" => %{"benchmark_id" => id}})

        assert html =~ "Dieses Wertpapier gibt es nicht mehr, die Benchmark bleibt."
        assert benchmark_id(scope) == security.id
        assert has_element?(lv, ~s(#benchmark-form option[selected][value="#{security.id}"]))
      end
    end
  end
end
