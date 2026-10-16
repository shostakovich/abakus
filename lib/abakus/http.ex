defmodule Abakus.HTTP do
  @moduledoc """
  Requests to outside services over OTP's `:httpc`, with certificate and host name checks, a
  deadline for the whole response and a cap on the body. Errors are only `:timeout`,
  `:too_large` and `:unreachable`, never a reason that could hold the request's credentials.
  """

  @type header :: {String.t(), String.t()}
  @type reason :: :timeout | :too_large | :unreachable

  # Yahoo answers requests without a browser-like user agent with 429.
  @user_agent "Mozilla/5.0 (compatible; Abakus)"
  @timeout 120_000
  @connect_timeout 15_000
  @max_body 32 * 1024 * 1024

  @doc "GETs `url` and returns the status and body; options and errors as `request/3`."
  @spec get(String.t(), keyword()) :: {:ok, pos_integer(), binary()} | {:error, reason()}
  def get(url, opts \\ []), do: without_headers(request(:get, url, opts))

  @doc "POSTs to `url` and returns the status and body; options and errors as `request/3`."
  @spec post(String.t(), keyword()) :: {:ok, pos_integer(), binary()} | {:error, reason()}
  def post(url, opts \\ []), do: without_headers(request(:post, url, opts))

  @doc """
  Sends a `:get`, `:post`, `:patch` or `:delete` request and returns the status, the response
  headers (names in lower case) and the body.

  Options: `:headers` as `{name, value}` strings, `:params` for the query, `:json` for a body,
  `:timeout` for the whole response in milliseconds (two minutes), `:max_body` in bytes
  (32 MiB) and `:follow_redirects` (false). A request with headers never follows a redirect, as
  `:httpc` would send them, an API key among them, on to wherever it points.
  """
  @spec request(atom(), String.t(), keyword()) ::
          {:ok, pos_integer(), [header()], binary()} | {:error, reason()}
  def request(method, url, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    timeout = Keyword.get(opts, :timeout, @timeout)
    deadline = System.monotonic_time(:millisecond) + timeout
    uri = url |> URI.new!() |> with_query(Keyword.get(opts, :params, []))

    http_options = [
      timeout: timeout,
      connect_timeout: min(@connect_timeout, timeout),
      autoredirect: Keyword.get(opts, :follow_redirects, false) and headers == [],
      ssl: ssl_options(uri.host)
    ]

    request = build_request(uri, headers, Keyword.fetch(opts, :json))
    stream_options = [sync: false, stream: :self, body_format: :binary]

    case :httpc.request(method, request, http_options, stream_options) do
      {:ok, ref} -> receive_response(ref, deadline, Keyword.get(opts, :max_body, @max_body))
      {:error, reason} -> {:error, reduce(reason)}
    end
  catch
    :exit, _reason -> {:error, :unreachable}
  end

  defp without_headers({:ok, status, _headers, body}), do: {:ok, status, body}
  defp without_headers(error), do: error

  defp with_query(uri, []), do: uri
  defp with_query(uri, params), do: URI.append_query(uri, URI.encode_query(params))

  defp build_request(uri, headers, json) do
    url = uri |> URI.to_string() |> String.to_charlist()
    headers = headers |> with_user_agent() |> Enum.map(&charlists/1)

    case json do
      {:ok, body} -> {url, headers, ~c"application/json", JSON.encode!(body)}
      :error -> {url, headers}
    end
  end

  defp with_user_agent(headers) do
    if Enum.any?(headers, fn {name, _value} -> String.downcase(name) == "user-agent" end),
      do: headers,
      else: [{"user-agent", @user_agent} | headers]
  end

  defp receive_response(ref, deadline, max_body, headers \\ [], chunks \\ []) do
    receive do
      {:http, {^ref, :stream_start, headers}} ->
        receive_response(ref, deadline, max_body, headers, chunks)

      {:http, {^ref, :stream, chunk}} when byte_size(chunk) > max_body ->
        cancel(ref)
        {:error, :too_large}

      {:http, {^ref, :stream, chunk}} ->
        receive_response(ref, deadline, max_body - byte_size(chunk), headers, [chunks | chunk])

      {:http, {^ref, :stream_end, _headers}} ->
        {:ok, 200, strings(headers), IO.iodata_to_binary(chunks)}

      {:http, {^ref, {{_version, _status, _reason}, _headers, body}}}
      when byte_size(body) > max_body ->
        {:error, :too_large}

      {:http, {^ref, {{_version, status, _reason}, headers, body}}} ->
        {:ok, status, strings(headers), body}

      {:http, {^ref, {:error, reason}}} ->
        {:error, reduce(reason)}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        cancel(ref)
        {:error, :timeout}
    end
  end

  defp reduce(:timeout), do: :timeout
  defp reduce(_reason), do: :unreachable

  defp strings(headers) do
    Enum.map(headers, fn {name, value} ->
      {name |> to_string() |> String.downcase(), to_string(value)}
    end)
  end

  defp cancel(ref) do
    :httpc.cancel_request(ref)
    flush(ref)
  end

  defp flush(ref) do
    receive do
      {:http, {^ref, _message}} -> flush(ref)
      {:http, {^ref, _event, _data}} -> flush(ref)
    after
      0 -> :ok
    end
  end

  defp charlists({name, value}), do: {String.to_charlist(name), String.to_charlist(value)}

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
