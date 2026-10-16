defmodule Abakus.ExchangeRates.JobTest do
  use Abakus.DataCase

  alias Abakus.{ExchangeRates, FakeExchangeRateSource}
  alias Abakus.ExchangeRates.Job

  setup do
    FakeExchangeRateSource.stub(fn _from -> {:ok, []} end)
  end

  test "a boot without a previous run loads the rates" do
    start_supervised!(Job)

    assert_receive {:rates, ~D[1999-01-04]}
  end

  test "a boot after a run on the same day does not" do
    ExchangeRates.load(DateTime.utc_now(:microsecond))
    assert_received {:rates, _from}

    start_supervised!(Job)

    refute_receive {:rates, _from}, 100
  end
end
