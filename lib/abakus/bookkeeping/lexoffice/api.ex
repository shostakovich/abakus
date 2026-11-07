defmodule Abakus.Bookkeeping.Lexoffice.API do
  @moduledoc """
  Lexoffice's public API at api.lexware.io, authenticated by the API key as a bearer token. Requests of a process are
  at least half a second apart, so an import stays within Lexoffice's two requests per second; one answered with 429
  is tried again up to three times, a second later each. Lexoffice answers 406 for a voucher without payments, which
  counts as `:not_found`. Config of this module: `:base_url`, `:interval` and `:retry_after` in milliseconds.
  """
  @behaviour Abakus.Bookkeeping.Lexoffice

  alias Abakus.HTTP

  @base_url "https://api.lexware.io/v1/"
  @retries 3

  @impl true
  def get(key, path, params) do
    with {:ok, body} <- request(key, path, params, "application/json", @retries) do
      case JSON.decode(body) do
        {:ok, json} -> {:ok, json}
        {:error, _reason} -> {:error, :invalid_response}
      end
    end
  end

  @impl true
  def download(key, id), do: request(key, "files/" <> segment(id), [], "*/*", @retries)

  defp segment(id), do: URI.encode(id, &URI.char_unreserved?/1)

  defp request(key, path, params, accept, retries) do
    throttle()

    headers = [{"authorization", "Bearer " <> key.()}, {"accept", accept}]

    case HTTP.get(base_url() <> path, params: params, headers: headers) do
      {:ok, 200, body} ->
        {:ok, body}

      {:ok, 429, _body} when retries > 0 ->
        Process.sleep(config(:retry_after, 1_000))
        request(key, path, params, accept, retries - 1)

      {:ok, 429, _body} ->
        {:error, :rate_limited}

      {:ok, 401, _body} ->
        {:error, :unauthorized}

      {:ok, status, _body} when status in [404, 406] ->
        {:error, :not_found}

      {:ok, status, _body} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp throttle do
    interval = config(:interval, 500)
    last = Process.get(__MODULE__)
    now = System.monotonic_time(:millisecond)

    if last && now - last < interval, do: Process.sleep(interval - (now - last))
    Process.put(__MODULE__, System.monotonic_time(:millisecond))
  end

  defp base_url, do: config(:base_url, @base_url)

  defp config(key, default),
    do: Keyword.get(Application.get_env(:abakus, __MODULE__, []), key, default)
end
