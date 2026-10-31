defmodule AbakusWeb.ContentSecurityPolicy do
  @moduledoc """
  Phoenix's secure browser headers with a strict content security policy, set in the endpoint
  for every response. Scripts come from the app itself or carry the request's nonce
  (`@csp_nonce`, for Setzkasten's `<.theme_script>`); styles, fonts and images from the app alone.
  LiveView connects back to the endpoint's host.
  """
  @behaviour Plug

  import Plug.Conn

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

  @doc "Lets the page's forms also lead to `target`, e.g. a sign-in that ends in an app's redirect."
  def allow_form_target(conn, target) do
    put_resp_header(
      conn,
      "content-security-policy",
      policy(conn.assigns.csp_nonce, AbakusWeb.Endpoint.url(), [target])
    )
  end

  @doc "The policy for a response whose inline scripts carry `nonce` and whose forms may also lead to `targets`."
  def policy(nonce, endpoint_url \\ AbakusWeb.Endpoint.url(), form_targets \\ []) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self'",
        "font-src 'self'",
        "img-src 'self' data:",
        "connect-src 'self' #{socket_origin(endpoint_url)}",
        "object-src 'none'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        Enum.join(["form-action 'self'" | form_targets], " ")
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
