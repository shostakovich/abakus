defmodule Abakus.Depot.MarketDataTest do
  use Abakus.DataCase

  import Abakus.Depot.SecuritiesFixtures

  alias Abakus.Depot.{
    ExchangeRates,
    FakePriceFeed,
    FakeRateSource,
    FakeSymbolSearch,
    FakeSymbolSource,
    MarketData,
    Securities
  }

  alias Abakus.Depot.MarketData.DivvyDiary.Response
  alias Abakus.Depot.Securities.Security

  @now ~U[2026-10-09 16:00:00.000000Z]

  defp usd(date, rate), do: {"USD", date, Decimal.new(rate)}

  describe "run_daily/1" do
    test "stores rates and prices; the next run fetches from the last stored day on" do
      security = security_fixture()
      FakeRateSource.stub(fn _from -> {:ok, [usd(~D[2026-10-08], "1.1186")]} end)

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}])}
      end)

      MarketData.run_daily(@now)

      assert_received {:rates, ~D[1999-01-04]}
      assert_received {:chart, "VGWL.DE", nil}
      assert ExchangeRates.latest("USD").rate == Decimal.new("1.1186")
      assert prices_of(security) == [{~D[2026-10-08], 100, :yahoo}]

      security = Repo.reload!(security)
      assert {security.latest_close, security.latest_date} == {16_666_000_000, ~D[2026-10-09]}
      assert {security.fetched_at, security.fetch_error} == {@now, nil}
      assert MarketData.last_run().ran_at == @now

      MarketData.run_daily(@now)

      assert_received {:rates, ~D[2026-10-08]}
      assert_received {:chart, "VGWL.DE", ~D[2026-10-08]}
    end

    test "PP and manual prices win over Yahoo" do
      security = security_fixture()
      price_fixture(security, ~D[2026-10-05], 100, :pp)
      price_fixture(security, ~D[2026-10-06], 200, :manual)

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-05], 1}, {~D[2026-10-06], 2}])}
      end)

      MarketData.run_daily(@now)

      assert prices_of(security) == [{~D[2026-10-05], 100, :pp}, {~D[2026-10-06], 200, :manual}]
    end

    test "a quote in another currency stores nothing and records the mismatch" do
      security = security_fixture(symbol: "LDGL.L")

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}], 1, "USD")}
      end)

      MarketData.run_daily(@now)

      assert prices_of(security) == []
      security = Repo.reload!(security)
      assert security.fetch_error == "Yahoo notiert LDGL.L in USD, das Wertpapier ist in EUR."
      assert {security.latest_close, security.fetched_at} == {nil, nil}
    end

    test "fetches neither manual nor retired securities" do
      security_fixture(quote_feed: :manual, symbol: nil)
      security_fixture(retired: true)
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([])} end)

      MarketData.run_daily(@now)

      refute_received {:chart, _symbol, _from}
    end

    test "a failing source is recorded, the other one still runs" do
      security = security_fixture(fetched_at: ~U[2026-10-08 16:00:00.000000Z])
      FakeRateSource.stub(fn _from -> {:error, {:http_status, 503}} end)
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:error, :not_found} end)

      MarketData.run_daily(@now)

      assert MarketData.last_run().error == "Die EZB antwortet mit HTTP 503."
      security = Repo.reload!(security)
      assert security.fetch_error == "Yahoo kennt das Symbol VGWL.DE nicht."
      assert security.fetched_at == ~U[2026-10-08 16:00:00.000000Z]
    end

    test "stores nothing a fetch delivered for a symbol changed meanwhile" do
      security = security_fixture()

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        security |> Ecto.Changeset.change(symbol: "VWRL.AS") |> Repo.update!()
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}])}
      end)

      MarketData.run_daily(@now)

      assert prices_of(security) == []
      assert %Security{latest_close: nil, fetched_at: nil} = Repo.reload!(security)
    end

    test "an exception is recorded and does not stop the other securities" do
      broken = security_fixture(symbol: "BROKEN.DE")
      fine = security_fixture(symbol: "FINE.DE")
      FakeRateSource.stub(fn _from -> raise "ECB parser exploded" end)

      FakePriceFeed.stub(fn
        "BROKEN.DE", _from, _now -> raise "chart exploded"
        _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}])}
      end)

      ExUnit.CaptureLog.capture_log(fn -> MarketData.run_daily(@now) end)

      assert MarketData.last_run().error ==
               "Die Wechselkurse ließen sich nicht speichern: ECB parser exploded"

      assert Repo.reload!(broken).fetch_error ==
               "Die Kurse ließen sich nicht speichern: chart exploded"

      assert prices_of(fine) == [{~D[2026-10-08], 100, :yahoo}]
    end

    test "an exit is recorded without its reason, which may hold the request" do
      broken = security_fixture(symbol: "BROKEN.DE")
      fine = security_fixture(symbol: "FINE.DE")
      FakeRateSource.stub(fn _from -> exit({:noproc, [{"authorization", "SECRET"}]}) end)

      FakePriceFeed.stub(fn
        "BROKEN.DE", _from, _now -> exit({:noproc, [{"authorization", "SECRET"}]})
        _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}])}
      end)

      log = ExUnit.CaptureLog.capture_log(fn -> MarketData.run_daily(@now) end)

      assert MarketData.last_run().error == "Die Wechselkurse ließen sich nicht abrufen."
      assert Repo.reload!(broken).fetch_error == "Die Kurse ließen sich nicht abrufen."
      assert prices_of(fine) == [{~D[2026-10-08], 100, :yahoo}]
      assert log =~ "BROKEN.DE"
      refute log =~ "SECRET"
    end

    test "never asks for prices after today" do
      security = security_fixture()
      price_fixture(security, ~D[2026-12-24], 100, :manual)
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:ok, FakePriceFeed.chart_result([])} end)

      MarketData.run_daily(@now)

      assert_received {:chart, "VGWL.DE", ~D[2026-10-09]}
    end

    test "tells subscribers about the update" do
      MarketData.subscribe()

      MarketData.run_daily(@now)

      assert_received :market_data_updated
    end
  end

  describe "run_daily/1 with DivvyDiary" do
    defp composition(countries, sectors \\ %{}),
      do: {:ok, %{composition: %{countries: countries, sectors: sectors}, dividends: []}}

    defp dividend(pay_date, per_share, currency \\ "USD"),
      do: %{
        ex_date: Date.add(pay_date, -14),
        pay_date: pay_date,
        per_share: per_share,
        currency: currency
      }

    test "stores the composition of each security with an ISIN; the next run replaces it" do
      security = security_fixture(isin: "IE00B3RBWM25")
      FakeSymbolSource.stub(fn _isin -> composition(%{"US" => 1}, %{"Energy" => 1}) end)

      MarketData.run_daily(@now)

      assert_received {:symbol, "IE00B3RBWM25"}

      assert %{countries: %{"US" => 1}, sectors: %{"Energy" => 1}, fetched_at: @now} =
               composition_of(security)

      later = DateTime.add(@now, 1, :day)
      FakeSymbolSource.stub(fn _isin -> composition(%{"JP" => 0.4, "BR" => 0.6}) end)

      MarketData.run_daily(later)

      assert %{countries: countries, sectors: sectors, fetched_at: ^later} =
               composition_of(security)

      assert {countries, sectors} == {%{"JP" => 0.4, "BR" => 0.6}, %{}}
    end

    test "stores the dividends of each security with an ISIN without forecasts; the next run replaces them" do
      security = security_fixture(isin: "IE00B3RBWM25")
      other = security_fixture(isin: "IE00B4L5Y983", name: "Other")
      json = "test/fixtures/depot/divvydiary/symbol.json" |> File.read!() |> JSON.decode!()
      FakeSymbolSource.stub(fn _isin -> Response.symbol(json) end)

      MarketData.run_daily(@now)

      assert dividends_of(security) == [
               {~D[2026-03-12], ~D[2026-03-25], 15_000_000, "USD", @now},
               {~D[2026-06-11], ~D[2026-06-24], 31_250_000, "USD", @now},
               {~D[2026-09-10], ~D[2026-09-24], 20_000_000, "USD", @now}
             ]

      later = DateTime.add(@now, 1, :day)
      announced = dividend(~D[2026-12-30], 51_000_000)

      FakeSymbolSource.stub(fn
        "IE00B3RBWM25" ->
          {:ok, %{composition: %{countries: %{}, sectors: %{}}, dividends: [announced]}}

        _isin ->
          {:error, :unreachable}
      end)

      ExUnit.CaptureLog.capture_log(fn -> MarketData.run_daily(later) end)

      assert dividends_of(security) == [
               {~D[2026-12-16], ~D[2026-12-30], 51_000_000, "USD", later}
             ]

      assert length(dividends_of(other)) == 3
    end

    test "asks nothing without an API key" do
      security_fixture(isin: "IE00B3RBWM25")
      FakeSymbolSource.stub(fn _isin -> composition(%{"US" => 1}) end, api_key: false)

      MarketData.run_daily(@now)

      refute_received {:symbol, _isin}
    end

    test "asks neither for securities without an ISIN nor for retired ones" do
      security_fixture(isin: nil)
      security_fixture(isin: "")
      security_fixture(isin: "IE00B4L5Y983", retired: true)
      FakeSymbolSource.stub()

      MarketData.run_daily(@now)

      refute_received {:symbol, _isin}
    end

    test "a failed fetch keeps the stored composition and does not stop the others" do
      failing = security_fixture(isin: "IE00B3RBWM25", name: "A")
      unknown = security_fixture(isin: "IE00B4L5Y983", name: "B")
      fine = security_fixture(isin: "IE00BKM4GZ66", name: "C")
      composition_fixture(failing, %{"US" => 1})

      FakeSymbolSource.stub(fn
        "IE00B3RBWM25" -> {:error, {:http_status, 503}}
        "IE00B4L5Y983" -> {:error, :not_found}
        _isin -> composition(%{"BR" => 1})
      end)

      log = ExUnit.CaptureLog.capture_log(fn -> MarketData.run_daily(@now) end)

      assert log =~ "IE00B3RBWM25"
      refute log =~ "IE00B4L5Y983"
      assert %{countries: %{"US" => 1}} = composition_of(failing)
      assert composition_of(unknown) == nil
      assert %{countries: %{"BR" => 1}} = composition_of(fine)
    end

    test "an exception is logged and does not stop the others" do
      security_fixture(isin: "IE00B3RBWM25", name: "A")
      fine = security_fixture(isin: "IE00BKM4GZ66", name: "B")

      FakeSymbolSource.stub(fn
        "IE00B3RBWM25" -> raise "composition exploded"
        _isin -> composition(%{"BR" => 1})
      end)

      log = ExUnit.CaptureLog.capture_log(fn -> MarketData.run_daily(@now) end)

      assert log =~ "composition exploded"
      assert %{countries: %{"BR" => 1}} = composition_of(fine)
    end

    test "an exit is logged without its reason, which may hold the API key" do
      security_fixture(isin: "IE00B3RBWM25", name: "A")
      fine = security_fixture(isin: "IE00BKM4GZ66", name: "B")

      FakeSymbolSource.stub(fn
        "IE00B3RBWM25" -> exit({:noproc, [{"x-api-key", "SECRET"}]})
        _isin -> composition(%{"BR" => 1})
      end)

      log = ExUnit.CaptureLog.capture_log(fn -> MarketData.run_daily(@now) end)

      assert log =~ "IE00B3RBWM25"
      refute log =~ "SECRET"
      assert %{countries: %{"BR" => 1}} = composition_of(fine)
    end
  end

  defp dividends_of(security) do
    for d <- Securities.list_divvy_diary_dividends([security.id]),
        do: {d.ex_date, d.pay_date, d.per_share, d.currency, d.fetched_at}
  end

  describe "divvy_diary_available?/0" do
    test "says whether the source has its API key" do
      refute MarketData.divvy_diary_available?()

      FakeSymbolSource.stub()

      assert MarketData.divvy_diary_available?()
    end
  end

  describe "refresh_stale_quotes/1" do
    test "refreshes quotes older than 15 minutes in the background, without storing prices" do
      stale = security_fixture(checked_at: ~U[2026-10-09 15:44:59.000000Z])
      _fresh = security_fixture(symbol: "LDGL.DE", checked_at: ~U[2026-10-09 15:46:00.000000Z])

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-08], 100}], 42)}
      end)

      MarketData.subscribe()

      MarketData.refresh_stale_quotes(@now)

      assert_receive :market_data_updated
      assert_received {:chart, "VGWL.DE", ~D[2026-10-09]}
      refute_received {:chart, "LDGL.DE", _from}
      assert %Security{latest_close: 42, fetched_at: @now} = Repo.reload!(stale)
      assert prices_of(stale) == []
    end

    test "a failed check counts as a check, so pages opened together fetch once" do
      security = security_fixture()
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:error, :unreachable} end)
      MarketData.subscribe()

      MarketData.refresh_stale_quotes(@now)
      MarketData.refresh_stale_quotes(@now)

      assert_receive :market_data_updated
      assert_received {:chart, "VGWL.DE", _from}
      refute_receive {:chart, "VGWL.DE", _from}, 50

      assert %Security{checked_at: @now, fetch_error: "Yahoo ist nicht erreichbar."} =
               Repo.reload!(security)
    end

    test "does nothing when every quote is fresh" do
      security_fixture(checked_at: ~U[2026-10-09 15:50:00.000000Z])
      MarketData.subscribe()

      assert MarketData.refresh_stale_quotes(@now) == :ok

      refute_receive :market_data_updated, 50
    end
  end

  describe "fetch_in_background/1" do
    test "fetches the whole history and tells subscribers" do
      security = security_fixture()
      price_fixture(security, ~D[2026-10-01], 100, :pp)

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2017-10-26], 50}])}
      end)

      MarketData.subscribe()

      MarketData.fetch_in_background(security)

      assert_receive :market_data_updated
      assert_received {:chart, "VGWL.DE", nil}
      assert {~D[2017-10-26], 50, :yahoo} in prices_of(security)
    end

    test "runs while the sign-in mails' task supervisor is full" do
      security = security_fixture()
      blockers = fill_task_supervisor()
      on_exit(fn -> Enum.each(blockers, &Process.exit(&1, :kill)) end)

      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2017-10-26], 50}])}
      end)

      MarketData.subscribe()

      assert MarketData.fetch_in_background(security) == :ok
      assert_receive :market_data_updated
    end
  end

  defp fill_task_supervisor(pids \\ []) do
    case Task.Supervisor.start_child(Abakus.TaskSupervisor, fn -> Process.sleep(:infinity) end) do
      {:ok, pid} -> fill_task_supervisor([pid | pids])
      {:error, :max_children} -> pids
    end
  end

  describe "lookup_isin/1" do
    defp listing(symbol, exchange, name \\ "iShares Core MSCI EM IMI"),
      do: %{symbol: symbol, name: name, exchange: exchange}

    test "prefers a listing in euros, found by the name of the ISIN's listing" do
      FakeSymbolSearch.stub(fn
        "IE00BKM4GZ66" ->
          {:ok, [listing("EIMI.L", "LSE")]}

        "iShares Core MSCI EM IMI" ->
          {:ok,
           [
             listing("EIMI.L", "LSE"),
             listing("EMIM.AS", "AMS"),
             listing("IS3N.DE", "GER"),
             listing("ACC.DE", "GER", "iShares Core MSCI EM IMI Acc")
           ]}
      end)

      assert MarketData.lookup_isin("IE00BKM4GZ66") ==
               {:ok, %{name: "iShares Core MSCI EM IMI", symbol: "IS3N.DE"}}

      assert_received {:search, "IE00BKM4GZ66"}
      assert_received {:search, "iShares Core MSCI EM IMI"}
    end

    test "takes the first listing without one in euros" do
      FakeSymbolSearch.stub(fn
        "IE00BKM4GZ66" -> {:ok, [listing("EIMI.L", "LSE")]}
        _name -> {:error, :unreachable}
      end)

      assert {:ok, %{symbol: "EIMI.L"}} = MarketData.lookup_isin("IE00BKM4GZ66")
    end

    test "says why it found nothing" do
      FakeSymbolSearch.stub(fn _query -> {:ok, []} end)
      assert {:error, :not_found} = MarketData.lookup_isin("IE00BKM4GZ66")
      assert MarketData.lookup_error(:not_found) == "Yahoo kennt diese ISIN nicht."

      FakeSymbolSearch.stub(fn _query -> {:error, :unreachable} end)
      assert {:error, :unreachable} = MarketData.lookup_isin("IE00BKM4GZ66")
      assert MarketData.lookup_error(:unreachable) == "Yahoo ist nicht erreichbar."
      assert MarketData.lookup_error(:timeout) == "Yahoo ist nicht erreichbar."
      assert MarketData.lookup_error(:too_large) == "Yahoo liefert eine zu große Antwort."
    end
  end

  describe "create_yahoo_security/3" do
    setup do
      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, FakePriceFeed.chart_result([{~D[2026-10-07], 100}, {~D[2026-10-08], 101}])}
      end)

      %{scope: Abakus.UsersFixtures.user_scope_fixture()}
    end

    test "stores the name, currency and price history Yahoo gives", %{scope: scope} do
      assert {:ok, security} =
               MarketData.create_yahoo_security(scope, %{"symbol" => " iusq.de "}, @now)

      assert_received {:chart, "IUSQ.DE", nil}

      assert %Security{
               name: "Weltindex-ETF",
               currency: "EUR",
               quote_feed: :yahoo,
               symbol: "IUSQ.DE",
               isin: nil,
               latest_close: 16_666_000_000,
               fetched_at: @now
             } = Repo.reload!(security)

      assert prices_of(security) == [{~D[2026-10-07], 100, :yahoo}, {~D[2026-10-08], 101, :yahoo}]
    end

    test "reuses the security of a symbol it knows", %{scope: scope} do
      {:ok, first} = MarketData.create_yahoo_security(scope, %{"symbol" => "IUSQ.DE"}, @now)
      assert_received {:chart, "IUSQ.DE", nil}

      assert {:ok, ^first} =
               MarketData.create_yahoo_security(scope, %{"symbol" => "iusq.de"}, @now)

      refute_received {:chart, _symbol, _from}

      known = security_fixture(%{symbol: "VGWL.DE"})

      assert {:ok, %{id: id}} =
               MarketData.create_yahoo_security(scope, %{"symbol" => "VGWL.DE"}, @now)

      assert id == known.id
      assert Repo.aggregate(Security, :count) == 2
    end

    test "reuses the security another request created while Yahoo answered", %{scope: scope} do
      FakePriceFeed.stub(fn _symbol, _from, _now ->
        security_fixture(%{symbol: "IUSQ.DE"})
        {:ok, FakePriceFeed.chart_result([])}
      end)

      assert {:ok, security} =
               MarketData.create_yahoo_security(scope, %{"symbol" => "IUSQ.DE"}, @now)

      assert [%{id: id}] = Repo.all(Security)
      assert security.id == id
    end

    test "names the security after its symbol when Yahoo gives no name", %{scope: scope} do
      FakePriceFeed.stub(fn _symbol, _from, _now ->
        {:ok, %{FakePriceFeed.chart_result([]) | name: nil}}
      end)

      assert {:ok, %{name: "IUSQ.DE"}} =
               MarketData.create_yahoo_security(scope, %{"symbol" => "IUSQ.DE"}, @now)
    end

    test "creates nothing for a symbol Yahoo does not know or cannot deliver", %{scope: scope} do
      FakePriceFeed.stub(fn _symbol, _from, _now -> {:error, :not_found} end)

      assert {:error, changeset} =
               MarketData.create_yahoo_security(scope, %{"symbol" => "NOPE"}, @now)

      assert "Yahoo kennt das Symbol NOPE nicht." in errors_on(changeset).symbol

      FakePriceFeed.stub(fn _symbol, _from, _now -> {:error, :unreachable} end)

      assert {:error, changeset} =
               MarketData.create_yahoo_security(scope, %{"symbol" => "X"}, @now)

      assert "Yahoo ist nicht erreichbar." in errors_on(changeset).symbol

      FakePriceFeed.stub(fn _symbol, _from, _now -> exit(:timeout) end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, changeset} =
                   MarketData.create_yahoo_security(scope, %{"symbol" => "X"}, @now)

          assert "Die Kurse ließen sich nicht abrufen." in errors_on(changeset).symbol
        end)

      assert log =~ "The request for the prices of X exited"

      assert Repo.aggregate(Security, :count) == 0
    end

    test "asks Yahoo nothing for an empty or invalid symbol", %{scope: scope} do
      assert {:error, changeset} =
               MarketData.create_yahoo_security(scope, %{"symbol" => " "}, @now)

      assert "braucht ein Symbol" in errors_on(changeset).symbol

      for symbol <- ["IUSQ DE", "..", ".", "-X", "=X"] do
        assert {:error, changeset} =
                 MarketData.create_yahoo_security(scope, %{"symbol" => symbol}, @now)

        assert "ist kein Yahoo-Symbol" in errors_on(changeset).symbol
      end

      refute_received {:chart, _symbol, _from}
    end

    test "takes indices and currency pairs" do
      for symbol <- ["^GDAXI", "EURUSD=X", "BRK-B", "0P0000IUSQ.F"] do
        assert Securities.change_yahoo_symbol(%{"symbol" => symbol}).valid?
      end
    end
  end
end
