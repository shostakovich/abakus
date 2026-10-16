defmodule AbakusWeb.Depot.BenchmarkTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}

  alias Abakus.Depot.Settings
  alias Abakus.LocalTime

  setup :register_and_log_in_user_without_budget

  # 10 shares delivered yesterday; the benchmark stood at 100 € seven months ago and at 105 €
  # today.
  setup %{scope: scope} do
    today = LocalTime.today()
    security = security_fixture(quote_feed: :manual, latest_date: today, latest_close: price(110))
    price_fixture(security, Date.add(today, -1), price(100), :pp)

    transaction_fixture(scope, Date.add(today, -1),
      type: :inbound_delivery,
      portfolio_id: portfolio_fixture(scope).id,
      security_id: security.id,
      shares: shares(10)
    )

    benchmark =
      security_fixture(%{
        name: "Weltindex-ETF",
        symbol: "IUSQ.DE",
        latest_date: today,
        latest_close: price(105)
      })

    price_fixture(benchmark, Date.shift(today, month: -7), price(100), :yahoo)

    %{benchmark: benchmark}
  end

  defp pick_benchmark(%{scope: scope, benchmark: benchmark}),
    do: {:ok, _setting} = Settings.update_benchmark(scope, benchmark.id)

  # A device that showed the benchmark before sends it when a page connects.
  defp shown_on_this_device(conn), do: put_connect_params(conn, %{"benchmark" => "shown"})

  describe "a user who picked a benchmark" do
    setup ctx do
      pick_benchmark(ctx)
      :ok
    end

    test "sees it hidden until they press „Benchmark“, then here and on the performance screen",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot")

      assert has_element?(lv, "#benchmark-toggle[aria-pressed=false]", "Benchmark")
      refute has_element?(lv, "#benchmark-ttwror")
      assert has_element?(lv, "#ttwror", "zeitgewichtet")

      lv |> element("#benchmark-toggle") |> render_click()

      assert_push_event(lv, "benchmark", %{shown: true})
      assert has_element?(lv, "#benchmark-toggle[aria-pressed=true]")
      assert has_element?(lv, "#ttwror #benchmark-ttwror", "Weltindex-ETF")
      assert has_element?(lv, "#ttwror #benchmark-ttwror", "+5,00 %")
      refute has_element?(lv, "#ttwror", "zeitgewichtet")

      {:ok, lv, _html} = live(shown_on_this_device(conn), ~p"/depot/performance")

      assert has_element?(lv, "#benchmark-toggle[aria-pressed=true]")
      assert has_element?(lv, "#ttwror #benchmark-ttwror", "Weltindex-ETF")
      assert has_element?(lv, "#ttwror #benchmark-ttwror", "+5,00\u00A0%")
    end

    test "draws the shadow portfolio in it on the net worth chart while shown", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot")

      assert_push_event(lv, "net-worth-chart", %{dates: dates, benchmark: values} = chart)
      assert chart.benchmark_shown == false
      assert length(values) == length(dates)
      assert Enum.all?(values, &is_integer/1)
      refute has_element?(lv, "#history-legend", "Weltindex-ETF")

      lv |> element("#benchmark-toggle") |> render_click()

      assert_push_event(lv, "benchmark", %{shown: true})
      assert has_element?(lv, "#history-legend", "Weltindex-ETF")
    end

    test "keeps it shown after a reload on the same device", %{conn: conn} do
      {:ok, lv, _html} = live(shown_on_this_device(conn), ~p"/depot")
      assert has_element?(lv, "#ttwror #benchmark-ttwror", "+5,00 %")
    end

    test "hides it again on the performance screen", %{conn: conn} do
      {:ok, lv, _html} = live(shown_on_this_device(conn), ~p"/depot/performance")

      lv |> element("#benchmark-toggle") |> render_click()

      assert_push_event(lv, "benchmark", %{shown: false})
      refute has_element?(lv, "#benchmark-ttwror")
      assert has_element?(lv, "#ttwror", "p. a.")
    end

    test "gives its TTWROR over the period picked", %{conn: conn, benchmark: benchmark} do
      price_fixture(benchmark, Date.shift(LocalTime.today(), month: -3), price(84), :yahoo)

      {:ok, lv, _html} = live(shown_on_this_device(conn), ~p"/depot/performance?period=max")
      assert has_element?(lv, "#benchmark-ttwror", "+25,00 %")
    end
  end

  test "without a benchmark picked, neither screen has the button", %{conn: conn} do
    for path <- [~p"/depot", ~p"/depot/performance"] do
      {:ok, lv, _html} = live(shown_on_this_device(conn), path)

      refute has_element?(lv, "#benchmark-toggle")
      refute has_element?(lv, "#benchmark-ttwror")
      refute has_element?(lv, "#history-legend", "Weltindex-ETF")
    end

    {:ok, lv, _html} = live(shown_on_this_device(conn), ~p"/depot")
    assert_push_event(lv, "net-worth-chart", %{benchmark: nil})
  end

  test "the note shortens a fund's name to what tells it apart" do
    alias AbakusWeb.Depot.Benchmark

    assert Benchmark.short_name("Welt Aktien UCITS ETF USD (Acc)") == "Welt Aktien"
    assert Benchmark.short_name("Welt Aktien ETF") == "Welt Aktien"
    assert Benchmark.short_name("Welt Aktien (Dist)") == "Welt Aktien"
    assert Benchmark.short_name("Weltindex-ETF") == "Weltindex-ETF"
    assert Benchmark.short_name("Welt Aktien ETF EUR (Acc)") == "Welt Aktien"
    assert Benchmark.short_name("Amundi ETF MSCI World") == "Amundi ETF MSCI World"

    assert Benchmark.short_name("iShares Core S&P 500 UCITS ETF USD (Acc)") ==
             "iShares Core S&P 500"
  end
end
