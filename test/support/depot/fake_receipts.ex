defmodule Abakus.Depot.FakeModel do
  @moduledoc """
  The receipt model in tests. Answers with the function given to `stub/1`, called with the
  receipt's text, or with it and the correction asked for, nil at first; tells the test about
  each call as `{:answer, text}` or, in a correction round, `{:correction, message}`. Without a
  stub no model is configured.
  """
  @behaviour Abakus.Depot.Receipts.Model

  def stub(fun) do
    Application.put_env(:abakus, __MODULE__, {self(), fun})
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:abakus, __MODULE__) end)
  end

  @impl true
  def available?, do: Application.get_env(:abakus, __MODULE__) != nil

  @impl true
  def name, do: if(available?(), do: "Testmodell")

  @impl true
  def answer(_instructions, [{:user, text} | rest], _schema) do
    {test, fun} = Application.fetch_env!(:abakus, __MODULE__)

    correction =
      case List.last(rest) do
        {:user, message} -> message
        nil -> nil
      end

    send(test, if(correction, do: {:correction, correction}, else: {:answer, text}))
    if is_function(fun, 1), do: fun.(text), else: fun.(text, correction)
  end
end

defmodule Abakus.Depot.FakeTextExtractor do
  @moduledoc """
  `pdftotext` in tests: the text given to `stub/1` for every PDF, or the function's result for
  its path; without a stub a PDF has no text layer.
  """
  @behaviour Abakus.Depot.Receipts.TextExtractor

  def stub(text) when is_binary(text), do: stub(fn _path -> {:ok, text} end)

  def stub(fun) when is_function(fun, 1) do
    Application.put_env(:abakus, __MODULE__, fun)
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:abakus, __MODULE__) end)
  end

  @impl true
  def text(path) do
    case Application.get_env(:abakus, __MODULE__) do
      nil -> :error
      fun -> fun.(path)
    end
  end
end
