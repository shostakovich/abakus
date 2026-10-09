defmodule AbakusWeb.ContentSecurityPolicy do
  @moduledoc """
  Phoenix's secure browser headers with a strict content security policy, set in the endpoint
  for every response. Scripts come from the app itself or carry the request's nonce
  (`@csp_nonce`, for `#theme-script`); styles and their images may also come from felt-css.
  LiveView connects back to the endpoint's host.
  """
  @behaviour Plug

  import Plug.Conn

  @felt "https://felt-css.rocu.de"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()

    conn
    |> assign(:csp_nonce, nonce)
    |> Phoenix.Controller.put_secure_browser_headers(%{
      "content-security-policy" => policy(nonce)
    })
  end

  @doc "The policy for a response whose inline scripts carry `nonce`."
  def policy(nonce, endpoint_url \\ AbakusWeb.Endpoint.url()) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self' #{@felt}",
        "font-src 'self'",
        "img-src 'self' #{@felt} data:",
        "connect-src 'self' #{socket_origin(endpoint_url)}",
        "object-src 'none'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'"
      ],
      "; "
    )
  end

  defp socket_origin(endpoint_url) do
    case URI.parse(endpoint_url) do
      %URI{scheme: "https"} = uri -> URI.to_string(%{uri | scheme: "wss", port: nil})
      uri -> URI.to_string(%{uri | scheme: "ws"})
    end
  end
end
