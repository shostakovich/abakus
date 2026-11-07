defmodule Abakus.Bookkeeping.FakeLexoffice do
  @moduledoc """
  Lexoffice in tests, answering with the responses recorded in `test/fixtures/bookkeeping/lexoffice`, made up in the
  shape of real ones: a path's JSON in `<path>.json`, a page after the first in `<path>-<page>.json`, a file in
  `files/<id>.pdf`; a path without one is not found. `serve/1` starts it with the one API key it takes and
  responses that replace recorded ones by path; without it every key is refused. It keeps the paths asked for.
  """
  @behaviour Abakus.Bookkeeping.Lexoffice

  @dir "test/fixtures/bookkeeping/lexoffice"

  @doc "Starts Lexoffice for the test with the API key `key` and `responses` by path."
  def serve(key, responses \\ %{}) do
    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start:
        {Agent, :start_link,
         [fn -> %{key: key, responses: responses, requests: []} end, [name: __MODULE__]]}
    })
  end

  @doc "The paths asked for so far, in order."
  def requests, do: Agent.get(__MODULE__, &Enum.reverse(&1.requests))

  @impl true
  def get(key, segments, params) do
    path = Enum.join(segments, "/")
    path = if params[:page] in [nil, 0], do: path, else: "#{path}-#{params[:page]}"

    with :ok <- check(key, path) do
      case recorded(path) do
        nil -> read(path <> ".json", &JSON.decode!/1)
        response -> response
      end
    end
  end

  @impl true
  def download(key, id) do
    path = "files/" <> id

    with :ok <- check(key, path) do
      recorded(path) || read(path <> ".pdf", & &1)
    end
  end

  defp check(key, path) do
    if Process.whereis(__MODULE__) &&
         Agent.get_and_update(
           __MODULE__,
           &{&1.key == key.(), %{&1 | requests: [path | &1.requests]}}
         ),
       do: :ok,
       else: {:error, :unauthorized}
  end

  defp recorded(path), do: Agent.get(__MODULE__, & &1.responses[path])

  defp read(file, decode) do
    case File.read(Path.join(@dir, file)) do
      {:ok, content} -> {:ok, decode.(content)}
      {:error, :enoent} -> {:error, :not_found}
    end
  end
end
