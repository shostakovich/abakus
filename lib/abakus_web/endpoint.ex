defmodule AbakusWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :abakus

  alias Plug.Conn.WrapperError

  @session_options [
    store: :cookie,
    key: "_abakus_key",
    signing_salt: "zFoyQv9M",
    same_site: "Lax",
    # Behind https, ForwardedSSL marks every cookie `secure`.
    http_only: true
  ]

  if Application.compile_env(:abakus, :forwarded_ssl, false) do
    plug AbakusWeb.ForwardedSSL
  end

  # Every response, error pages and static files included; only the socket transports below are
  # dispatched before the plugs.
  plug AbakusWeb.ContentSecurityPolicy

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  @static Plug.Static.init(
            at: "/",
            from: :abakus,
            gzip: not code_reloading?,
            only: AbakusWeb.static_paths(),
            raise_on_missing_only: code_reloading?
          )

  plug :serve_static

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :abakus
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint], log: {__MODULE__, :log_level, []}

  @parsers Plug.Parsers.init(
             parsers: [:urlencoded, :multipart, :json],
             pass: ["*/*"],
             json_decoder: Phoenix.json_library()
           )

  plug :api_format
  plug :parse_body

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug AbakusWeb.Router

  @doc false
  # Health checks poll /up and would flood the log; the paths of mailed links hold their token.
  def log_level(%Plug.Conn{path_info: ["up"]}), do: false
  def log_level(%Plug.Conn{path_info: ["users", "log-in", _token]}), do: false
  def log_level(%Plug.Conn{path_info: ["users", "settings", "confirm-email", _token]}), do: false
  def log_level(_conn), do: :info

  # The API answers JSON, also to a request without an Accept header whose body is no JSON.
  defp api_format(%Plug.Conn{path_info: ["api" | _]} = conn, _opts),
    do: Phoenix.Controller.put_format(conn, "json")

  defp api_format(conn, _opts), do: conn

  # Errors of these plugs are wrapped like the router's, so the error page keeps the headers set
  # above.
  defp serve_static(conn, _opts), do: keep_headers_on_error(conn, Plug.Static, @static)
  defp parse_body(conn, _opts), do: keep_headers_on_error(conn, Plug.Parsers, @parsers)

  defp keep_headers_on_error(conn, plug, opts) do
    plug.call(conn, opts)
  rescue
    error -> WrapperError.reraise(conn, :error, error, __STACKTRACE__)
  end
end
