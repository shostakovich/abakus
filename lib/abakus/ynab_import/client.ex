defmodule Abakus.YnabImport.Client do
  @moduledoc """
  YNAB's API as far as the import needs it, with a personal access token; the base URL is configurable for tests.
  """

  alias Abakus.HTTP

  @default_url "https://api.ynab.com/v1"

  # A whole plan's export is large and takes YNAB a while.
  @timeout 120_000
  @max_body 256 * 1024 * 1024

  @doc "The plans the token can see, as YNAB lists them (`id`, `name`, ...)."
  def plans(token) do
    with {:ok, data} <- get(token, "/plans"), do: {:ok, data["plans"]}
  end

  @doc "A plan's full export (`GET /plans/{id}`)."
  def plan(token, id) do
    with {:ok, data} <- get(token, "/plans/" <> URI.encode(id, &URI.char_unreserved?/1)),
         do: {:ok, data["plan"]}
  end

  defp get(token, path) do
    headers = [{"authorization", "Bearer " <> token}, {"accept", "application/json"}]

    case HTTP.get(base_url() <> path, headers: headers, timeout: @timeout, max_body: @max_body) do
      {:ok, 200, body} -> {:ok, JSON.decode!(body)["data"]}
      {:ok, status, body} -> {:error, {:ynab, status, detail(body)}}
      {:error, reason} -> {:error, {:ynab, reason}}
    end
  end

  defp detail(body) do
    case JSON.decode(body) do
      {:ok, %{"error" => %{"detail" => detail}}} -> detail
      _other -> String.slice(body, 0, 200)
    end
  end

  defp base_url, do: Application.get_env(:abakus, __MODULE__, [])[:base_url] || @default_url
end
