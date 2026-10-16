defmodule Abakus.Depot.MarketData.HTTP do
  @moduledoc """
  GET and POST requests over OTP's `:httpc`, with certificate and host name checks.
  """

  # Yahoo answers requests without a browser-like user agent with 429.
  @user_agent "Mozilla/5.0 (compatible; Abakus)"

  @doc """
  Returns the status and body, `:timeout` when the response does not come in time, or
  `:unreachable` when there is none at all. `headers` are
  `{name, value}` strings; a request with them does not follow redirects, as `:httpc` would send
  them, an API key among them, on to wherever a redirect points.
  """
  def get(url, params, headers \\ []) do
    uri = url |> URI.new!() |> with_query(params)
    request = {to_charlist(URI.to_string(uri)), request_headers(headers)}
    request(:get, uri, request, headers == [], [])
  end

  @doc """
  POSTs `body` as JSON and returns like `get/3`; it never follows a redirect. `opts` may set the
  `:timeout` in milliseconds, two minutes by default.
  """
  def post_json(url, body, headers \\ [], opts \\ []) do
    request =
      {to_charlist(url), request_headers(headers), ~c"application/json", JSON.encode!(body)}

    request(:post, URI.new!(url), request, false, opts)
  end

  defp request(method, uri, request, follow_redirects?, opts) do
    http_options = [
      timeout: Keyword.get(opts, :timeout, 120_000),
      connect_timeout: 15_000,
      ssl: ssl_options(uri.host),
      autoredirect: follow_redirects?
    ]

    case :httpc.request(method, request, http_options, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, body}} -> {:ok, status, body}
      {:error, :timeout} -> {:error, :timeout}
      {:error, _reason} -> {:error, :unreachable}
    end
  end

  defp request_headers(headers),
    do: Enum.map([{"user-agent", @user_agent} | headers], &charlists/1)

  defp with_query(uri, []), do: uri
  defp with_query(uri, params), do: URI.append_query(uri, URI.encode_query(params))

  defp charlists({name, value}), do: {to_charlist(name), to_charlist(value)}

  defp ssl_options(host) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      depth: 99,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end
end
