defmodule Abakus.FakeExchangeRateSource do
  @moduledoc """
  The rate source in tests. Answers with the function given to `stub/1` and tells the test about
  each call as `{:rates, from}`; without a stub, it has no rates.
  """
  @behaviour Abakus.ExchangeRates.Source

  def stub(fun) do
    Application.put_env(:abakus, __MODULE__, {self(), fun})
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:abakus, __MODULE__) end)
  end

  @impl true
  def rates(from) do
    case Application.get_env(:abakus, __MODULE__) do
      {test, fun} ->
        send(test, {:rates, from})
        fun.(from)

      nil ->
        {:ok, []}
    end
  end
end
