defmodule Abakus.ExchangeRatesTest do
  use Abakus.DataCase

  alias Abakus.{ExchangeRates, FakeExchangeRateSource}
  alias Abakus.ExchangeRates.ExchangeRate

  @now ~U[2026-10-09 15:00:00.000000Z]

  defp rate(currency, date, value), do: {currency, date, Decimal.new(value)}

  defp manual(currency, date, value) do
    Repo.insert!(%ExchangeRate{
      currency: currency,
      date: date,
      source: :manual,
      rate: Decimal.new(value)
    })
  end

  describe "load/1" do
    test "an empty table loads from the first ECB day on, a later run from the last stored day" do
      FakeExchangeRateSource.stub(fn _from -> {:ok, [rate("USD", ~D[2026-10-08], "1.1186")]} end)

      assert ExchangeRates.load(@now) == :ok

      assert_received {:rates, ~D[1999-01-04]}
      assert ExchangeRates.latest("USD").rate == Decimal.new("1.1186")
      assert %{ran_at: @now, error: nil} = ExchangeRates.last_run()

      ExchangeRates.load(@now)

      assert_received {:rates, ~D[2026-10-08]}
    end

    test "a manual rate does not move the start" do
      manual("USD", ~D[2026-10-08], "1.2")
      FakeExchangeRateSource.stub(fn _from -> {:ok, []} end)

      ExchangeRates.load(@now)

      assert_received {:rates, ~D[1999-01-04]}
    end

    test "a failing source is recorded and returned" do
      FakeExchangeRateSource.stub(fn _from -> {:error, {:http_status, 503}} end)

      assert ExchangeRates.load(@now) == {:error, "Die EZB antwortet mit HTTP 503."}
      assert ExchangeRates.last_run().error == "Die EZB antwortet mit HTTP 503."
    end

    test "a too large answer is recorded" do
      FakeExchangeRateSource.stub(fn _from -> {:error, :too_large} end)

      assert ExchangeRates.load(@now) == {:error, "Die EZB liefert eine zu große Antwort."}
    end

    test "a failure in a later chunk stores none of the rates" do
      rates =
        for day <- 0..5999, do: rate("USD", Date.add(~D[2000-01-01], day), "1.1")

      FakeExchangeRateSource.stub(fn _from ->
        {:ok, rates ++ [rate(nil, ~D[2026-10-08], "1")]}
      end)

      ExUnit.CaptureLog.capture_log(fn -> ExchangeRates.load(@now) end)

      assert ExchangeRates.last_date() == nil
      assert ExchangeRates.last_run().error =~ "ließen sich nicht speichern"
    end

    test "an exception is recorded" do
      FakeExchangeRateSource.stub(fn _from -> raise "ECB parser exploded" end)

      ExUnit.CaptureLog.capture_log(fn -> ExchangeRates.load(@now) end)

      assert ExchangeRates.last_run().error ==
               "Die Wechselkurse ließen sich nicht speichern: ECB parser exploded"
    end

    test "an exit is recorded without its reason, which may hold the request" do
      FakeExchangeRateSource.stub(fn _from -> exit({:noproc, [{"authorization", "SECRET"}]}) end)

      log = ExUnit.CaptureLog.capture_log(fn -> ExchangeRates.load(@now) end)

      assert ExchangeRates.last_run().error == "Die Wechselkurse ließen sich nicht abrufen."
      refute log =~ "SECRET"
    end

    test "the last run is the latest" do
      ExchangeRates.load(DateTime.add(@now, -1, :day))
      ExchangeRates.load(@now)

      assert ExchangeRates.last_run().ran_at == @now
    end
  end

  test "the latest rate of a currency comes with its date" do
    ExchangeRates.store([
      rate("USD", ~D[2026-10-08], "1.1652"),
      rate("USD", ~D[2026-10-09], "1.1701"),
      rate("JPY", ~D[2026-10-10], "161.2")
    ])

    assert %{date: ~D[2026-10-09], rate: rate} = ExchangeRates.latest("USD")
    assert rate == Decimal.new("1.1701")
    assert ExchangeRates.latest("CHF") == nil
  end

  test "storing a rate again replaces it" do
    ExchangeRates.store([rate("USD", ~D[2026-10-08], "1.1652")])

    ExchangeRates.store([
      rate("USD", ~D[2026-10-08], "1.1653"),
      rate("JPY", ~D[2026-10-09], "161.2")
    ])

    assert %{date: ~D[2026-10-08], rate: rate} = ExchangeRates.latest("USD")
    assert rate == Decimal.new("1.1653")
    assert ExchangeRates.last_date() == ~D[2026-10-09]
  end

  test "rates since a date start at the last one on or before it, or at the first one" do
    ExchangeRates.store([
      rate("USD", ~D[2026-10-01], "1.1"),
      rate("USD", ~D[2026-10-02], "1.2"),
      rate("USD", ~D[2026-10-05], "1.5"),
      rate("JPY", ~D[2026-10-05], "160"),
      rate("CHF", ~D[2026-10-05], "0.9")
    ])

    assert Enum.sort(ExchangeRates.list_rates_since(["USD", "JPY"], ~D[2026-10-03])) == [
             rate("JPY", ~D[2026-10-05], "160"),
             rate("USD", ~D[2026-10-02], "1.2"),
             rate("USD", ~D[2026-10-05], "1.5")
           ]
  end

  test "without rates there is no last date" do
    assert ExchangeRates.last_date() == nil
  end

  test "lookups read only ECB rates" do
    ExchangeRates.store([rate("USD", ~D[2026-10-01], "1.1")])
    manual("USD", ~D[2026-10-02], "1.2")
    manual("JPY", ~D[2026-10-02], "160")

    assert ExchangeRates.list_rates_since(["USD", "JPY"], ~D[2026-10-02]) == [
             rate("USD", ~D[2026-10-01], "1.1")
           ]

    assert ExchangeRates.latest("USD").date == ~D[2026-10-01]
    assert ExchangeRates.latest("JPY") == nil
    assert ExchangeRates.last_date() == ~D[2026-10-01]
  end
end
