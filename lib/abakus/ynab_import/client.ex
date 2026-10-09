defmodule Abakus.YnabImport.Client do
  @moduledoc """
  YNAB's API as far as the import needs it, with a personal access token; the base URL is configurable for tests.
  Uses OTP's `:httpc` with certificate verification, as the import makes only a couple of requests.
  """

  @default_url "https://api.ynab.com/v1"

  # A whole plan's export takes YNAB a while.
  @timeout 120_000

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
    url = base_url() <> path

    headers = [
      {~c"authorization", ~c"Bearer " ++ String.to_charlist(token)},
      {~c"accept", ~c"application/json"}
    ]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_options(url),
           body_format: :binary
         ) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        {:ok, JSON.decode!(body)["data"]}

      {:ok, {{_version, status, _reason}, _headers, body}} ->
        {:error, {:ynab, status, detail(body)}}

      {:error, reason} ->
        {:error, {:ynab, reason}}
    end
  end

  defp http_options(url) do
    ssl =
      if String.starts_with?(url, "https:") do
        host = url |> URI.parse() |> Map.fetch!(:host) |> String.to_charlist()

        [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: host,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      else
        []
      end

    [timeout: @timeout, connect_timeout: 15_000, ssl: ssl]
  end

  defp detail(body) do
    case JSON.decode(body) do
      {:ok, %{"error" => %{"detail" => detail}}} -> detail
      _other -> String.slice(body, 0, 200)
    end
  end

  defp base_url, do: Application.get_env(:abakus, __MODULE__, [])[:base_url] || @default_url
end
