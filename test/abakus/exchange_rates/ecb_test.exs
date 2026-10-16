defmodule Abakus.ExchangeRates.ECBTest do
  use ExUnit.Case, async: true

  alias Abakus.ExchangeRates.ECB

  test "reads currency, date and rate of every row" do
    assert {:ok, rates} = ECB.parse(File.read!("test/fixtures/ecb/rates.csv"))

    assert length(rates) == 6
    assert {"USD", ~D[2026-10-08], Decimal.new("1.1186")} in rates
    assert {"JPY", ~D[2026-10-06], Decimal.new("178.15")} in rates
  end

  test "an empty body has no rates, as the ECB answers before its first rate of the day" do
    assert ECB.parse("") == {:ok, []}
  end

  test "skips rows without a finite value" do
    csv = """
    KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE
    EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-10-08,
    EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-10-07,NaN
    EXR.D.JPY.EUR.SP00.A,D,JPY,EUR,SP00,A,2026-10-07,Infinity
    """

    assert ECB.parse(csv) == {:ok, []}
  end

  test "skips rows with a rate of 0, below 0 or above 10⁹" do
    csv = """
    KEY,FREQ,CURRENCY,CURRENCY_DENOM,EXR_TYPE,EXR_SUFFIX,TIME_PERIOD,OBS_VALUE
    EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-10-08,0
    EXR.D.USD.EUR.SP00.A,D,USD,EUR,SP00,A,2026-10-07,-1.1
    EXR.D.IDR.EUR.SP00.A,D,IDR,EUR,SP00,A,2026-10-07,1000000001
    EXR.D.IDR.EUR.SP00.A,D,IDR,EUR,SP00,A,2026-10-06,1000000000
    """

    assert ECB.parse(csv) == {:ok, [{"IDR", ~D[2026-10-06], Decimal.new("1000000000")}]}
  end

  test "an unexpected body is reported as such" do
    assert ECB.parse("<html><body>blocked</body></html>") == {:error, :invalid_response}
  end
end
